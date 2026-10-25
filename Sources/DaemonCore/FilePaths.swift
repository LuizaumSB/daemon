import Foundation

/// Caminhos de arquivo prontos para o shell.
public enum FilePaths {
    /// Escapa com barra invertida tudo que o shell interpretaria (espaço, aspas, parênteses,
    /// &, ;...). Letras com acento continuam como estão.
    public static func escaped(_ path: String) -> String {
        let safe = Set("/._-+@%:,=~")
        return path.map { char in
            char.isLetter || char.isNumber || safe.contains(char) ? String(char) : "\\" + String(char)
        }.joined()
    }
}
