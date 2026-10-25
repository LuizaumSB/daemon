import AppKit
import SwiftUI
import DaemonCore

/// Um pedaço de janela: tem as próprias abas (como um grupo de editores do VS Code), uma
/// delas selecionada, e mostra o terminal dela.
@MainActor
final class Pane: ObservableObject {
    let id = UUID()
    @Published var tabIDs: [String]
    @Published var selectedID: String?

    init(tabIDs: [String]) {
        self.tabIDs = tabIDs
        self.selectedID = tabIDs.first
    }

    /// Tira a aba; se era a selecionada, seleciona a vizinha.
    func remove(_ tabID: String) {
        guard let index = tabIDs.firstIndex(of: tabID) else { return }
        tabIDs.remove(at: index)
        if selectedID == tabID { selectedID = tabIDs.isEmpty ? nil : tabIDs[max(0, index - 1)] }
    }
}

/// Lado de um pedaço onde uma aba foi solta para dividir a janela.
enum DropEdge { case left, right, top, bottom }

/// Onde a aba solta vai parar: no meio de um pedaço (entra nas abas dele) ou numa borda
/// (divide a janela ali).
enum DropZone: Equatable {
    case center
    case edge(DropEdge)
}

/// A divisão de uma janela, como uma árvore: cada nó é um pedaço ou uma divisão com
/// filhos lado a lado (`sideBySide`) ou um em cima do outro.
@MainActor
indirect enum Layout {
    case pane(Pane)
    case split(sideBySide: Bool, [Layout])

    /// Os pedaços, da esquerda para a direita e de cima para baixo.
    var panes: [Pane] {
        switch self {
        case .pane(let pane): return [pane]
        case .split(_, let children): return children.flatMap(\.panes)
        }
    }

    /// O pedaço do canto de cima à esquerda (é o que divide espaço com o botão de fechar).
    var topLeftPane: Pane {
        switch self {
        case .pane(let pane): return pane
        case .split(_, let children): return children[0].topLeftPane
        }
    }

    /// Põe um pedaço novo ao lado de outro. Se já existe uma divisão na mesma direção, ele
    /// entra nela como mais um filho; senão, o pedaço vizinho vira uma divisão nova.
    func inserting(_ new: Pane, beside target: Pane, at edge: DropEdge) -> Layout {
        let sideBySide = edge == .left || edge == .right
        let before = edge == .left || edge == .top
        switch self {
        case .pane(let pane):
            guard pane === target else { return self }
            return .split(sideBySide: sideBySide, before ? [.pane(new), self] : [self, .pane(new)])
        case .split(let direction, let children):
            if direction == sideBySide, let index = children.firstIndex(where: { $0.isPane(target) }) {
                var children = children
                children.insert(.pane(new), at: before ? index : index + 1)
                return .split(sideBySide: direction, children)
            }
            return .split(sideBySide: direction, children.map { $0.inserting(new, beside: target, at: edge) })
        }
    }

    /// Tira um pedaço. Divisões que ficam com um filho só deixam de existir, e divisões na
    /// mesma direção uma dentro da outra viram uma só. `nil` = não sobrou nada.
    func removing(_ target: Pane) -> Layout? {
        switch self {
        case .pane(let pane):
            return pane === target ? nil : self
        case .split(let direction, let children):
            let rest = children.compactMap { $0.removing(target) }
            if rest.isEmpty { return nil }
            if rest.count == 1 { return rest[0] }
            return .split(sideBySide: direction, rest.flatMap { child -> [Layout] in
                if case .split(let inner, let grandchildren) = child, inner == direction { return grandchildren }
                return [child]
            })
        }
    }

    private func isPane(_ target: Pane) -> Bool {
        if case .pane(let pane) = self { return pane === target }
        return false
    }
}

/// Uma janela do Daemon com a sua divisão em pedaços.
@MainActor
final class WorkspaceWindow: NSObject, NSWindowDelegate {
    let window: FloatingPanel
    var layout: Layout
    /// O pedaço com o foco (o último clicado).
    var focusedPane: Pane
    private unowned let workspace: Workspace

    init(layout: Layout, size: NSSize, workspace: Workspace) {
        self.layout = layout
        self.focusedPane = layout.topLeftPane
        self.workspace = workspace
        window = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))
        window.contentMinSize = NSSize(width: 360, height: 260)
        super.init()
        window.delegate = self
        window.onShortcut = { [weak self] event in
            guard let self else { return false }
            return self.workspace.handleShortcut(event, in: self)
        }
    }

    var panes: [Pane] { layout.panes }

    /// Fechar a janela principal só esconde (ela volta pelo mascote). Fechar uma janela extra
    /// devolve as abas dela para a principal: as sessões continuam vivas.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        workspace.windowWillClose(self)
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        workspace.didFocus(focusedPane, in: self)
    }
}

/// Todas as janelas do Daemon: a principal (que o mascote e o ⌥Espaço abrem) e as que
/// nascem quando uma aba é arrastada para fora. Cada aba está em exatamente um pedaço de
/// uma janela, porque a view do terminal de uma sessão só pode estar num lugar por vez.
@MainActor
public final class Workspace {
    let agents: AgentsModel
    /// A primeira é a principal. Se ela ficar vazia, a seguinte vira a principal.
    private var windows: [WorkspaceWindow] = []
    private var paneViews: [UUID: PaneView] = [:]
    private var clickMonitor: Any?

    static let windowSize = NSSize(width: 920, height: 580)

    /// Onde o mascote está agora. A janela principal abre no centro da tela em que ele está.
    public var anchorFrame: (() -> NSRect?)?

    public init(agents: AgentsModel) {
        self.agents = agents
        let first = Pane(tabIDs: agents.tabs.map(\.id))
        windows = [WorkspaceWindow(layout: .pane(first), size: Self.windowSize, workspace: self)]
        render(windows[0])

        agents.isViewing = { [weak self] id in
            guard let self, NSApp.isActive, let (window, pane) = self.locate(id) else { return false }
            return window.window.isVisible && pane.selectedID == id
        }
        // O pedaço com o foco é o último em que o usuário clicou.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = self.windows.first(where: { $0.window === event.window }),
                      let pane = self.pane(at: event.locationInWindow, in: window)
                else { return event }
                self.didFocus(pane, in: window)
                return event
            }
        }
    }

    private var main: WorkspaceWindow { windows[0] }

    public var isVisible: Bool { main.window.isVisible }

    // MARK: - Mostrar e esconder

    /// Clique no mascote ou ⌥Espaço. Se alguma aba está esperando o usuário, abre nela.
    public func toggle() {
        if let waiting = agents.waiting, let (window, _) = locate(waiting.id),
           !(window.window.isKeyWindow && agents.selectedID == waiting.id) {
            focus(waiting.id)
        } else if main.window.isVisible && main.window.isKeyWindow && NSApp.isActive {
            main.window.orderOut(nil)
        } else {
            show()
        }
    }

    /// Mostra a janela principal.
    public func show() {
        present(main)
        focusContent(of: main.focusedPane, in: main)
    }

    private func present(_ window: WorkspaceWindow) {
        if !window.window.isVisible {
            place(window, size: window.window.frame.size, centerOn: window === main ? mascotScreenCenter() : nil)
        }
        // Janela comum: para vir para a frente, o Daemon vira o app ativo.
        NSApp.activate(ignoringOtherApps: true)
        window.window.makeKeyAndOrderFront(nil)
    }

    /// Leva o usuário até uma aba, esteja ela em que janela estiver.
    func focus(_ tabID: String) {
        guard let (window, pane) = locate(tabID) else { return }
        select(tabID, in: pane, of: window)
        present(window)
        focusContent(of: pane, in: window)
    }

    // MARK: - Abas dentro de um pedaço

    func select(_ tabID: String, in pane: Pane, of window: WorkspaceWindow) {
        pane.selectedID = tabID
        refresh(pane)
        didFocus(pane, in: window)
        focusContent(of: pane, in: window)
    }

    func didFocus(_ pane: Pane, in window: WorkspaceWindow) {
        window.focusedPane = pane
        if let id = pane.selectedID { agents.select(id) }
    }

    // MARK: - Arrastar abas

    /// Se a aba pode ser solta ali. Soltar no próprio pedaço, sendo a única aba dele, não
    /// faz sentido (nem no meio, nem dividindo ele com ele mesmo).
    func canDrop(_ tabID: String, on pane: Pane, zone: DropZone) -> Bool {
        guard pane.tabIDs.contains(tabID) else { return true }
        return zone != .center && pane.tabIDs.count > 1
    }

    /// Solta uma aba num pedaço: no meio, ela entra nas abas dele; numa borda, divide ali.
    func drop(_ tabID: String, on target: Pane, zone: DropZone) {
        guard canDrop(tabID, on: target, zone: zone),
              let (sourceWindow, source) = locate(tabID),
              let targetWindow = window(of: target)
        else { return }
        source.remove(tabID)
        switch zone {
        case .center:
            target.tabIDs.append(tabID)
            target.selectedID = tabID
        case .edge(let edge):
            let pane = Pane(tabIDs: [tabID])
            targetWindow.layout = targetWindow.layout.inserting(pane, beside: target, at: edge)
            growIfNeeded(targetWindow, sideBySide: edge == .left || edge == .right)
        }
        removeIfEmpty(source, from: sourceWindow)
        if windows.contains(where: { $0 === sourceWindow }), sourceWindow !== targetWindow { render(sourceWindow) }
        render(targetWindow)
        focus(tabID)
    }

    /// Solta uma aba fora das janelas: ela ganha uma janela própria, onde foi solta.
    func detach(_ tabID: String, at screenPoint: NSPoint) {
        guard let (sourceWindow, source) = locate(tabID) else { return }
        // A única aba da janela: arrastar para fora seria só mover a janela.
        if sourceWindow.panes.count == 1 && source.tabIDs.count == 1 { return }
        source.remove(tabID)
        let size = Self.windowSize
        let window = WorkspaceWindow(layout: .pane(Pane(tabIDs: [tabID])), size: size, workspace: self)
        windows.append(window)
        removeIfEmpty(source, from: sourceWindow)
        if windows.contains(where: { $0 === sourceWindow }) { render(sourceWindow) }
        render(window)
        // O ponteiro fica perto do canto de cima à esquerda, onde estava a aba.
        let origin = NSPoint(x: screenPoint.x - 60, y: screenPoint.y - size.height + 14)
        place(window, size: size, origin: origin)
        focus(tabID)
    }

    func isInsideWindows(_ screenPoint: NSPoint) -> Bool {
        windows.contains { $0.window.isVisible && $0.window.frame.contains(screenPoint) }
    }

    /// Fechou uma janela: se não é a principal, as abas dela voltam para a principal.
    func windowWillClose(_ window: WorkspaceWindow) {
        guard window !== main else { return }
        let target = main.focusedPane
        for pane in window.panes {
            target.tabIDs.append(contentsOf: pane.tabIDs)
            paneViews[pane.id] = nil
        }
        windows.removeAll { $0 === window }
        render(main)
    }

    /// Pedaço vazio sai da divisão; janela vazia fecha (se era a principal, a próxima assume).
    private func removeIfEmpty(_ pane: Pane, from window: WorkspaceWindow) {
        guard pane.tabIDs.isEmpty else { return }
        paneViews[pane.id] = nil
        if let rest = window.layout.removing(pane) {
            window.layout = rest
            if window.focusedPane === pane { window.focusedPane = rest.topLeftPane }
        } else {
            windows.removeAll { $0 === window }
            window.window.delegate = nil
            window.window.orderOut(nil)
        }
    }

    /// Dividiu uma janela estreita: ela cresce para os dois pedaços caberem.
    private func growIfNeeded(_ window: WorkspaceWindow, sideBySide: Bool) {
        var size = window.window.frame.size
        if sideBySide { size.width = max(size.width, 880) } else { size.height = max(size.height, 640) }
        guard size != window.window.frame.size else { return }
        place(window, size: size, centerOn: nil)
    }

    // MARK: - Criar e fechar abas

    /// O "+" de um pedaço: a aba nova entra nele.
    func presentNewAgent(in pane: Pane, of window: WorkspaceWindow) {
        guard let actions = agents.actions else { return }
        let form = NewAgentForm()
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.contentView = NSHostingView(rootView: NewAgentView(
            form: form,
            onCancel: { window.window.endSheet(sheet) },
            onCreate: { [weak self] request in
                guard let self else { return }
                window.window.endSheet(sheet)
                guard let tab = self.agents.create(request) else { return }
                pane.tabIDs.append(tab.id)
                self.select(tab.id, in: pane, of: window)
            }
        ))
        window.window.beginSheet(sheet)

        // A lista de conversas lê vários arquivos: carrega em segundo plano.
        form.loading = true
        Task {
            form.conversations = await actions.recentConversations()
            form.loading = false
        }
    }

    func confirmClose(_ tabID: String) {
        guard let tab = agents.tab(tabID), let (window, pane) = locate(tabID) else { return }
        let alert = NSAlert()
        alert.messageText = "Fechar a aba \(tab.agent.displayName)?"
        alert.informativeText = "A sessão é encerrada. A conversa continua salva e pode ser retomada pelo +."
        alert.addButton(withTitle: "Fechar aba")
        alert.addButton(withTitle: "Cancelar")
        alert.beginSheetModal(for: window.window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            MainActor.assumeIsolated {
                self.agents.remove(tabID)
                pane.remove(tabID)
                self.removeIfEmpty(pane, from: window)
                if self.windows.contains(where: { $0 === window }) { self.render(window) }
            }
        }
    }

    /// Clique direito → "Renomear aba…": pergunta o nome numa folha presa à janela.
    func promptRename(_ tabID: String) {
        guard let tab = agents.tab(tabID), let (window, _) = locate(tabID) else { return }
        let alert = NSAlert()
        alert.messageText = "Renomear a aba"
        alert.addButton(withTitle: "Renomear")
        alert.addButton(withTitle: "Cancelar")
        let field = NSTextField(string: tab.agent.displayName)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window.window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.agents.rename(tabID, to: field.stringValue) }
        }
    }

    /// A aba principal (a primeira) não pode ser fechada.
    func canClose(_ tabID: String) -> Bool { tabID != agents.tabs.first?.id }

    /// Clique direito → "Abrir em nova janela": o mesmo que arrastar para fora, ao lado.
    func openInNewWindow(_ tabID: String) {
        guard let (window, _) = locate(tabID) else { return }
        let frame = window.window.frame
        detach(tabID, at: NSPoint(x: frame.maxX + 40, y: frame.maxY - 20))
    }

    // MARK: - Atalhos

    /// ⌘1, ⌘2, ⌘3… levam à aba, em qualquer janela.
    func handleShortcut(_ event: NSEvent, in window: WorkspaceWindow) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return false }
        if let key = event.charactersIgnoringModifiers, let number = Int(key),
           number >= 1, number <= agents.tabs.count {
            focus(agents.tabs[number - 1].id)
            return true
        }
        return false
    }

    // MARK: - Desenhar

    /// Monta as views da janela a partir da árvore: cada divisão vira um `NSSplitView`.
    private func render(_ window: WorkspaceWindow) {
        for pane in window.panes { paneView(for: pane).removeFromSuperview() }
        let root = window.window.contentView ?? NSView()
        root.subviews.forEach { $0.removeFromSuperview() }
        let content = view(for: window.layout, in: window)
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        window.window.contentView = root
        let topLeft = window.layout.topLeftPane
        for pane in window.panes {
            paneView(for: pane).sharesTitleBar = pane === topLeft
            refresh(pane)
        }
    }

    private func view(for layout: Layout, in window: WorkspaceWindow) -> NSView {
        switch layout {
        case .pane(let pane):
            let view = paneView(for: pane)
            view.workspaceWindow = window
            // Dentro de uma divisão, quem dá o tamanho é o `NSSplitView`, pelo frame.
            view.translatesAutoresizingMaskIntoConstraints = true
            return view
        case .split(let sideBySide, let children):
            let split = EvenSplitView()
            split.isVertical = sideBySide
            split.dividerStyle = .thin
            for child in children { split.addArrangedSubview(view(for: child, in: window)) }
            return split
        }
    }

    private func paneView(for pane: Pane) -> PaneView {
        if let view = paneViews[pane.id] { return view }
        let view = PaneView(pane: pane, workspace: self)
        paneViews[pane.id] = view
        return view
    }

    /// Põe no pedaço o terminal da aba selecionada.
    private func refresh(_ pane: Pane) {
        guard let id = pane.selectedID, let tab = agents.tab(id) else { return }
        paneView(for: pane).show(tab.session.terminalView())
    }

    private func focusContent(of pane: Pane, in window: WorkspaceWindow) {
        guard let id = pane.selectedID, let tab = agents.tab(id) else { return }
        window.window.makeFirstResponder(tab.session.terminalView())
    }

    // MARK: - Onde está cada coisa

    private func locate(_ tabID: String) -> (WorkspaceWindow, Pane)? {
        for window in windows {
            if let pane = window.panes.first(where: { $0.tabIDs.contains(tabID) }) { return (window, pane) }
        }
        return nil
    }

    private func window(of pane: Pane) -> WorkspaceWindow? {
        windows.first { $0.panes.contains { $0 === pane } }
    }

    private func pane(at point: NSPoint, in window: WorkspaceWindow) -> Pane? {
        window.panes.first { pane in
            let view = paneView(for: pane)
            return view.window != nil && view.bounds.contains(view.convert(point, from: nil))
        }
    }

    // MARK: - Posição

    private func mascotScreenCenter() -> NSPoint? {
        let anchor = anchorFrame?()
        let screen = anchor.flatMap { a in
            NSScreen.screens.first { $0.frame.contains(NSPoint(x: a.midX, y: a.midY)) }
        } ?? NSScreen.main
        return screen.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) }
    }

    /// Muda o tamanho em volta de um centro (o da tela do mascote ou o atual da janela).
    private func place(_ window: WorkspaceWindow, size: NSSize, centerOn center: NSPoint?) {
        let frame = window.window.frame
        let center = center ?? NSPoint(x: frame.midX, y: frame.midY)
        place(window, size: size, origin: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    private func place(_ window: WorkspaceWindow, size: NSSize, origin: NSPoint) {
        let probe = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(probe) } ?? window.window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
        var origin = origin
        // Nunca sai da tela.
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        // Sem animação: animando, o terminal muda de tamanho a cada quadro e o CLI
        // redesenha a tela inteira em cada um, o que travava a janela.
        window.window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }
}

/// Divisão nativa do macOS que, na primeira vez que ganha tamanho, reparte o espaço igual
/// entre os pedaços. Depois o usuário arrasta o divisor como quiser.
private final class EvenSplitView: NSSplitView {
    private var distributed = false

    override var dividerColor: NSColor { NSColor(calibratedWhite: 0.22, alpha: 1) }

    override func layout() {
        super.layout()
        let total = isVertical ? bounds.width : bounds.height
        guard !distributed, total > 0, arrangedSubviews.count > 1 else { return }
        distributed = true
        let count = CGFloat(arrangedSubviews.count)
        for index in 0..<(arrangedSubviews.count - 1) {
            setPosition(total * CGFloat(index + 1) / count, ofDividerAt: index)
        }
    }
}

/// `NSButton` usa target/action (estilo Objective-C); isto converte para uma closure.
@MainActor
final class ActionTrampoline: NSObject {
    static let shared = ActionTrampoline()
    var actions: [ObjectIdentifier: () -> Void] = [:]

    @objc func fire(_ sender: NSButton) {
        actions[ObjectIdentifier(sender)]?()
    }
}
