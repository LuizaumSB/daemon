import SwiftUI
import DaemonCore

/// Faixa de abas no topo do painel, ao lado do botão de fechar, com o "+" no fim.
struct TabBarView: View {
    @ObservedObject var agents: AgentsModel
    let onSelect: (String) -> Void
    let onAdd: () -> Void
    let onClose: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(agents.tabs.enumerated()), id: \.element.id) { index, tab in
                TabButton(
                    bot: tab,
                    shortcut: index + 1,
                    selected: tab.id == agents.selectedID,
                    unread: agents.unread.contains(tab.id)
                ) { onSelect(tab.id) }
                .contextMenu {
                    // A primeira aba é a principal (Daemon): não sai.
                    if index > 0 {
                        Button("Fechar aba") { onClose(tab.id) }
                    }
                }
            }
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.6))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Nova aba")
        }
        .fixedSize()
    }
}

private struct TabButton: View {
    @ObservedObject var bot: BotModel
    let shortcut: Int
    let selected: Bool
    let unread: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(bot.agent.displayName)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(selected ? Color.white : Color(white: 0.6))
                    .lineLimit(1)
                if unread && !selected {
                    // Resposta nova que o usuário ainda não viu.
                    Circle().fill(Color.white).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shortcut <= 9 ? "\(bot.agent.config.executable) (⌘\(shortcut))" : bot.agent.config.executable)
    }

    private var statusColor: Color {
        switch (bot.state, bot.activity) {
        case (.running, .idle): return .green
        case (.running, .thinking): return .yellow
        case (.running, .needsAttention): return .orange
        case (.starting, _): return .yellow
        default: return .red
        }
    }
}
