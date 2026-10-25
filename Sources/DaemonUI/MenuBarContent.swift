import SwiftUI
import DaemonCore

/// Conteúdo do menu que abre ao clicar no ícone da menu bar.
public struct MenuBarContent: View {
    // Observa as abas para o menu acompanhar qual está aberta.
    @ObservedObject private var agents: AgentsModel
    private let onShow: () -> Void
    private let onToggleMascot: () -> Void

    public init(
        agents: AgentsModel,
        onShow: @escaping () -> Void,
        onToggleMascot: @escaping () -> Void
    ) {
        self.agents = agents
        self.onShow = onShow
        self.onToggleMascot = onToggleMascot
    }

    public var body: some View {
        Button("Abrir Daemon  (⌥Espaço)", action: onShow)
        Button("Mostrar/esconder mascote", action: onToggleMascot)
        Divider()
        Text("Trocar de conversa: /resume no terminal")
        Button("Reiniciar sessão (\(agents.selected.agent.displayName))") { try? agents.selected.session.restart() }
        Divider()
        Button("Sair") {
            agents.tabs.forEach { $0.session.stop() }
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
