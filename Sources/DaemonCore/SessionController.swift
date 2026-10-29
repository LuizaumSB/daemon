import AppKit

/// Estado da sessão do CLI que roda em segundo plano.
public enum SessionState: Equatable, Sendable {
    case stopped
    case starting
    case running
    /// Hibernando: o CLI foi encerrado para liberar memória e volta na mesma conversa com
    /// `wake()`. Para a interface, é uma aba pronta, só que sem processo.
    case sleeping
    /// O processo terminou. `code` é o código de saída do CLI.
    case exited(code: Int32)
}

/// O que o CLI está fazendo agora. Alimenta o mascote e as bolinhas das abas.
public enum SessionActivity: Equatable, Sendable {
    /// Esperando uma mensagem nova.
    case idle
    /// Trabalhando numa resposta.
    case thinking
    /// Parado esperando o usuário (uma aprovação, por exemplo).
    case needsAttention(message: String)
}

/// Contrato entre a interface (frente A) e a sessão (frente B).
///
/// A interface só fala com a sessão por aqui. Assim a frente A pode ser construída com
/// o `EchoSession` (uma sessão de mentira) enquanto a frente B ainda não existe, e a
/// frente B pode trocar SwiftTerm, PTY ou CLI sem a interface perceber.
///
/// `@MainActor`: tudo aqui roda na thread principal, a mesma da interface. Isso evita
/// que a UI seja atualizada de outra thread, o erro mais comum em apps de macOS.
@MainActor
public protocol SessionController: AnyObject {
    var state: SessionState { get }
    var config: CLIConfig { get }

    /// Chamado sempre que `state` muda.
    var onStateChange: ((SessionState) -> Void)? { get set }

    var activity: SessionActivity { get }

    /// Chamado sempre que `activity` muda.
    var onActivityChange: ((SessionActivity) -> Void)? { get set }


    func start() throws
    func stop()
    func restart() throws

    /// Encerra o CLI se ele estiver parado à toa, para liberar memória. Sem efeito se ele
    /// estiver trabalhando, esperando o usuário, ou se o CLI não souber retomar a conversa.
    func sleep()
    /// Volta da hibernação (na mesma conversa). Sem efeito se a sessão não estiver dormindo.
    func wake()

    /// Manda uma mensagem para a sessão, como se fosse digitada e seguida de Enter.
    func send(_ text: String)

    /// A view do terminal completo, ligada à mesma sessão.
    /// A frente A só embute essa view; não sabe o que tem dentro.
    func terminalView() -> NSView
}
