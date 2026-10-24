import SwiftUI
import AppKit

// Ícone do app no padrão da Apple: canvas 1024, squircle de 824 no meio, cubo em cima.
// Compilado junto com o CubeMascot.swift pelo scripts/make-icon.sh.
@MainActor func icon(darkBackground: Bool) -> some View {
    let top = darkBackground ? Color(red: 0.20, green: 0.22, blue: 0.26) : Color(red: 0.97, green: 0.97, blue: 0.98)
    let bottom = darkBackground ? Color(red: 0.06, green: 0.06, blue: 0.08) : Color(red: 0.82, green: 0.84, blue: 0.87)
    return ZStack {
        RoundedRectangle(cornerRadius: 185, style: .continuous)
            .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            .frame(width: 824, height: 824)
        // Fundo escuro leva o cubo claro, e vice-versa.
        CubeMascot(mood: .idle, dark: !darkBackground)
            .frame(width: 900, height: 900)
            .shadow(color: .black.opacity(darkBackground ? 0.55 : 0.3), radius: 28, y: 18)
            .offset(y: 4)
    }
    .frame(width: 1024, height: 1024)
}

@MainActor func save(_ view: some View, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let cg = renderer.cgImage else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

MainActor.assumeIsolated {
    save(icon(darkBackground: true), to: CommandLine.arguments[1])
    save(icon(darkBackground: false), to: CommandLine.arguments[2])
}
