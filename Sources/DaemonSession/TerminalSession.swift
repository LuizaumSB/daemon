import AppKit
import DaemonCore
import SwiftTerm

/// Sessão real: o CLI rodando num terminal de verdade (PTY + SwiftTerm).
///
/// O processo vive enquanto o app viver. A mesma `terminalView` é usada no terminal
/// completo; o bot flutuante manda texto com `send` e mostra a conversa lida da
/// transcrição. Trocar de conversa é com /resume dentro do terminal: o hook
/// `SessionStart` avisa e o bot passa a seguir a conversa nova.
@MainActor
public final class TerminalSession: NSObject, SessionController {
    public private(set) var state: SessionState = .stopped {
        didSet { onStateChange?(state) }
    }
    public private(set) var activity: SessionActivity = .idle {
        didSet { onActivityChange?(activity) }
    }
    public let config: CLIConfig
    public var onStateChange: ((SessionState) -> Void)?
    public var onActivityChange: ((SessionActivity) -> Void)?

    /// Chave da aba: separa hooks, eventos e última conversa de cada sessão viva.
    private let key: String
    /// Nome dado a uma conversa nova (`--name`).
    private let name: String
    private let terminal: LocalProcessTerminalView
    private let hooks: HookBridge
    private var inputFixes: TerminalInputFixes?
    private var startedAt = Date()
    private var resumedSession = false

    /// Os hooks e a retomada de sessão só existem no Claude Code.
    private var isClaude: Bool {
        (config.executable as NSString).lastPathComponent == "claude"
    }

    public init(key: String, name: String, config: CLIConfig) {
        self.key = key
        self.name = name
        self.config = config
        hooks = HookBridge(key: key)
        // Já nasce do tamanho do terminal completo (920x580 menos as margens do painel),
        // para o CLI não ter que redesenhar tudo quando o painel abre pela primeira vez.
        terminal = DaemonTerminalView(frame: NSRect(x: 0, y: 0, width: 908, height: 544))
        super.init()
        terminal.processDelegate = self
        applyAppearance()
        inputFixes = TerminalInputFixes(terminalView: terminal)
        hooks.onEvent = { [weak self] event in self?.handle(event) }
    }

    public func start() throws {
        guard state == .stopped || state == .sleeping || isExited else { return }
        if state == .sleeping {
            // Limpa a tela antiga: o Claude redesenha a conversa ao retomar.
            terminal.getTerminal().resetToInitialState()
        }
        state = .starting
        startedAt = Date()

        var cliArgs = config.arguments
        var directory = config.workingDirectory
        var hooksFile: String?
        if isClaude {
            hooksFile = try hooks.writeSettings().path
            if let last = AppSupport.loadLastSession(key: key) {
                // Reabre a última conversa usada, na pasta onde ela nasceu: continua de onde parou.
                cliArgs += ["--resume", last.id]
                directory = TranscriptReader.originalWorkingDirectory(sessionID: last.id) ?? last.workingDirectory
                resumedSession = true
            } else {
                // Primeira vez: conversa nova com o nome da aba e a mensagem inicial, se houver.
                let id = UUID().uuidString.lowercased()
                AppSupport.saveLastSession(.init(id: id, workingDirectory: directory), key: key)
                cliArgs += ["--name", name, "--session-id", id]
                if let prompt = config.initialPrompt { cliArgs.append(prompt) }
                resumedSession = false
            }
            hooks.startWatching()
        }

        // Apps abertos pelo Finder não herdam o PATH do terminal. Rodar dentro de um
        // shell de login (-l) carrega o mesmo ambiente que o usuário tem no terminal.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Self.environment()
        if (shell as NSString).lastPathComponent == "zsh" {
            // Terminal de verdade: o zsh fica aberto e roda o CLI dentro dele. Quando o CLI
            // fecha, sobra o shell (para `cd … && claude --resume …`, por exemplo).
            // No zsh do Daemon, `claude` já acrescenta o `--settings` com os hooks.
            let quoted = cliArgs.map(Self.shellQuote).joined(separator: " ")
            // `claude` sem aspas, para o zsh usar a função que põe os hooks. Os outros CLIs
            // também vão sem aspas: o usuário pode ter digitado argumentos no "+"
            // (ex.: `aider --model x`), e o comando é dele, rodando no shell dele.
            let program = isClaude ? "claude" : config.executable
            try ShellBootstrap.install()
            env.merge(ShellBootstrap.environment(hooksFile: hooksFile, startCommand: "\(program) \(quoted)")) { $1 }
            terminal.startProcess(
                executable: shell,
                args: ["-l", "-i"],
                environment: env.map { "\($0.key)=\($0.value)" },
                currentDirectory: directory
            )
        } else {
            // Outros shells: roda o CLI direto, com os hooks na linha de comando.
            let args = cliArgs + (hooksFile.map { ["--settings", $0] } ?? [])
            let command = ([config.executable] + args.map(Self.shellQuote)).joined(separator: " ")
            terminal.startProcess(
                executable: shell,
                args: ["-l", "-i", "-c", "exec \(command)"],
                environment: env.map { "\($0.key)=\($0.value)" },
                currentDirectory: directory
            )
        }
        state = .running

        // CLIs sem suporte a prompt inicial recebem a mensagem digitada depois de abrir.
        if !isClaude, let prompt = config.initialPrompt {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.send(prompt) }
        }
    }

    public func stop() {
        guard state == .running || state == .starting || state == .sleeping else { return }
        endProcess()
        state = .stopped
        activity = .idle
    }

    /// Hiberna: encerra o CLI e libera a memória dele (uns 250 MB no Claude). A conversa
    /// continua salva na transcrição, e `wake()` reabre a mesma com `--resume`.
    /// Só o Claude: os outros CLIs não têm hooks (não dá para saber se estão trabalhando)
    /// nem retomada automática da última conversa.
    public func sleep() {
        guard isClaude, state == .running, activity == .idle else { return }
        endProcess()
        state = .sleeping
    }

    public func wake() {
        guard state == .sleeping else { return }
        try? start()
    }

    public func restart() throws {
        stop()
        try start()
    }

    public func send(_ text: String) {
        guard state == .running else { return }
        // Colagem "entre colchetes": o CLI recebe o texto inteiro de uma vez, mesmo com
        // quebras de linha, sem cada Enter virar um envio. Depois, o Enter de verdade.
        if terminal.getTerminal().bracketedPasteMode {
            terminal.send(txt: "\u{1b}[200~\(text)\u{1b}[201~")
        } else {
            terminal.send(txt: text.replacingOccurrences(of: "\n", with: " "))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.terminal.send(txt: "\r")
        }
        activity = .thinking
    }

    public func terminalView() -> NSView { terminal }

    // MARK: - Privado

    /// Encerra o shell e tudo o que roda dentro dele (o CLI e os servidores MCP dele).
    /// O `terminate()` do SwiftTerm só manda SIGTERM ao shell, e o zsh interativo ignora
    /// SIGTERM: o Claude de uma aba fechada continuava vivo até o app fechar.
    private func endProcess() {
        hooks.stopWatching()
        let shell = terminal.process.shellPid
        // Lista os descendentes antes de o shell morrer: depois eles viram filhos do launchd
        // e não dá mais para achar quem era de quem.
        let children = shell > 0 ? Self.descendants(of: shell) : []
        for pid in children { kill(pid, SIGTERM) }
        // SIGHUP é o "terminal fechou": o zsh sai (e avisa os jobs dele).
        if shell > 0 { kill(shell, SIGHUP) }
        terminal.terminate()
        // Quem não saiu por bem em 3 s sai à força.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for pid in children + [shell] where pid > 0 && kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    /// Filhos, netos etc. de um processo (do mais próximo para o mais distante).
    private static func descendants(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        // Recebe o tamanho do buffer em bytes, mas devolve quantos PIDs achou.
        let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        let children = Array(buffer.prefix(max(0, Int(count)))).filter { $0 > 0 }
        return children + children.flatMap(descendants)
    }

    private var isExited: Bool {
        if case .exited = state { return true }
        return false
    }

    private func handle(_ event: HookBridge.Event) {
        switch event {
        case .sessionStarted(let payload):
            // Início, ou troca de conversa com /resume: passa a seguir a conversa nova
            // e lembra dela para o próximo início do app.
            follow(payload)
        case .promptSubmitted(let payload):
            follow(payload)
            activity = .thinking
        case .stopped(let payload):
            follow(payload)
            activity = .idle
        case .notification(let message):
            activity = .needsAttention(message: message)
        }
    }

    /// Atualiza a conversa atual com o que o hook informou.
    private func follow(_ payload: [String: Any]) {
        guard let id = payload["session_id"] as? String,
              id != AppSupport.loadLastSession(key: key)?.id
        else { return }
        // Conversa nova (troca com /resume). A pasta é a de origem da conversa, não o
        // `cwd` do hook: esse muda quando o Claude faz `cd` no meio da conversa.
        let cwd = TranscriptReader.originalWorkingDirectory(sessionID: id) ?? payload["cwd"] as? String
        if let cwd { AppSupport.saveLastSession(.init(id: id, workingDirectory: cwd), key: key) }
    }

    private func applyAppearance() {
        // Igual ao Terminal do macOS: Option compõe caracteres (ç, ã, é...) em vez de
        // funcionar como tecla Meta, que é o padrão do SwiftTerm.
        terminal.optionAsMetaKey = false
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        terminal.nativeForegroundColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        terminal.caretColor = .systemGreen
    }

    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "pt_BR.UTF-8"
        // Se o app for aberto de dentro de uma sessão do Claude Code, herda variáveis dela
        // que fazem o CLI se achar "filho" daquela sessão e parar de salvar a conversa.
        // O shell de login recoloca as que o usuário configurou de propósito.
        for key in env.keys where key == "CLAUDECODE" || key.hasPrefix("CLAUDE_CODE_") {
            env.removeValue(forKey: key)
        }
        return env
    }

    /// Coloca o argumento entre aspas simples para o shell não interpretar nada nele.
    private static func shellQuote(_ arg: String) -> String {
        "'" + arg.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension TerminalSession: LocalProcessTerminalViewDelegate {
    public nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    public nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    public nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    public nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.hooks.stopWatching()
            // Se a retomada falhou logo de cara (sessão apagada, por exemplo), esquece o
            // ID para o próximo início abrir uma sessão nova em vez de falhar de novo.
            if self.resumedSession, Date().timeIntervalSince(self.startedAt) < 5, exitCode != 0 {
                AppSupport.saveLastSession(nil, key: self.key)
            }
            // Ao trocar de sessão, o aviso de "terminou" do processo antigo chega depois
            // que o novo já subiu; esse aviso atrasado não vale para o novo.
            // Parada de propósito (fechar a aba ou hibernar) também não vira "terminou".
            guard self.state != .stopped, self.state != .sleeping, !self.terminal.process.running else { return }
            self.state = .exited(code: exitCode ?? -1)
            self.activity = .idle
        }
    }
}
