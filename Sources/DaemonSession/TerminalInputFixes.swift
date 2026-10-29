import AppKit
import SwiftTerm

/// Dois ajustes no terminal do SwiftTerm para o Claude Code funcionar como num terminal
/// comum (iTerm, Terminal):
/// - Shift+Enter pula linha em vez de enviar;
/// - a rolagem do mouse/trackpad chega ao programa quando ele usa a tela alternativa;
/// - o clique que só dá o foco ao terminal não chega ao programa (no Claude Code, um clique
///   abre o bloco que está embaixo dele);
/// - arrastar com ⌥ (Option) ou Shift seleciona texto mesmo quando o programa liga o "modo
///   mouse" (o Claude Code em tela cheia liga), como no Terminal e no Cursor.
///
/// O SwiftTerm não deixa sobrescrever `keyDown`/`scrollWheel` de fora do pacote, então os
/// eventos são interceptados antes de chegar ao terminal (monitor local de eventos do app).
@MainActor
final class TerminalInputFixes {
    private weak var terminalView: LocalProcessTerminalView?
    private var monitor: Any?
    /// Trackpads mandam rolagem em pedacinhos; acumula até dar uma linha inteira.
    private var pendingScroll: CGFloat = 0
    /// O "soltar" do clique de foco também não pode chegar ao programa.
    private var swallowMouseUp = false
    /// Durante um arraste com ⌥/Shift, o repasse do mouse ao programa fica desligado.
    private var forcingSelection = false

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                // `nil` = evento tratado aqui, não segue para o terminal.
                return self.handle(event) ? nil : event
            }
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let view = terminalView, let window = view.window, event.window === window else { return false }
        switch event.type {
        case .keyDown:
            return window.firstResponder === view && handleKey(event, in: view)
        case .scrollWheel:
            let point = view.convert(event.locationInWindow, from: nil)
            return view.bounds.contains(point) && handleScroll(event, in: view)
        case .leftMouseDown:
            // Como no Terminal e no Cursor: o primeiro clique num terminal sem foco só dá o
            // foco. O SwiftTerm repassaria esse clique ao programa (o `mouseDown` dele não
            // pode ser sobrescrito de fora do pacote, por isso o monitor).
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else { return false }
            if window.firstResponder !== view {
                window.makeFirstResponder(view)
                swallowMouseUp = true
                return true
            }
            // Com ⌥ ou Shift, o SwiftTerm seleciona em vez de repassar o mouse: desliga o
            // repasse até o botão ser solto. O evento segue para o terminal normalmente.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !flags.isDisjoint(with: [.option, .shift]), view.getTerminal().mouseMode != .off {
                view.allowMouseReporting = false
                forcingSelection = true
            }
            return false
        case .leftMouseUp:
            if forcingSelection {
                forcingSelection = false
                // Religa depois que o terminal tratar este "soltar" (que fecha a seleção).
                DispatchQueue.main.async { [weak view] in view?.allowMouseReporting = true }
                return false
            }
            guard swallowMouseUp else { return false }
            swallowMouseUp = false
            return true
        default:
            return false
        }
    }

    private func handleKey(_ event: NSEvent, in view: LocalProcessTerminalView) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Return (36) ou Enter do teclado numérico (76) com Shift: ESC + Enter, a sequência
        // que o Claude Code entende como "nova linha" (a mesma do Option+Enter).
        guard flags == .shift, event.keyCode == 36 || event.keyCode == 76 else { return false }
        view.send(txt: "\u{1b}\r")
        return true
    }

    private func handleScroll(_ event: NSEvent, in view: LocalProcessTerminalView) -> Bool {
        let terminal = view.getTerminal()
        // Tela normal: o próprio SwiftTerm rola o histórico.
        guard terminal.isCurrentBufferAlternate else { return false }

        // Tela alternativa (o Claude Code, por exemplo): o terminal não tem histórico,
        // quem rola é o programa. A rolagem vai para ele.
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 12 : 1
        pendingScroll += event.scrollingDeltaY
        let lines = Int(pendingScroll / step)
        guard lines != 0 else { return true }
        pendingScroll -= CGFloat(lines) * step

        let up = lines > 0
        for _ in 0..<min(abs(lines), 10) {
            if view.allowMouseReporting && terminal.mouseMode != .off {
                // Roda do mouse no protocolo de mouse do terminal: botão 4 (cima) / 5 (baixo).
                let (col, row) = cell(at: event, in: view)
                let flags = terminal.encodeButton(button: up ? 4 : 5, release: false, shift: false, meta: false, control: false)
                terminal.sendEvent(buttonFlags: flags, x: col, y: row)
            } else {
                // O programa não pediu mouse: setas para cima/baixo, como no Terminal do macOS.
                view.send(txt: up ? "\u{1b}[A" : "\u{1b}[B")
            }
        }
        return true
    }

    /// Coluna e linha do terminal sob o ponteiro.
    private func cell(at event: NSEvent, in view: NSView) -> (Int, Int) {
        let point = view.convert(event.locationInWindow, from: nil)
        let terminal = (view as! LocalProcessTerminalView).getTerminal()
        let col = Int(point.x / max(view.bounds.width, 1) * CGFloat(terminal.cols))
        let row = Int((view.bounds.height - point.y) / max(view.bounds.height, 1) * CGFloat(terminal.rows))
        return (min(max(col, 0), terminal.cols - 1), min(max(row, 0), terminal.rows - 1))
    }
}
