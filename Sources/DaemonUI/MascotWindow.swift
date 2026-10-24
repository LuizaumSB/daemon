import AppKit
import SwiftUI
import DaemonCore

/// O mini bot sempre visível: um ícone pequeno que flutua por cima de tudo.
/// Clique abre/fecha o painel; arrastar muda ele de lugar.
@MainActor
public final class MascotWindow {
    private let panel: NSPanel

    public init(agents: AgentsModel, onClick: @escaping () -> Void) {
        let size = NSSize(width: 60, height: 60)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // A sombra é desenhada pelo próprio cubo; a da janela ficaria duplicada.
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = ClickOrDragView(
            content: NSHostingView(rootView: MascotView(agents: agents)),
            onClick: onClick
        )

        if !panel.setFrameUsingName("DaemonMascot"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24))
        }
        // A posição salva pode ser de quando o mascote tinha outro tamanho.
        panel.setContentSize(size)
        panel.setFrameAutosaveName("DaemonMascot")
    }

    public func show() { panel.orderFrontRegardless() }
    public func hide() { panel.orderOut(nil) }
    public var isVisible: Bool { panel.isVisible }
    public var frame: NSRect { panel.frame }
}

/// O que anima o mascote: piscar, olhar para os lados e o pulinho de "precisa de você".
/// Objeto em vez de `@State` pelo mesmo motivo do `DraftState`.
@MainActor
private final class MascotMotion: ObservableObject {
    @Published var blinking = false
    @Published var look: CGFloat = 0
    @Published var hop = false
    private var ticks = 0

    /// Chamado a cada 0,35 s com a cara atual.
    func tick(_ mood: CubeMascot.Mood) {
        ticks += 1
        switch mood {
        case .thinking:
            // Olha para um lado, para o outro, e volta ao meio de vez em quando.
            let positions: [CGFloat] = [-3, -3, 3, 3, 0]
            withAnimation(.easeInOut(duration: 0.3)) { look = positions[ticks % positions.count] }
        case .attention:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { hop.toggle() }
        default:
            if look != 0 || hop {
                withAnimation(.easeOut(duration: 0.2)) { look = 0; hop = false }
            }
        }
        // Pisca a cada ~4 s (menos quando arregalado ou parado).
        if ticks % 12 == 0, mood == .idle || mood == .thinking || mood == .happy {
            blinking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak self] in self?.blinking = false }
        }
    }
}

/// O mascote: o cubo do Daemon com a cara do estado, e um badge com a inicial da aba que
/// está esperando o usuário (ou que tem resposta nova).
private struct MascotView: View {
    @ObservedObject var agents: AgentsModel
    @ObservedObject var motion = MascotMotion()
    // `@Environment` não é macro (diferente do `@State`), então compila sem o Xcode.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if mood == .attention {
                    // Brilho laranja atrás do cubo: chama atenção sem precisar ler nada.
                    Circle().fill(Color.orange.opacity(0.55)).blur(radius: 8).padding(10)
                }
                // No modo escuro, o cubo claro (contrasta com o fundo); no claro, o escuro.
                CubeMascot(mood: mood, dark: colorScheme != .dark, blinking: motion.blinking, look: motion.look)
                    .shadow(color: .black.opacity(0.35), radius: 2.5, y: 1.5)
                    .saturation(mood == .stopped ? 0 : 1)
                    .opacity(mood == .stopped ? 0.7 : 1)
                    .offset(y: motion.hop ? -3 : 0)
                    .padding(3)
            }
            if let badge {
                Text(badge.letter)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.black)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(badge.color))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mood)
        .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { _ in
            motion.tick(mood)
        }
    }

    /// A cara do mascote resume todas as abas: parado > precisa de você > pensando >
    /// resposta nova > pronto.
    private var mood: CubeMascot.Mood {
        guard agents.tabs[0].state == .running else { return .stopped }
        if agents.waiting != nil { return .attention }
        if agents.tabs.contains(where: { $0.activity == .thinking }) { return .thinking }
        if !agents.unread.isEmpty { return .happy }
        return .idle
    }

    /// Laranja: a aba que precisa de você. Branco: aba com resposta que você ainda não viu.
    private var badge: (letter: String, color: Color)? {
        if let waiting = agents.waiting {
            return (String(waiting.agent.displayName.prefix(1)), .orange)
        }
        if let unread = agents.tabs.first(where: { agents.unread.contains($0.id) }) {
            return (String(unread.agent.displayName.prefix(1)), .white)
        }
        return nil
    }
}

/// Distingue clique de arraste: se o mouse andou, move a janela; se não, é clique.
private final class ClickOrDragView: NSView {
    private let onClick: () -> Void
    private var dragged = false

    init(content: NSView, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("não usado") }

    // Todos os cliques vêm para esta view, não para o SwiftUI de dentro.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { dragged = false }

    override func mouseDragged(with event: NSEvent) {
        if !dragged {
            dragged = true
            window?.performDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { onClick() }
    }
}
