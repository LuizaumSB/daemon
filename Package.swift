// swift-tools-version: 5.10
// O Package.swift é a "receita" do projeto: quais módulos existem, de quem cada um
// depende e para qual sistema compilar. O SwiftPM lê este arquivo no `swift build`.
import PackageDescription

let package = Package(
    name: "Daemon",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Terminal de verdade (emulador VT100/xterm) para AppKit, com PTY embutido.
        // Fixo na 1.11.2: da 1.12 em diante vem um shader Metal que só compila com o Xcode
        // completo, e o projeto compila só com as Command Line Tools.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.11.2"),
    ],
    targets: [
        // Contrato entre as frentes: protocolos e tipos simples, sem lógica de UI nem de PTY.
        .target(name: "DaemonCore"),

        // Frente A: menu bar, painel flutuante, atalho global, expandir para terminal.
        // Só conhece o DaemonCore, nunca o DaemonSession.
        .target(name: "DaemonUI", dependencies: ["DaemonCore"]),

        // Frente B: PTY, processo do CLI sempre vivo, configuração do CLI.
        // Só conhece o DaemonCore, nunca o DaemonUI.
        .target(
            name: "DaemonSession",
            dependencies: ["DaemonCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),

        // O app em si: liga a sessão real (B) à interface (A).
        .executableTarget(
            name: "Daemon",
            dependencies: ["DaemonCore", "DaemonUI", "DaemonSession"]
        ),
    ]
)
