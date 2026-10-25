import AppKit

/// Janela do chat e do terminal. É uma janela comum: fica por cima só enquanto está em
/// uso e vai para trás quando o usuário clica em outro app. Quem fica sempre por cima é só
/// o mascote.
final class FloatingPanel: NSPanel {
    /// Devolve `true` se tratou o atalho (⌘ + tecla).
    var onShortcut: ((NSEvent) -> Bool)?

    init(contentRect: NSRect, resizable: Bool = true) {
        var style: NSWindow.StyleMask = [.titled, .fullSizeContentView, .closable]
        if resizable { style.insert(.resizable) }
        super.init(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)

        level = .normal
        // Abre no Space em que o usuário está, e aparece no Mission Control como janela normal.
        collectionBehavior = [.moveToActiveSpace, .managed, .participatesInCycle]
        // Move só pela faixa do topo; arrastar no conteúdo seleciona texto.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.97)
        appearance = NSAppearance(named: .darkAqua)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    /// ⌘C, ⌘V, ⌘X, ⌘A e ⌘Z. Num app normal quem entrega esses atalhos é o menu Editar;
    /// o Daemon vive só na menu bar e não tem esse menu, então o painel entrega direto
    /// para quem estiver com o foco (o terminal ou um campo de texto).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Atalhos do próprio painel (trocar de aba, abrir o terminal) vêm antes de tudo,
        // para funcionarem também com o foco no terminal.
        if onShortcut?(event) == true { return true }
        if flags == .command, let key = event.charactersIgnoringModifiers {
            let action: Selector? = switch key {
            case "c": #selector(NSText.copy(_:))
            case "v": #selector(NSText.paste(_:))
            case "x": #selector(NSText.cut(_:))
            case "a": #selector(NSText.selectAll(_:))
            case "z": Selector(("undo:"))
            default: nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
