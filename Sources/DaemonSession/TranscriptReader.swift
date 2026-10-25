import Foundation
import DaemonCore

/// Lê as transcrições do Claude Code (arquivos JSONL, um objeto por linha): a pasta onde
/// cada conversa nasceu e o título dela, para retomar conversas.
enum TranscriptReader {
    /// Pasta onde a conversa nasceu, lida da própria transcrição (o primeiro `cwd`).
    /// É nela que `--resume` precisa rodar; a pasta "atual" muda quando o Claude faz `cd`.
    static func originalWorkingDirectory(sessionID: String) -> String? {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let projects = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let file = project.appendingPathComponent("\(sessionID).jsonl")
            guard let handle = FileHandle(forReadingAtPath: file.path) else { continue }
            defer { try? handle.close() }
            // O `cwd` aparece logo nas primeiras linhas; não precisa ler o arquivo todo.
            guard let head = try? handle.read(upToCount: 256_000),
                  let text = String(data: head, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"cwd\"") {
                if let entry = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                   let cwd = entry["cwd"] as? String {
                    return cwd
                }
            }
        }
        return nil
    }

    /// As conversas mais recentes de todas as pastas, da mais nova para a mais antiga.
    static func recentConversations(limit: Int) -> [ConversationSummary] {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let projects = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        // Só os arquivos da raiz de cada pasta: as subpastas guardam conversas de subagentes.
        var files: [(url: URL, modified: Date)] = []
        for project in projects {
            let entries = (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for url in entries where url.pathExtension == "jsonl" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                files.append((url, date))
            }
        }
        files.sort { $0.modified > $1.modified }

        return files.prefix(limit).compactMap { file in
            let id = file.url.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: id) != nil,
                  let cwd = originalWorkingDirectory(sessionID: id)
            else { return nil }
            return ConversationSummary(id: id, title: title(of: file.url) ?? String(id.prefix(8)),
                                       workingDirectory: cwd, modified: file.modified)
        }
    }

    /// Título da conversa: o que o usuário deu (/rename) ou, se não tiver, o que o Claude gerou.
    /// O título é regravado ao longo do arquivo, então o fim basta.
    private static func title(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 300_000 ? size - 300_000 : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        var custom: String?
        var generated: String?
        for line in text.split(separator: "\n") where line.contains("-title\"") {
            guard let entry = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            if let title = entry["customTitle"] as? String { custom = title }
            if let title = entry["aiTitle"] as? String { generated = title }
        }
        return custom ?? generated
    }
}
