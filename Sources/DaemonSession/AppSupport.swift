import Foundation

/// Pastas e arquivos que o Daemon guarda em ~/Library/Application Support/Daemon.
enum AppSupport {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Daemon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Onde os hooks de uma sessão deixam um arquivo por evento (Stop, UserPromptSubmit...).
    /// Uma pasta por sessão viva: assim cada evento chega na sessão certa.
    static func eventsDirectory(for key: String) -> URL {
        let dir = directory.appendingPathComponent("events/\(key)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Settings extras passados ao `claude --settings`, só com os hooks daquela sessão.
    static func hookSettingsFile(for key: String) -> URL {
        let dir = directory.appendingPathComponent("hooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(key).json")
    }

    /// A conversa em que cada aba estava, para reabrir nela. Muda quando o usuário troca
    /// de conversa com /resume no terminal daquela aba.
    struct LastSession: Codable {
        var id: String
        var workingDirectory: String
    }

    /// Um arquivo por aba. A do Daemon ("main") mantém o nome de antes das abas.
    static func lastSessionFile(for key: String) -> URL {
        directory.appendingPathComponent(key == "main" ? "last-session.json" : "last-session-\(key).json")
    }

    static func loadLastSession(key: String) -> LastSession? {
        if let data = try? Data(contentsOf: lastSessionFile(for: key)) {
            return try? JSONDecoder().decode(LastSession.self, from: data)
        }
        // Versões antigas guardavam só o ID da sessão própria, que roda em ~/Documents.
        let legacy = directory.appendingPathComponent("session-id")
        guard key == "main", let id = try? String(contentsOf: legacy, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), UUID(uuidString: id) != nil
        else { return nil }
        return LastSession(id: id, workingDirectory: NSString(string: "~/Documents").expandingTildeInPath)
    }

    static func saveLastSession(_ session: LastSession?, key: String) {
        let file = lastSessionFile(for: key)
        if let session, let data = try? JSONEncoder().encode(session) {
            try? data.write(to: file, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
