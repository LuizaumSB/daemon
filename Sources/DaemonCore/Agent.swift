import Foundation

/// Um agente é uma aba do painel: uma sessão do CLI sempre viva, com conversa própria.
/// A primeira aba é a principal (Daemon); as outras o usuário cria pelo "+" e ficam
/// salvas em `agents.json`.
public struct Agent: Identifiable, Equatable, Codable, Sendable {
    /// Chave da sessão: separa a pasta de eventos, os hooks e a última conversa de cada aba.
    public let id: String
    /// Nome exibido na aba. Também vira o `--name` de uma conversa nova.
    public var displayName: String
    public var config: CLIConfig

    public init(id: String, displayName: String, config: CLIConfig) {
        self.id = id
        self.displayName = displayName
        self.config = config
    }

    /// Só o Claude Code tem hooks e transcrição; os outros CLIs aparecem só no terminal.
    public var usesClaude: Bool {
        (config.executable as NSString).lastPathComponent == "claude"
    }

    /// A aba principal, que não pode ser fechada. A chave "main" vem de antes das abas;
    /// mudar perderia a conversa.
    public static let daemon = Agent(id: "main", displayName: "Daemon", config: .claudeDefault)
}

/// Uma conversa do Claude Code já existente, para virar aba com "retomar conversa".
public struct ConversationSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Pasta onde a conversa nasceu: é nela que o `--resume` precisa rodar.
    public let workingDirectory: String
    public let modified: Date

    public init(id: String, title: String, workingDirectory: String, modified: Date) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.modified = modified
    }
}

/// O que o usuário preencheu no "+" para criar uma aba.
public struct NewAgentRequest: Sendable {
    public enum Start: Sendable {
        /// Conversa nova, rodando nesta pasta.
        case newConversation(directory: String)
        /// Retoma uma conversa do Claude Code que já existe.
        case resume(ConversationSummary)
    }

    public var name: String
    /// Comando do CLI: "claude", "codex", "gemini"...
    public var executable: String
    public var start: Start

    public init(name: String, executable: String, start: Start) {
        self.name = name
        self.executable = executable
        self.start = start
    }
}
