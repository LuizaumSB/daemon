import Foundation

/// Prepara o zsh do terminal do Daemon.
///
/// O terminal roda um zsh de verdade (com o ambiente do usuário) e abre o CLI dentro dele.
/// Quando o CLI fecha, sobra o shell: dá para rodar `cd … && claude --resume …` e trocar
/// para uma conversa de outra pasta. Para os hooks do Daemon valerem também nesse
/// `claude` digitado à mão, o zsh ganha uma função `claude` que acrescenta `--settings`.
///
/// O zsh lê os arquivos de inicialização da pasta `ZDOTDIR`. O Daemon aponta `ZDOTDIR`
/// para uma pasta própria, cujos arquivos carregam os originais do usuário e depois
/// acrescentam a função e o comando inicial.
enum ShellBootstrap {
    static let directory = AppSupport.directory.appendingPathComponent("zsh", isDirectory: true)

    /// Variáveis que o terminal recebe para o zsh do Daemon funcionar.
    static func environment(hooksFile: String?, startCommand: String) -> [String: String] {
        var env = ["ZDOTDIR": directory.path, "DAEMON_START": startCommand]
        env["DAEMON_HOOKS"] = hooksFile
        return env
    }

    static func install() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Cada arquivo só repassa para o original do usuário, se existir.
        for name in [".zshenv", ".zprofile", ".zlogin"] {
            let script = "[ -f \"$HOME/\(name)\" ] && source \"$HOME/\(name)\"\n"
            try script.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let zshrc = """
        # Gerado pelo Daemon. Carrega o .zshrc do usuário e acrescenta o que o Daemon precisa.
        [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"

        # O zsh do macOS guarda o histórico de comandos dentro do ZDOTDIR; aqui ele volta
        # para o arquivo de sempre, para a setinha para cima ser a mesma do terminal normal.
        [[ "$HISTFILE" == "$ZDOTDIR"/* ]] && HISTFILE="$HOME/.zsh_history"

        # Todo `claude` aberto neste terminal leva os hooks do Daemon, para o bot acompanhar.
        # `function nome { }` em vez de `nome() { }`: não quebra se houver um alias `claude`.
        if [ -n "$DAEMON_HOOKS" ]; then
          unalias claude 2>/dev/null
          function claude { command claude --settings "$DAEMON_HOOKS" "$@"; }
        fi

        # Comando inicial (abrir o claude), rodado uma vez só.
        if [ -n "$DAEMON_START" ]; then
          __daemon_start="$DAEMON_START"
          unset DAEMON_START
          eval "$__daemon_start"
          unset __daemon_start
        fi

        """
        try zshrc.write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
    }
}
