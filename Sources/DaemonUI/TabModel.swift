import Foundation
import DaemonCore

/// Uma aba: o agente (nome, CLI) e a sessão viva dele, com o estado que a interface desenha
/// (as bolinhas das abas e a cara do mascote).
///
/// `ObservableObject` + `@Published`: quando um valor muda, o SwiftUI redesenha
/// sozinho as views que usam esse valor.
@MainActor
public final class TabModel: ObservableObject, Identifiable {
    @Published public private(set) var activity: SessionActivity = .idle
    @Published public private(set) var state: SessionState = .stopped
    /// Muda quando a aba é renomeada (o `id` não muda nunca).
    @Published public private(set) var agent: Agent
    public let session: SessionController
    // `nonisolated`: o `id` é fixo, então pode ser lido de qualquer thread.
    public nonisolated let id: String

    public init(agent: Agent, session: SessionController) {
        self.agent = agent
        self.id = agent.id
        self.session = session
        state = session.state
        activity = session.activity
        session.onStateChange = { [weak self] in self?.state = $0 }
        session.onActivityChange = { [weak self] in self?.activity = $0 }
    }

    func rename(to name: String) {
        agent.displayName = name
    }
}
