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

    // MARK: - Copiar

    /// ⌘C. O `copy` do SwiftTerm grava a seleção na área de transferência, mesmo vazia: sem
    /// nada selecionado, ele apagaria o que já estava lá, inclusive o que o Claude Code copiou
    /// por conta própria (ele copia mandando o texto pelo terminal, pelo código OSC 52).
    /// Aqui, sem seleção, a área de transferência fica como está.
    override func copy(_ sender: Any) {
        guard let text = getSelection(), !text.isEmpty else { return }
        super.copy(sender)
    }

    // MARK: - Cursor

    /// O Claude Code esconde e mostra o cursor a cada quadro que desenha, e o SwiftTerm
    /// aplicaria isso na hora, no meio do quadro: o cursor pisca pela tela. Ignorando estes
    /// avisos, quem mostra ou esconde o cursor é o redesenho da tela (que já lê o estado do
    /// cursor), então ele só muda quando o quadro está pronto.
    override func showCursor(source: Terminal) {}
    override func hideCursor(source: Terminal) {}

    private static func fileURLs(in info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}
