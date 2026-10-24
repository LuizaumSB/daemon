import SwiftUI
import DaemonCore

/// O texto sendo digitado no bot.
///
/// Fica num objeto em vez de `@State` porque, no SDK do macOS 27, `@State` virou uma
/// macro cujo plugin só vem com o Xcode completo. Assim o projeto compila só com as
/// Command Line Tools.
final class DraftState: ObservableObject {
    @Published var text = ""
}

/// O bot compacto: conversa curta com cara de terminal e um campo para digitar.
struct BotView: View {
    @ObservedObject var model: BotModel
    @ObservedObject var draft: DraftState

    private let mono = Font.system(size: 13, design: .monospaced)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            conversation
            Divider().overlay(Color.white.opacity(0.08))
            input
        }
        .background(Color(white: 0.08))
    }

    /// Linha de estado da aba. As abas e o botão do terminal ficam na faixa de cima do painel.
    private var header: some View {
        HStack(spacing: 8) {
            Text(statusText).font(mono).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.messages.isEmpty {
                        Text("Fala comigo. Para trocar de conversa, use /resume.")
                            .font(mono).foregroundStyle(.secondary)
                    }
                    ForEach(model.messages) { message in
                        MessageRow(message: message, font: mono).id(message.id)
                    }
                    if model.activity == .thinking {
                        Text("…").font(mono).foregroundStyle(.green).id("thinking")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.messages.count) { _ in
                if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var input: some View {
        HStack(spacing: 8) {
            Text(">").font(mono.weight(.bold)).foregroundStyle(.green)
            TextField("", text: $draft.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(mono)
                .lineLimit(1...5)
                .onSubmit(submit)
        }
        .padding(12)
    }

    private func submit() {
        model.send(draft.text)
        draft.text = ""
    }

    private var statusText: String {
        switch (model.state, model.activity) {
        case (.running, .idle): return "pronto"
        case (.running, .thinking): return "pensando"
        case (.running, .needsAttention(let message)): return message.isEmpty ? "precisa de você" : message
        case (.starting, _): return "iniciando"
        case (.exited(let code), _): return "sessão encerrou (\(code))"
        default: return "parado"
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let font: Font

    var body: some View {
        switch message.author {
        case .user:
            HStack(alignment: .top, spacing: 8) {
                Text(">").foregroundStyle(.green)
                Text(message.text).foregroundStyle(.white)
            }
            .font(font)
            .textSelection(.enabled)
        case .assistant:
            // Respostas do Claude vêm em Markdown; o SwiftUI renderiza o básico.
            Text((try? AttributedString(
                markdown: message.text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(message.text))
                .font(font)
                .foregroundStyle(Color(white: 0.85))
                .textSelection(.enabled)
        }
    }
}
