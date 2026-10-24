import Foundation

/// Qual CLI o Daemon mantém vivo e como ele é iniciado.
/// `Codable` permite salvar e ler isso como JSON nas configurações.
public struct CLIConfig: Codable, Equatable, Sendable {
    /// Nome ou caminho do executável: "claude", "codex", "gemini"...
    public var executable: String
    public var arguments: [String]
    /// Mensagem enviada logo que uma conversa nova abre (ex.: um comando como /minha-skill).
    public var initialPrompt: String?
    /// Pasta onde o CLI roda numa conversa nova.
    public var workingDirectory: String

    public init(
        executable: String,
        arguments: [String] = [],
        initialPrompt: String? = nil,
        workingDirectory: String
    ) {
        self.executable = executable
        self.arguments = arguments
        self.initialPrompt = initialPrompt
        self.workingDirectory = workingDirectory
    }

    /// O padrão da aba principal: Claude Code na pasta pessoal, sem mensagem inicial.
    /// Para mudar (pasta, mensagem inicial), salve uma aba "main" no agents.json.
    public static let claudeDefault = CLIConfig(
        executable: "claude",
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
    )
}
