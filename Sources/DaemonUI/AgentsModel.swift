import Combine
import Foundation
import DaemonCore

/// Todas as abas (sessões), em qualquer janela: um `BotModel` por agente, qual está com o
/// foco e quais têm resposta nova. Onde cada aba aparece é com o `Workspace`.
@MainActor
public final class AgentsModel: ObservableObject {
    /// O que a interface pede ao app para criar e remover abas. A interface não sabe
    /// salvar abas nem abrir sessões; quem sabe é o app, que preenche isto.
    public struct Actions {
        public var recentConversations: () async -> [ConversationSummary]
        public var create: (NewAgentRequest) -> BotModel
        public var remove: (BotModel) -> Void
        /// Salva o novo nome (a aba já foi renomeada na interface).
        public var rename: (BotModel) -> Void

        public init(
            recentConversations: @escaping () async -> [ConversationSummary],
            create: @escaping (NewAgentRequest) -> BotModel,
            remove: @escaping (BotModel) -> Void,
            rename: @escaping (BotModel) -> Void
        ) {
            self.recentConversations = recentConversations
            self.create = create
            self.remove = remove
            self.rename = rename
        }
    }

    @Published public private(set) var tabs: [BotModel]
    @Published public private(set) var selectedID: String
    /// Abas que terminaram uma resposta enquanto o usuário não estava olhando para elas.
    @Published public private(set) var unread: Set<String> = []
    public var actions: Actions?
    /// Se o usuário está vendo esta aba agora. Quem sabe disso é o painel, que preenche aqui.
    var isViewing: (String) -> Bool = { _ in false }
    private var observers: [String: [AnyCancellable]] = [:]

    public init(tabs: [BotModel]) {
        precondition(!tabs.isEmpty, "precisa de pelo menos uma aba")
        self.tabs = tabs
        selectedID = tabs[0].id
        tabs.forEach(observe)
    }

    public var selected: BotModel { tabs.first { $0.id == selectedID } ?? tabs[0] }

    /// A primeira aba parada esperando o usuário (uma aprovação, por exemplo).
    public var waiting: BotModel? {
        tabs.first { if case .needsAttention = $0.activity { return true } else { return false } }
    }

    func select(_ id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id
        markSeen(id)
    }

    func markSeen(_ id: String) {
        unread.remove(id)
    }

    /// Cria a aba pelo app e já deixa ela selecionada.
    @discardableResult
    func create(_ request: NewAgentRequest) -> BotModel? {
        guard let actions else { return nil }
        let tab = actions.create(request)
        tabs.append(tab)
        observe(tab)
        select(tab.id)
        return tab
    }

    func tab(_ id: String) -> BotModel? { tabs.first { $0.id == id } }

    func rename(_ id: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let tab = tab(id) else { return }
        tab.rename(to: name)
        actions?.rename(tab)
    }

    /// Remove a aba (menos a primeira, a do Daemon). Se era a aberta, volta para o Daemon.
    func remove(_ id: String) {
        guard id != tabs[0].id, let tab = tabs.first(where: { $0.id == id }) else { return }
        actions?.remove(tab)
        observers[id] = nil
        unread.remove(id)
        tabs.removeAll { $0.id == id }
        if selectedID == id { selectedID = tabs[0].id }
    }

    private func observe(_ tab: BotModel) {
        let id = tab.id
        observers[id] = [
            // O mascote observa só este modelo; qualquer mudança numa aba redesenha ele.
            tab.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
            // Pensando → pronto numa aba fora da vista: marca como "resposta nova".
            tab.$activity.removeDuplicates()
                .scan((SessionActivity.idle, SessionActivity.idle)) { ($0.1, $1) }
                .sink { [weak self] previous, current in
                    guard let self, previous == .thinking, current == .idle, !self.isViewing(id) else { return }
                    self.unread.insert(id)
                },
        ]
    }
}
