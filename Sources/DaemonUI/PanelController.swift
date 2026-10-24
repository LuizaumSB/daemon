import AppKit
import SwiftUI
import DaemonCore

/// Controla o painel: mostra/esconde, troca de aba e alterna entre bot e terminal completo.
@MainActor
public final class PanelController {
    public enum Mode { case bot, terminal }

    public private(set) var mode: Mode = .bot
    private let agents: AgentsModel
    private let panel: FloatingPanel
    private let root: PanelRootView
    /// Um bot por aba, criado na primeira vez que a aba aparece. Cada um tem o próprio
    /// rascunho, então o texto digitado numa aba não some ao trocar para outra.
    private var botViews: [String: NSView] = [:]

    private static let botSize = NSSize(width: 440, height: 480)
    static let terminalSize = NSSize(width: 920, height: 580)

    /// Onde o mascote está agora. O painel abre no centro da tela em que ele está.
    public var anchorFrame: (() -> NSRect?)?

    public init(agents: AgentsModel) {
        self.agents = agents
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Self.botSize))
        // Closures com `[weak self]` porque o `self` ainda não existe inteiro aqui.
        var select: (String) -> Void = { _ in }
        var add: () -> Void = {}
        var close: (String) -> Void = { _ in }
        var toggleMode: () -> Void = {}
        root = PanelRootView(
            tabBar: NSHostingView(rootView: TabBarView(
                agents: agents,
                onSelect: { select($0) },
                onAdd: { add() },
                onClose: { close($0) }
            )),
            onToggleMode: { toggleMode() }
        )
        panel.contentView = root
        select = { [weak self] in self?.select($0) }
        add = { [weak self] in self?.presentNewAgent() }
        close = { [weak self] in self?.confirmClose($0) }
        toggleMode = { [weak self] in self?.toggleMode() }

        panel.onShortcut = { [weak self] in self?.handleShortcut($0) ?? false }
        agents.isViewing = { [weak self] id in
            guard let self else { return false }
            return self.panel.isVisible && NSApp.isActive && self.agents.selectedID == id
        }
        showContent()
    }

    public var isVisible: Bool { panel.isVisible }

    /// Clique no mascote ou ⌥Espaço. Se alguma aba está esperando o usuário, abre nela.
    public func toggle() {
        if let waiting = agents.waiting, waiting.id != agents.selectedID {
            select(waiting.id)
            show()
        } else if panel.isVisible && panel.isKeyWindow && NSApp.isActive {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    public func show(mode newMode: Mode? = nil) {
        if let newMode { setMode(newMode) }
        if !panel.isVisible { place(size: panel.frame.size) }
        // Janela comum: para vir para a frente, o Daemon vira o app ativo.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        agents.markSeen(agents.selectedID)
        focusCurrent()
    }

    public func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        showContent()
        place(size: newMode == .bot ? Self.botSize : Self.terminalSize)
        focusCurrent()
    }

    private func toggleMode() {
        setMode(mode == .bot ? .terminal : .bot)
    }

    private func select(_ id: String) {
        guard id != agents.selectedID else { return }
        agents.select(id)
        showSelected()
    }

    /// Mostra a aba escolhida. Abas de outros CLIs (Codex...) não têm bot: vão direto
    /// para o terminal.
    private func showSelected() {
        if !agents.selected.agent.usesClaude && mode == .bot {
            setMode(.terminal)
        } else {
            showContent()
            focusCurrent()
        }
    }

    // MARK: - Criar e fechar abas

    /// Abre o "+" como uma folha presa ao painel.
    private func presentNewAgent() {
        guard let actions = agents.actions else { return }
        let form = NewAgentForm()
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.contentView = NSHostingView(rootView: NewAgentView(
            form: form,
            onCancel: { [weak self] in self?.panel.endSheet(sheet) },
            onCreate: { [weak self] request in
                guard let self else { return }
                self.panel.endSheet(sheet)
                self.agents.create(request)
                self.showSelected()
            }
        ))
        panel.beginSheet(sheet)

        // A lista de conversas lê vários arquivos: carrega em segundo plano.
        form.loading = true
        Task {
            form.conversations = await actions.recentConversations()
            form.loading = false
        }
    }

    private func confirmClose(_ id: String) {
        guard let tab = agents.tabs.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Fechar a aba \(tab.agent.displayName)?"
        alert.informativeText = "A sessão é encerrada. A conversa continua salva e pode ser retomada pelo +."
        alert.addButton(withTitle: "Fechar aba")
        alert.addButton(withTitle: "Cancelar")
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            MainActor.assumeIsolated {
                let wasSelected = self.agents.selectedID == id
                self.agents.remove(id)
                self.botViews[id] = nil
                if wasSelected { self.showSelected() }
            }
        }
    }

    /// ⌘1, ⌘2, ⌘3… trocam de aba; ⌘↩ alterna entre bot e terminal.
    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            toggleMode()
            return true
        }
        if let key = event.charactersIgnoringModifiers, let number = Int(key),
           number >= 1, number <= agents.tabs.count {
            select(agents.tabs[number - 1].id)
            return true
        }
        return false
    }

    /// Põe no painel o bot ou o terminal da aba escolhida.
    private func showContent() {
        let tab = agents.selected
        switch mode {
        case .bot:
            root.show(botView(for: tab), mode: mode)
        case .terminal:
            root.show(tab.session.terminalView(), mode: mode)
        }
    }

    private func botView(for tab: BotModel) -> NSView {
        if let view = botViews[tab.id] { return view }
        let view = NSHostingView(rootView: BotView(model: tab, draft: DraftState()))
        botViews[tab.id] = view
        return view
    }

    private func focusCurrent() {
        switch mode {
        case .terminal:
            panel.makeFirstResponder(agents.selected.session.terminalView())
        case .bot:
            // Sem `@FocusState` (macro que exige o Xcode): procura o campo de texto que o
            // SwiftUI criou por baixo e dá o foco direto nele.
            let view = botView(for: agents.selected)
            DispatchQueue.main.async { [weak self] in
                guard let self, let field = Self.firstTextField(in: view) else { return }
                self.panel.makeFirstResponder(field)
            }
        }
    }

    private static func firstTextField(in view: NSView) -> NSView? {
        if view is NSTextField || view is NSTextView, view.acceptsFirstResponder { return view }
        for sub in view.subviews {
            if let found = firstTextField(in: sub) { return found }
        }
        return nil
    }

    /// Posiciona o painel. Ao abrir, no centro da tela onde está o mascote; ao trocar entre
    /// bot e terminal, em volta do centro atual (se o usuário arrastou a janela, ela fica lá).
    private func place(size: NSSize) {
        let center: NSPoint
        let screen: NSScreen?
        if panel.isVisible {
            center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            screen = panel.screen
        } else {
            let anchor = anchorFrame?()
            screen = anchor.flatMap { a in
                NSScreen.screens.first { $0.frame.contains(NSPoint(x: a.midX, y: a.midY)) }
            } ?? NSScreen.main
            center = screen.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? .zero
        }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }

        var origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        // Nunca sai da tela.
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)

        // Sem animação: animando, o terminal muda de tamanho a cada quadro e o CLI
        // redesenha a tela inteira em cada um, o que travava a abertura.
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }
}

/// Conteúdo do painel: as abas e o botão bot/terminal na faixa de cima (a barra de título
/// é transparente) e, embaixo, o bot ou o terminal da aba escolhida.
private final class PanelRootView: NSView {
    private let modeButton: NSButton
    private var content: NSView?
    private static let barHeight: CGFloat = 30

    init(tabBar: NSView, onToggleMode: @escaping () -> Void) {
        modeButton = NSButton(image: Self.icon(for: .bot), target: nil, action: nil)
        super.init(frame: .zero)

        // As abas têm a largura do conteúdo; o resto da faixa fica livre para arrastar a janela.
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        // A faixa fica embaixo da barra de título transparente. Por padrão o SwiftUI desvia
        // dessa barra (a "área segura") e desenha as abas deslocadas, cortadas pela borda.
        if #available(macOS 14, *), let hosting = tabBar as? NSHostingView<TabBarView> {
            hosting.safeAreaRegions = []
        }
        addSubview(tabBar)

        modeButton.isBordered = false
        modeButton.translatesAutoresizingMaskIntoConstraints = false
        modeButton.target = ActionTrampoline.shared
        modeButton.action = #selector(ActionTrampoline.fire(_:))
        ActionTrampoline.shared.actions[ObjectIdentifier(modeButton)] = onToggleMode
        addSubview(modeButton)

        NSLayoutConstraint.activate([
            // Começa depois do botão de fechar (o único visível na barra de título).
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 34),
            tabBar.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.barHeight / 2),
            modeButton.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.barHeight / 2),
            modeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("não usado") }

    func show(_ view: NSView, mode: PanelController.Mode) {
        modeButton.image = Self.icon(for: mode)
        modeButton.toolTip = mode == .bot ? "Abrir terminal completo (⌘↩)" : "Voltar ao bot (⌘↩)"
        guard view !== content else { return }
        content?.removeFromSuperview()
        content = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        // O terminal ganha uma margem; o bot vai até a borda, como antes.
        let inset: CGFloat = mode == .terminal ? 6 : 0
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: Self.barHeight),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }

    private static func icon(for mode: PanelController.Mode) -> NSImage {
        let name = mode == .bot ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
        return NSImage(systemSymbolName: name, accessibilityDescription: mode == .bot ? "Abrir terminal" : "Voltar ao bot")!
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
