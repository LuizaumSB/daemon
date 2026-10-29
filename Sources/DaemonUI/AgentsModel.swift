import Combine
import Foundation
import DaemonCore

/// Todas as abas (sessões), em qualquer janela: um `TabModel` por agente, qual está com o
/// foco e quais têm resposta nova. Onde cada aba aparece é com o `Workspace`.
@MainActor
public final class AgentsModel: ObservableObject {
    /// O que a interface pede ao app para criar e remover abas. A interface não sabe
    /// salvar abas nem abrir sessões; quem sabe é o app, que preenche isto.
    public struct Actions {
        public var recentConversations: () async -> [ConversationSummary]
        public var create: (NewAgentRequest) -> TabModel
        public var remove: (TabModel) -> Void
        /// Salva o novo nome (a aba já foi renomeada na interface).
        public var rename: (TabModel) -> Void

        public init(
            recentConversations: @escaping () async -> [ConversationSummary],
            create: @escaping (NewAgentRequest) -> TabModel,
            remove: @escaping (TabModel) -> Void,
            rename: @escaping (TabModel) -> Void
        ) {
            self.recentConversations = recentConversations
            self.create = create
            self.remove = remove
            self.rename = rename
        }
    }

    @Published public private(set) var tabs: [TabModel]
    @Published public private(set) var selectedID: String
    /// Abas que terminaram uma resposta enquanto o usuário não estava olhando para elas.
    @Published public private(set) var unread: Set<String> = []
    public var actions: Actions?
    /// Se o usuário está vendo esta aba agora. Quem sabe disso é o painel, que preenche aqui.
    var isViewing: (String) -> Bool = { _ in false }
    /// Se a aba aparece numa janela aberta, mesmo com outro app na frente. Também do painel.
    var isOnScreen: (String) -> Bool = { _ in false }
    private var observers: [String: [AnyCancellable]] = [:]
    /// Quando cada aba fez algo ou esteve à vista pela última vez.
    private var lastUsed: [String: Date] = [:]
    private var sleepTimer: Timer?

    public init(tabs: [TabModel]) {
        precondition(!tabs.isEmpty, "precisa de pelo menos uma aba")
        self.tabs = tabs
        selectedID = tabs[0].id
        tabs.forEach(observe)
    }

    public var selected: TabModel { tabs.first { $0.id == selectedID } ?? tabs[0] }

    /// A primeira aba parada esperando o usuário (uma aprovação, por exemplo).
    public var waiting: TabModel? {
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
    func create(_ request: NewAgentRequest) -> TabModel? {
        guard let actions else { return nil }
        let tab = actions.create(request)
        tabs.append(tab)
        observe(tab)
        select(tab.id)
        return tab
    }

    func tab(_ id: String) -> TabModel? { tabs.first { $0.id == id } }

    // MARK: - Hibernar

    /// Liga a hibernação: a aba parada há `idle` segundos e fora da vista encerra o CLI.
    /// Ela acorda sozinha (na mesma conversa) quando volta a aparecer numa janela.
    /// Abas pensando ou esperando o usuário nunca hibernam.
    public func sleepIdleTabs(after idle: TimeInterval) {
        // Uma checagem por minuto basta: hibernar um minuto antes ou depois não faz diferença.
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepIdle(after: idle) }
        }
    }

    private func sleepIdle(after idle: TimeInterval) {
        let now = Date()
        for tab in tabs where tab.state == .running {
            if tab.activity != .idle || isOnScreen(tab.id) {
                lastUsed[tab.id] = now
            } else if now.timeIntervalSince(lastUsed[tab.id] ?? now) >= idle {
                tab.session.sleep()
            }
        }
    }

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
        lastUsed[id] = nil
        unread.remove(id)
        tabs.removeAll { $0.id == id }
        if selectedID == id { selectedID = tabs[0].id }
    }

    private func observe(_ tab: TabModel) {
        let id = tab.id
        lastUsed[id] = Date()
        observers[id] = [
            // Qualquer mudança de estado (pensou, respondeu, acordou) conta como uso.
            tab.$activity.sink { [weak self] _ in self?.lastUsed[id] = Date() },
            tab.$state.sink { [weak self] _ in self?.lastUsed[id] = Date() },
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
