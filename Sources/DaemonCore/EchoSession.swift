import AppKit

/// Sessão de mentira: finge que pensou e volta a ficar pronta.
/// Serve para desenvolver e testar a interface sem depender de um CLI de verdade.
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

    private let placeholder = NSTextField(labelWithString: "Terminal de mentira (EchoSession)")

    public init(config: CLIConfig = .claudeDefault) {
        self.config = config
    }

    public func start() throws { state = .running }
    public func stop() { state = .stopped }
    public func restart() throws { stop(); try start() }
    public func sleep() { if state == .running, activity == .idle { state = .sleeping } }
    public func wake() { if state == .sleeping { state = .running } }

    public func send(_ text: String) {
        activity = .thinking
        // Finge que pensou por um instante, para a interface poder mostrar o estado.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.activity = .idle }
    }

    public func terminalView() -> NSView { placeholder }
}
