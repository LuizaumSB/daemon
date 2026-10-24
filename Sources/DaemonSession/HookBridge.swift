import Foundation

/// Ponte entre os hooks do Claude Code e o app.
///
/// O Claude Code roda um comando de shell em certos momentos (hooks) e passa um JSON
/// no stdin. O Daemon registra hooks que só gravam esse JSON num arquivo dentro da pasta
/// de eventos da sessão, com o nome do evento no nome do arquivo. O app vigia a pasta,
/// lê cada arquivo novo e apaga. Assim não precisa de servidor, socket nem script extra.
@MainActor
final class HookBridge {
    enum Event {
        /// Uma sessão abriu: no início, ou quando o usuário troca de conversa com /resume.
        case sessionStarted(payload: [String: Any])
        /// O usuário (pelo bot ou pelo terminal) mandou uma mensagem: o CLI começou a trabalhar.
        case promptSubmitted(payload: [String: Any])
        /// O CLI terminou a resposta.
        case stopped(payload: [String: Any])
        /// O CLI está esperando o usuário (aprovação, pergunta...).
        case notification(message: String)
    }

    var onEvent: ((Event) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private let eventsDirectory: URL
    private let settingsFile: URL

    /// `key` identifica a sessão: cada sessão viva tem a própria pasta de eventos,
    /// então um evento nunca cai na sessão errada.
    init(key: String) {
        eventsDirectory = AppSupport.eventsDirectory(for: key)
        settingsFile = AppSupport.hookSettingsFile(for: key)
    }

    /// Escreve o arquivo de settings com os hooks e devolve o caminho dele.
    func writeSettings() throws -> URL {
        let dir = eventsDirectory.path
        func capture(_ name: String) -> [String: Any] {
            // mktemp cria um arquivo com nome único; o JSON do stdin vai para ele.
            let command = "cat > \"$(mktemp '\(dir)/\(name).XXXXXX')\""
            return ["hooks": [["type": "command", "command": command]]]
        }
        let settings: [String: Any] = [
            "hooks": [
                "SessionStart": [capture("SessionStart")],
                "UserPromptSubmit": [capture("UserPromptSubmit")],
                "Stop": [capture("Stop")],
                "Notification": [capture("Notification")],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsFile, options: .atomic)
        return settingsFile
    }

    func startWatching() {
        guard source == nil else { return }
        clearPendingEvents()
        let fd = open(eventsDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.drain() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }

    /// Eventos de uma execução anterior não interessam mais.
    private func clearPendingEvents() {
        for file in eventFiles() { try? FileManager.default.removeItem(at: file) }
    }

    private func eventFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: eventsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    private func drain() {
        var incomplete = false
        defer {
            // A pasta só avisa quando um arquivo é criado, não quando termina de ser
            // escrito. Se algum ainda estava pela metade, tenta de novo daqui a pouco.
            if incomplete {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.drain() }
            }
        }
        for file in eventFiles() {
            guard let data = try? Data(contentsOf: file),
                  let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { incomplete = true; continue }
            try? FileManager.default.removeItem(at: file)

            switch file.lastPathComponent.split(separator: ".").first {
            case "SessionStart":
                onEvent?(.sessionStarted(payload: payload))
            case "UserPromptSubmit":
                onEvent?(.promptSubmitted(payload: payload))
            case "Stop":
                onEvent?(.stopped(payload: payload))
            case "Notification":
                onEvent?(.notification(message: payload["message"] as? String ?? ""))
            default:
                break
            }
        }
    }
}
