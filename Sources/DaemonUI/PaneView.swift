import AppKit
import SwiftUI
import DaemonCore

extension NSPasteboard.PasteboardType {
    /// Tipo próprio para uma aba sendo arrastada. Nenhum outro app aceita esse tipo, então
    /// soltar fora das janelas do Daemon é sempre "ninguém aceitou": vira janela nova.
    static let daemonTab = NSPasteboard.PasteboardType("io.github.luizaumsb.daemon.tab")
}

/// Um pedaço na tela: a faixa de abas em cima e o terminal da aba selecionada embaixo.
/// É daqui que sai o arraste de uma aba (API nativa do macOS, `NSDraggingSession`) e é
/// aqui que uma aba arrastada pode ser solta: no meio (entra nas abas) ou numa borda
/// (divide a janela).
@MainActor
final class PaneView: NSView, NSDraggingSource {
    let pane: Pane
    /// A janela onde este pedaço está agora (muda quando a divisão é refeita).
    weak var workspaceWindow: WorkspaceWindow?
    private unowned let workspace: Workspace

    private let tabBar: NSView
    private let contentArea = NSView()
    private let highlight = NSView()
    private var tabBarLeading: NSLayoutConstraint!
    private weak var shown: NSView?
    /// A aba sendo arrastada a partir deste pedaço (só uma por vez).
    private var draggingTabID: String?

    static let barHeight: CGFloat = 30

    /// O pedaço de cima à esquerda divide a faixa com o botão de fechar da janela.
    var sharesTitleBar = false {
        didSet { tabBarLeading.constant = sharesTitleBar ? 34 : 8 }
    }

    init(pane: Pane, workspace: Workspace) {
        self.pane = pane
        self.workspace = workspace
        var onSelect: (String) -> Void = { _ in }
        var onAdd: () -> Void = {}
        var onClose: (String) -> Void = { _ in }
        var onDragStart: (String) -> Void = { _ in }
        let hosting = TabBarHostingView(rootView: TabBarView(
            pane: pane,
            agents: workspace.agents,
            canClose: { workspace.canClose($0) },
            onSelect: { onSelect($0) },
            onAdd: { onAdd() },
            onClose: { onClose($0) },
            onOpenInNewWindow: { workspace.openInNewWindow($0) },
            onRename: { workspace.promptRename($0) },
            onDragStart: { onDragStart($0) }
        ))
        // A faixa fica embaixo da barra de título transparente. Por padrão o SwiftUI desvia
        // dessa barra (a "área segura") e desenha as abas deslocadas, cortadas pela borda.
        if #available(macOS 14, *) { hosting.safeAreaRegions = [] }
        tabBar = hosting
        super.init(frame: .zero)
        onSelect = { [weak self] id in
            guard let self, let window = self.workspaceWindow else { return }
            workspace.select(id, in: pane, of: window)
        }
        onAdd = { [weak self] in
            guard let self, let window = self.workspaceWindow else { return }
            workspace.presentNewAgent(in: pane, of: window)
        }
        onClose = { workspace.confirmClose($0) }
        onDragStart = { [weak self] id in self?.beginDrag(of: id) }

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabBar)


        contentArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentArea)

        // Destaque de onde a aba vai entrar, por cima de tudo, só durante o arraste.
        highlight.wantsLayer = true
        highlight.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        highlight.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        highlight.layer?.borderWidth = 1.5
        highlight.layer?.cornerRadius = 8
        highlight.isHidden = true
        addSubview(highlight)

        tabBarLeading = tabBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        NSLayoutConstraint.activate([
            tabBarLeading,
            tabBar.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.barHeight / 2),
            tabBar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            contentArea.topAnchor.constraint(equalTo: topAnchor, constant: Self.barHeight),
            contentArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        registerForDraggedTypes([.daemonTab])
    }

    required init?(coder: NSCoder) { fatalError("não usado") }

    /// Põe o terminal da aba selecionada no pedaço.
    func show(_ view: NSView) {
        guard view !== shown || view.superview !== contentArea else { return }
        // Só tira a view anterior se ela ainda está aqui: a aba pode ter ido para outro
        // pedaço, e aí a view já está lá (tirar daqui apagaria ela de lá).
        if let shown, shown.superview === contentArea { shown.removeFromSuperview() }
        shown = view
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(view)
        // Uma margem em volta do terminal, para o texto não encostar na borda.
        let inset: CGFloat = 6
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentArea.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor, constant: -inset),
            view.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor, constant: -inset),
        ])
    }

    // MARK: - Arrastar uma aba daqui

    /// Chamado pelo gesto de arraste da aba (SwiftUI). Começa o arraste nativo do macOS com
    /// o evento de mouse atual; a partir daí quem acompanha o mouse é o próprio sistema.
    private func beginDrag(of tabID: String) {
        guard draggingTabID == nil, let event = NSApp.currentEvent, event.type == .leftMouseDragged,
              let name = workspace.agents.tab(tabID)?.agent.displayName
        else { return }
        draggingTabID = tabID
        let item = NSPasteboardItem()
        item.setString(tabID, forType: .daemonTab)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        let image = Self.dragImage(for: name)
        let point = convert(event.locationInWindow, from: nil)
        dragItem.setDraggingFrame(NSRect(x: point.x - 20, y: point.y - image.size.height / 2,
                                         width: image.size.width, height: image.size.height), contents: image)
        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        // Solta fora: não volta animando para o lugar, porque vai virar janela nova.
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                                     operation: NSDragOperation) {
        MainActor.assumeIsolated {
            defer { draggingTabID = nil }
            // Ninguém aceitou a aba e ela foi solta fora das janelas do Daemon: janela nova.
            guard operation.isEmpty, let id = draggingTabID, !workspace.isInsideWindows(screenPoint) else { return }
            workspace.detach(id, at: screenPoint)
        }
    }

    /// A "pílula" com o nome da aba que acompanha o mouse.
    private static func dragImage(for name: String) -> NSImage {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let text = name as NSString
        let textSize = text.size(withAttributes: attributes)
        let size = NSSize(width: ceil(textSize.width) + 24, height: 24)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(calibratedWhite: 0.2, alpha: 0.95).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
            text.draw(at: NSPoint(x: 12, y: (rect.height - textSize.height) / 2), withAttributes: attributes)
            return true
        }
    }

    // MARK: - Soltar uma aba aqui

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let id = sender.draggingPasteboard.string(forType: .daemonTab) else { return [] }
        let zone = zone(at: convert(sender.draggingLocation, from: nil))
        guard workspace.canDrop(id, on: pane, zone: zone) else {
            highlight.isHidden = true
            return []
        }
        highlight.frame = highlightFrame(for: zone)
        highlight.isHidden = false
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        highlight.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlight.isHidden = true
        guard let id = sender.draggingPasteboard.string(forType: .daemonTab) else { return false }
        let zone = zone(at: convert(sender.draggingLocation, from: nil))
        // Depois do arraste terminar: mexer na divisão no meio dele confunde o sistema.
        DispatchQueue.main.async { [workspace, pane] in workspace.drop(id, on: pane, zone: zone) }
        return true
    }

    /// Na faixa de abas ou no miolo: entra nas abas. Perto de uma borda (um quarto do
    /// tamanho): divide daquele lado.
    private func zone(at point: NSPoint) -> DropZone {
        let content = contentArea.frame
        guard content.contains(point), content.width > 0, content.height > 0 else { return .center }
        let x = (point.x - content.minX) / content.width
        let y = (point.y - content.minY) / content.height   // 0 embaixo, 1 em cima
        let distances: [(DropEdge, CGFloat)] = [(.left, x), (.right, 1 - x), (.bottom, y), (.top, 1 - y)]
        let nearest = distances.min { $0.1 < $1.1 }!
        return nearest.1 < 0.25 ? .edge(nearest.0) : .center
    }

    private func highlightFrame(for zone: DropZone) -> NSRect {
        let content = contentArea.frame.insetBy(dx: 4, dy: 4)
        switch zone {
        case .center: return content
        case .edge(.left): return NSRect(x: content.minX, y: content.minY, width: content.width / 2, height: content.height)
        case .edge(.right): return NSRect(x: content.midX, y: content.minY, width: content.width / 2, height: content.height)
        case .edge(.top): return NSRect(x: content.minX, y: content.midY, width: content.width, height: content.height / 2)
        case .edge(.bottom): return NSRect(x: content.minX, y: content.minY, width: content.width, height: content.height / 2)
        }
    }
}

/// A faixa de abas fica na barra de título, onde arrastar normalmente move a janela.
/// Aqui arrastar é tirar a aba do lugar, então a janela não pode se mover por esta view.
private final class TabBarHostingView: NSHostingView<TabBarView> {
    override var mouseDownCanMoveWindow: Bool { false }
}
