import AppKit
import SwiftUI
import DaemonCore

/// O que está sendo preenchido no "+". Objeto em vez de `@State` pelo mesmo motivo do
/// `DraftState` (no SDK do macOS 27, `@State` é uma macro que exige o Xcode).
final class NewAgentForm: ObservableObject {
    enum CLI: String, CaseIterable, Identifiable {
        case claude = "Claude", codex = "Codex", opencode = "OpenCode", antigravity = "Antigravity", other = "Outro"
        var id: String { rawValue }
    }
    enum Start: String, CaseIterable, Identifiable {
        case new = "Conversa nova", resume = "Retomar conversa"
        var id: String { rawValue }
    }

    @Published var name = ""
    @Published var cli: CLI = .claude
    @Published var customCommand = ""
    @Published var start: Start = .new
    @Published var directory = NSString(string: "~/Documents").expandingTildeInPath
    @Published var conversations: [ConversationSummary] = []
    @Published var loading = false
    @Published var selectedConversation: String?
    @Published var search = ""

    var executable: String {
        switch cli {
        case .claude: return "claude"
        case .codex: return "codex"
        case .opencode: return "opencode"
        // O Antigravity CLI (Google) substituiu o Gemini CLI; o comando é `agy`.
        case .antigravity: return "agy"
        case .other: return customCommand.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Retomar conversa só existe no Claude: os outros CLIs não têm a transcrição que o app lê.
    var resuming: Bool { cli == .claude && start == .resume }

    var filtered: [ConversationSummary] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.workingDirectory.localizedCaseInsensitiveContains(query)
        }
    }

    /// O pedido pronto, ou `nil` se falta alguma coisa.
    var request: NewAgentRequest? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !executable.isEmpty else { return nil }
        if resuming {
            guard let conversation = conversations.first(where: { $0.id == selectedConversation }) else { return nil }
            return NewAgentRequest(name: name, executable: executable, start: .resume(conversation))
        }
        return NewAgentRequest(name: name, executable: executable, start: .newConversation(directory: directory))
    }
}

/// Janela do "+": nome, CLI e se a aba começa uma conversa nova ou retoma uma existente.
struct NewAgentView: View {
    @ObservedObject var form: NewAgentForm
    let onCancel: () -> Void
    let onCreate: (NewAgentRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nova aba").font(.headline)

            TextField("Nome da aba", text: $form.name)
                .textFieldStyle(.roundedBorder)

            Picker("CLI", selection: $form.cli) {
                ForEach(NewAgentForm.CLI.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if form.cli == .other {
                TextField("Comando (ex.: aider)", text: $form.customCommand)
                    .textFieldStyle(.roundedBorder)
            }

            if form.cli == .claude {
                Picker("Início", selection: $form.start) {
                    ForEach(NewAgentForm.Start.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if form.resuming {
                conversationPicker
            } else {
                directoryPicker
                Spacer(minLength: 0)
            }

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Criar") { if let request = form.request { onCreate(request) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.request == nil)
            }
        }
        .padding(18)
        .frame(width: 440, height: 440)
    }

    private var directoryPicker: some View {
        HStack {
            Text("Pasta").foregroundStyle(.secondary)
            Text((form.directory as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Escolher…", action: chooseDirectory)
        }
    }

    private var conversationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Buscar conversa", text: $form.search)
                .textFieldStyle(.roundedBorder)
            if form.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(form.filtered, selection: $form.selectedConversation) { conversation in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title).lineLimit(1)
                        Text("\((conversation.workingDirectory as NSString).abbreviatingWithTildeInPath) · \(Self.relative(conversation.modified))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(conversation.id)
                }
                .onChange(of: form.selectedConversation) { id in
                    // Nome em branco: sugere o título da conversa escolhida.
                    if form.name.trimmingCharacters(in: .whitespaces).isEmpty,
                       let conversation = form.conversations.first(where: { $0.id == id }) {
                        form.name = conversation.title
                    }
                }
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: form.directory)
        if panel.runModal() == .OK, let url = panel.url { form.directory = url.path }
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
