import SwiftUI
import DaemonCore

/// Faixa de abas de um pedaço, com o "+" no fim. Cada pedaço da janela tem a sua.
struct TabBarView: View {
    @ObservedObject var pane: Pane
    @ObservedObject var agents: AgentsModel
    let canClose: (String) -> Bool
    let onSelect: (String) -> Void
    let onAdd: () -> Void
    let onClose: (String) -> Void
    let onOpenInNewWindow: (String) -> Void
    let onRename: (String) -> Void
    /// Arrastar a aba: quem faz o arraste de verdade é o AppKit (`PaneView`).
    let onDragStart: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pane.tabIDs, id: \.self) { id in
                if let tab = agents.tab(id) {
                    TabButton(
                        tab: tab,
                        shortcut: (agents.tabs.firstIndex { $0.id == id } ?? 99) + 1,
                        selected: id == pane.selectedID,
                        unread: agents.unread.contains(id)
                    ) { onSelect(id) }
                    // Junto com o clique: se o mouse andar com o botão apertado, é arraste.
                    .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { _ in onDragStart(id) })
                    .contextMenu {
                        Button("Renomear aba…") { onRename(id) }
                        Button("Abrir em nova janela") { onOpenInNewWindow(id) }
                        // A primeira aba é a principal (Daemon): não sai.
                        if canClose(id) {
                            Button("Fechar aba") { onClose(id) }
                        }
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
    @ObservedObject var tab: TabModel
    let shortcut: Int
    let selected: Bool
    let unread: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(tab.agent.displayName)
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
        .help(shortcut <= 9 ? "\(tab.agent.config.executable) (⌘\(shortcut))" : tab.agent.config.executable)
    }

    private var statusColor: Color {
        switch (tab.state, tab.activity) {
        case (.running, .idle): return .green
        case (.running, .thinking): return .yellow
        case (.running, .needsAttention): return .orange
        case (.starting, _): return .yellow
        // Hibernando: pronta, só que sem processo. Acorda quando a aba é aberta.
        case (.sleeping, _): return .gray
        default: return .red
        }
    }
}
