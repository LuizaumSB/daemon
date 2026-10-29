import AppKit
import Combine
import SwiftUI
import DaemonCore

/// O mascote sempre visível: um cubo pequeno que flutua por cima de tudo.
/// Clique abre/fecha o painel; arrastar muda ele de lugar.
@MainActor
public final class MascotWindow {
    private let panel: NSPanel
    private let motion = MascotMotion()
    /// Monta o conteúdo do mascote. Escondido, ele é desmontado: sem view, nada redesenha.
    private let makeContent: () -> NSView

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
        makeContent = { [motion] in
            ClickOrDragView(
                content: NSHostingView(rootView: MascotView(agents: agents, motion: motion)),
                onClick: onClick
            )
        }

        if !panel.setFrameUsingName("DaemonMascot"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24))
        }
        // A posição salva pode ser de quando o mascote tinha outro tamanho.
        panel.setContentSize(size)
        panel.setFrameAutosaveName("DaemonMascot")
        motion.frame = { [weak panel] in panel?.frame ?? .zero }
    }

    public func show() {
        if panel.contentView?.subviews.isEmpty ?? true { panel.contentView = makeContent() }
        motion.start()
        panel.orderFrontRegardless()
    }

    /// Esconder não só tira da tela: para os relógios da animação e desmonta a view, que
    /// senão continuaria acordando 30 vezes por segundo e redesenhando a cada mudança nas abas.
    public func hide() {
        panel.orderOut(nil)
        motion.stop()
        panel.contentView = NSView()
    }
    public var isVisible: Bool { panel.isVisible }
    public var frame: NSRect { panel.frame }
}

/// O que anima o mascote: piscar, olhar para os lados e o pulinho de "precisa de você".
/// Objeto em vez de `@State` porque `@State` é uma macro que exige o Xcode.
@MainActor
private final class MascotMotion: ObservableObject {
    @Published var blinking = false
    @Published var look: CGFloat = 0
    @Published var lookY: CGFloat = 0
    /// Quanto o cubo está girado na direção do ponteiro (graus, somados aos do MascotStyle).
    @Published var turn: Double = 0
    @Published var tiltUp: Double = 0
    @Published var hop = false
    private var ticks = 0
    /// Os relógios ficam aqui, não no `body`: lá cada redesenho fazia um relógio novo (e, com
    /// o mascote animando, o de 0,35 s quase nunca batia). A view só escuta os sinais.
    let tickSignal = PassthroughSubject<Void, Never>()
    let followSignal = PassthroughSubject<Void, Never>()
    private var timers: [Timer] = []

    /// Liga os relógios (mascote à vista).
    func start() {
        guard timers.isEmpty else { return }
        timers = [(0.35, tickSignal), (1.0 / 30, followSignal)].map { interval, signal in
            let timer = Timer(timeInterval: interval, repeats: true) { _ in signal.send() }
            // `.common`: continua batendo enquanto o usuário arrasta o mascote.
            RunLoop.main.add(timer, forMode: .common)
            return timer
        }
    }

    /// Desliga os relógios (mascote escondido).
    func stop() {
        timers.forEach { $0.invalidate() }
        timers = []
    }
    /// Onde o mascote está na tela, para saber em que direção fica o ponteiro.
    var frame: () -> NSRect = { .zero }

    /// Chamado 30 vezes por segundo: pronto ou com resposta nova, o cubo vira e a cara olha
    /// para o ponteiro. O macOS informa a posição do ponteiro sem pedir permissão
    /// (`NSEvent.mouseLocation`). Nos outros estados, o cubo volta a ficar de frente.
    func follow(_ mood: CubeMascot.Mood) {
        var direction = (x: CGFloat(0), y: CGFloat(0))
        if mood == .idle || mood == .happy {
            let frame = frame()
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - frame.midX, dy = mouse.y - frame.midY
            let distance = (dx * dx + dy * dy).squareRoot()
            // Ponteiro em cima do mascote: fica de frente. Longe: vira até o limite.
            let reach = distance < 20 ? 0 : min(1, distance / MascotStyle.followReach)
            if distance > 0 { direction = (dx / distance * reach, dy / distance * reach) }
        }
        // Ponteiro à direita: a frente vira para a direita (aparece mais da lateral esquerda).
        // Ponteiro em cima: a frente levanta (aparece mais da base).
        // Simétrico: o repouso já é virado para a direita (o `yaw` da logo), então para a
        // esquerda o caminho até o giro máximo é maior.
        let rest = MascotStyle.yaw, maxTurn = MascotStyle.followTurn
        let x = Double(direction.x)
        let targetTurn = x >= 0 ? x * (maxTurn - rest) : x * (maxTurn + rest)
        let targetTilt = Double(direction.y) * MascotStyle.followTilt
        let targetLook = direction.x * MascotStyle.followLook
        let targetLookY = -direction.y * MascotStyle.followLook * 0.8

        // Anda um quarto do caminho por tique: o giro sai macio, sem saltos. (O SwiftUI não
        // anima sozinho um ângulo que vira geometria, então a suavização é feita aqui.)
        // Só publica se ainda falta andar: parado, não redesenha nada.
        func approach(_ value: Double, _ target: Double, _ threshold: Double) -> Double? {
            abs(target - value) > threshold ? value + (target - value) * 0.25 : nil
        }
        if let v = approach(turn, targetTurn, 0.05) { turn = v }
        if let v = approach(tiltUp, targetTilt, 0.05) { tiltUp = v }
        if mood == .idle || mood == .happy {
            if let v = approach(Double(look), Double(targetLook), 0.05) { look = CGFloat(v) }
            if let v = approach(Double(lookY), Double(targetLookY), 0.05) { lookY = CGFloat(v) }
        }
    }

    /// Chamado a cada 0,35 s com a cara atual.
    func tick(_ mood: CubeMascot.Mood) {
        ticks += 1
        switch mood {
        case .thinking:
            // Olha para um lado, para o outro, e volta ao meio de vez em quando.
            let positions: [CGFloat] = [-3, -3, 3, 3, 0]
            withAnimation(.easeInOut(duration: 0.3)) {
                look = positions[ticks % positions.count]
                lookY = 0
            }
        case .attention:
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { hop.toggle() }
        case .stopped:
            if look != 0 || lookY != 0 || hop {
                withAnimation(.easeOut(duration: 0.2)) { look = 0; lookY = 0; hop = false }
            }
        case .idle, .happy:
            // Quem cuida do olhar aqui é o `follow`; só desfaz o pulinho.
            if hop { withAnimation(.easeOut(duration: 0.2)) { hop = false } }
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
    @ObservedObject var motion: MascotMotion
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
                CubeMascot(mood: mood, dark: colorScheme != .dark, blinking: motion.blinking,
                            look: motion.look, lookY: motion.lookY,
                            yaw: yaw, pitch: MascotStyle.pitch - motion.tiltUp, tilt: tilt)
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
        .onReceive(motion.tickSignal) { _ in
            motion.tick(mood)
        }
        .onReceive(motion.followSignal) { _ in
            motion.follow(mood)
        }
    }

    /// Giro de lado: o de repouso (virado para a direita, como na logo) mais o de seguir o mouse.
    private var yaw: Double { MascotStyle.yaw + motion.turn }

    /// A inclinação da logo (tombado para a direita) combina com o cubo virado para a direita.
    /// Ela acompanha o giro: virando para a esquerda, diminui e passa para o outro lado, como
    /// num espelho. Senão ele parece olhar "contra" o próprio corpo.
    private var tilt: Double { MascotStyle.tilt * max(-1, min(1, yaw / MascotStyle.yaw)) }

    /// A cara do mascote resume todas as abas: parado > precisa de você > pensando >
    /// resposta nova > pronto.
    private var mood: CubeMascot.Mood {
        // Hibernando conta como pronto: acorda sozinho quando a aba é aberta.
        guard [.running, .sleeping].contains(agents.tabs[0].state) else { return .stopped }
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
