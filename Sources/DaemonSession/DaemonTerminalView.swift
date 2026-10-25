import AppKit
import DaemonCore
import SwiftTerm

/// O terminal do SwiftTerm com uma coisa a mais: aceitar arquivos arrastados do Finder,
/// como o Terminal do macOS. Soltar um arquivo "digita" o caminho dele, com espaços e
/// caracteres especiais escapados. O Claude Code reconhece caminho de imagem colado e
/// anexa a imagem à mensagem.
///
/// O SwiftTerm não trata arquivos arrastados, mas a classe dele é `open`: dá para estender
/// por herança, sem mexer no pacote.
final class DaemonTerminalView: LocalProcessTerminalView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("não usado") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(in: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(in: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(in: sender)
        guard !urls.isEmpty else { return false }
        // Separados por espaço e com um espaço no fim, como o Terminal faz.
        let text = urls.map { FilePaths.escaped($0.path) }.joined(separator: " ") + " "
        // Como colagem (se o programa pediu "colagem entre colchetes"): é assim que o
        // Claude Code percebe que é um arquivo colado, e não texto digitado letra a letra.
        if getTerminal().bracketedPasteMode {
            send(txt: "\u{1b}[200~\(text)\u{1b}[201~")
        } else {
            send(txt: text)
        }
        window?.makeFirstResponder(self)
        return true
    }

    private static func fileURLs(in info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}
