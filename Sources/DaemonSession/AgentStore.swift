import Foundation
import DaemonCore

/// Guarda as abas em `agents.json`, em Application Support. Os IDs das conversas de cada
/// pessoa ficam lá, nunca no código.
public enum AgentStore {
    static let file = AppSupport.directory.appendingPathComponent("agents.json")

    /// As abas salvas. A primeira é sempre a principal (Daemon), que não pode ser removida.
    /// Uma aba "main" no arquivo personaliza a principal (pasta, mensagem inicial...).
    public static func load() -> [Agent] {
        let saved = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([Agent].self, from: $0) } ?? []
        let main = saved.first { $0.id == Agent.daemon.id } ?? .daemon
        return [main] + saved.filter { $0.id != Agent.daemon.id }
    }

    /// Cria a aba pedida no "+", salva e devolve. Ao retomar uma conversa, deixa ela
    /// marcada como a última da aba: é ela que a sessão abre ao começar.
    public static func create(_ request: NewAgentRequest, existing: [Agent]) -> Agent {
        var config = CLIConfig(executable: request.executable, workingDirectory: "")
        switch request.start {
        case .newConversation(let directory):
            config.workingDirectory = directory
        case .resume(let conversation):
            config.workingDirectory = conversation.workingDirectory
        }
        let agent = Agent(id: uniqueKey(for: request.name, existing: existing),
                          displayName: request.name, config: config)
        // A chave pode ter sido usada por uma aba já removida: começa limpa.
        AppSupport.saveLastSession(nil, key: agent.id)
        if case .resume(let conversation) = request.start {
            AppSupport.saveLastSession(.init(id: conversation.id, workingDirectory: conversation.workingDirectory),
                                       key: agent.id)
        }
        save(existing + [agent])
        return agent
    }

    /// Tira a aba da lista. A conversa continua no Claude Code e pode ser retomada de novo.
    public static func remove(_ agent: Agent, from existing: [Agent]) {
        guard agent.id != Agent.daemon.id else { return }
        save(existing.filter { $0.id != agent.id })
        AppSupport.saveLastSession(nil, key: agent.id)
    }

    /// Salva a lista com o nome novo de uma aba.
    public static func rename(_ agent: Agent, in existing: [Agent]) {
        save(existing.map { $0.id == agent.id ? agent : $0 })
    }

    private static func save(_ agents: [Agent]) {
        // A principal só vai para o arquivo se foi personalizada.
        let tabs = agents.filter { $0.id != Agent.daemon.id || $0 != .daemon }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(tabs) { try? data.write(to: file, options: .atomic) }
    }

    /// Chave a partir do nome ("Docs 2" → "docs-2"): vira nome de pasta e arquivo,
    /// então só letras, números e hífen. Repetida, ganha um número no fim.
    private static func uniqueKey(for name: String, existing: [Agent]) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let slug = folded.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? String($0) : "-" }
            .joined()
            .split(separator: "-").joined(separator: "-")
        let base = slug.isEmpty || slug == "main" ? "agente" : slug
        var key = base
        var number = 2
        while existing.contains(where: { $0.id == key }) {
            key = "\(base)-\(number)"
            number += 1
        }
        return key
    }

    /// Conversas recentes do Claude Code, para o "+" oferecer em "retomar conversa".
    public static func recentConversations(limit: Int = 40) async -> [ConversationSummary] {
        await Task.detached(priority: .userInitiated) {
            TranscriptReader.recentConversations(limit: limit)
        }.value
    }
}
