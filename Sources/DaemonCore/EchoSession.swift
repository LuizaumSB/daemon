import AppKit

/// Sessão de mentira: responde ecoando o que recebe.
/// Serve para a frente A desenvolver e testar a interface sem depender da frente B.
@MainActor
public final class EchoSession: SessionController {
    public private(set) var state: SessionState = .stopped {
        didSet { onStateChange?(state) }
    }
    public private(set) var activity: SessionActivity = .idle {
        didSet { onActivityChange?(activity) }
    }
    public let config: CLIConfig
    public var onActivityChange: ((SessionActivity) -> Void)?
    public var onStateChange: ((SessionState) -> Void)?
    public var onHistoryChange: (([ChatMessage]) -> Void)?
    private var history: [ChatMessage] = []

    private let placeholder = NSTextField(labelWithString: "Terminal de mentira (EchoSession)")

    public init(config: CLIConfig = .claudeDefault) {
        self.config = config
    }

    public func start() throws { state = .running }
    public func stop() { state = .stopped }
    public func restart() throws { stop(); try start() }

    public func send(_ text: String) {
        activity = .thinking
        history.append(ChatMessage(author: .user, text: text))
        onHistoryChange?(history)
        // Finge que pensou por um instante, para a interface poder mostrar o estado.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.history.append(ChatMessage(author: .assistant, text: "eco: \(text)"))
            self.onHistoryChange?(self.history)
            self.activity = .idle
        }
    }

    public func terminalView() -> NSView { placeholder }
}
