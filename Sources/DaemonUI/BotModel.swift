import Foundation
import DaemonCore

/// Estado do bot que a interface desenha: conversa curta, atividade e sessão.
///
/// `ObservableObject` + `@Published`: quando um valor muda, o SwiftUI redesenha
/// sozinho as views que usam esse valor.
@MainActor
public final class BotModel: ObservableObject, Identifiable {
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var activity: SessionActivity = .idle
    @Published public private(set) var state: SessionState = .stopped
    public let agent: Agent
    public let session: SessionController
    // `nonisolated`: o `id` não depende da thread principal (o `agent` nunca muda).
    public nonisolated var id: String { agent.id }

    public init(agent: Agent, session: SessionController) {
        self.agent = agent
        self.session = session
        state = session.state
        activity = session.activity
        session.onStateChange = { [weak self] in self?.state = $0 }
        session.onActivityChange = { [weak self] in self?.activity = $0 }
        // A conversa vem da sessão (transcrição), então bot e terminal mostram o mesmo.
        session.onHistoryChange = { [weak self] in self?.messages = $0 }
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.send(text)
    }
}
