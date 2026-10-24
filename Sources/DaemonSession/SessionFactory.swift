import DaemonCore

/// Ponto de entrada da frente B: o app pede uma sessão aqui e recebe um `SessionController`.
public enum SessionFactory {
    /// Uma sessão por agente (aba), cada uma com seus hooks e sua última conversa.
    @MainActor
    public static func make(agent: Agent) -> SessionController {
        TerminalSession(key: agent.id, name: agent.displayName, config: agent.config)
    }
}
