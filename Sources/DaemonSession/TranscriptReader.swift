import Foundation
import DaemonCore

/// Lê a transcrição do Claude Code (um arquivo JSONL, um objeto por linha) e monta a
/// conversa que o bot mostra. É a mesma conversa do terminal, então os dois ficam iguais.
enum TranscriptReader {
    /// Onde o Claude Code guarda a transcrição: uma pasta por diretório de trabalho
    /// (com tudo que não é letra ou número trocado por "-") e um arquivo por sessão.
    static func path(sessionID: String, workingDirectory: String) -> String {
        let folder = String(workingDirectory.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(folder)/\(sessionID).jsonl").path
    }

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

    /// As últimas `limit` mensagens: o que foi digitado e a resposta de cada vez.
    /// Lê só o fim do arquivo, porque transcrições longas passam de vários MB.
    static func history(path: String, limit: Int = 30, tailBytes: Int = 1_500_000) -> [ChatMessage] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let content = String(data: data, encoding: .utf8) else { return [] }

        var lines = content.split(separator: "\n")
        // Começou no meio do arquivo: a primeira linha está cortada.
        if start > 0, !lines.isEmpty { lines.removeFirst() }

        var messages: [ChatMessage] = []
        var replyParts: [String] = []
        var replyID: String?

        func flushReply() {
            let text = replyParts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { messages.append(ChatMessage(id: replyID ?? UUID().uuidString, author: .assistant, text: text)) }
            replyParts.removeAll()
            replyID = nil
        }

        for line in lines {
            // Filtro barato antes de decodificar: só interessam mensagens.
            guard line.contains("\"message\""),
                  let entry = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  entry["isSidechain"] as? Bool != true,
                  let message = entry["message"] as? [String: Any]
            else { continue }
            let id = entry["uuid"] as? String ?? UUID().uuidString

            switch entry["type"] as? String {
            case "user":
                guard entry["isMeta"] as? Bool != true, let text = typedText(message) else { continue }
                flushReply()
                messages.append(ChatMessage(id: id, author: .user, text: text))
            case "assistant":
                for block in message["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "text" {
                    if let text = block["text"] as? String { replyParts.append(text) }
                }
                if replyID == nil { replyID = id }
            default:
                break
            }
        }
        flushReply()
        return Array(messages.suffix(limit))
    }

    /// Texto digitado numa mensagem "user". Mensagens "user" também carregam resultados de
    /// ferramentas e avisos internos (entre <tags>); esses ficam de fora, menos comandos
    /// como /resume, que aparecem pelo nome.
    private static func typedText(_ message: [String: Any]) -> String? {
        let raw: String?
        if let text = message["content"] as? String {
            raw = text
        } else {
            let blocks = message["content"] as? [[String: Any]] ?? []
            if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return nil }
            raw = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
        }
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("<") {
            guard let range = text.range(of: "<command-name>"),
                  let end = text.range(of: "</command-name>", range: range.upperBound..<text.endIndex)
            else { return nil }
            return String(text[range.upperBound..<end.lowerBound])
        }
        return text
    }
}
