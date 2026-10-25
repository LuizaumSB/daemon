import SwiftUI
import DaemonCore
import DaemonUI
import DaemonSession

/// Ponto de entrada do app. `@main` diz ao Swift que a execução começa aqui.
@main
struct DaemonApp: App {
    // O AppDelegate é a parte "AppKit" do app: cuida do ciclo de vida
    // (abrir, fechar) e guarda a sessão, que precisa viver enquanto o app viver.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Ícone na menu bar: o cubo do mascote em versão chapada.
        MenuBarExtra {
            MenuBarContent(
                agents: appDelegate.agents,
                onShow: { appDelegate.panel.show() },
                onToggleMascot: { appDelegate.toggleMascot() }
            )
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Uma sessão viva por aba, cada uma com o seu bot. As abas vêm do `agents.json`;
    // a primeira é sempre o Daemon.
    let agents = AgentsModel(tabs: AgentStore.load().map(AppDelegate.makeTab))
    lazy var panel = Workspace(agents: agents)
    private lazy var mascot = MascotWindow(agents: agents) { [weak self] in self?.panel.toggle() }
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sem ícone no Dock nem menu de app: o Daemon vive só na menu bar.
        // No .app empacotado o Info.plist (LSUIElement) já faz isso; aqui cobre o `swift run`.
        NSApp.setActivationPolicy(.accessory)
        // Os modelos já existem (e escutam as sessões) antes de elas começarem.
        for tab in agents.tabs { try? tab.session.start() }
        agents.actions = AgentsModel.Actions(
            recentConversations: { await AgentStore.recentConversations() },
            create: { [unowned self] request in
                let agent = AgentStore.create(request, existing: self.agents.tabs.map(\.agent))
                let tab = Self.makeTab(agent)
                try? tab.session.start()
                return tab
            },
            remove: { [unowned self] tab in
                tab.session.stop()
                AgentStore.remove(tab.agent, from: self.agents.tabs.map(\.agent))
            },
            rename: { [unowned self] tab in
                AgentStore.rename(tab.agent, in: self.agents.tabs.map(\.agent))
            }
        )
        mascot.show()
        panel.anchorFrame = { [weak self] in
            guard let mascot = self?.mascot, mascot.isVisible else { return nil }
            return mascot.frame
        }
        hotKey = HotKey { [weak self] in self?.panel.toggle() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        agents.tabs.forEach { $0.session.stop() }
    }

    /// Uma aba = o bot ligado a uma sessão nova daquele agente.
    private static func makeTab(_ agent: Agent) -> TabModel {
        TabModel(agent: agent, session: SessionFactory.make(agent: agent))
    }

    func toggleMascot() {
        mascot.isVisible ? mascot.hide() : mascot.show()
    }
}
