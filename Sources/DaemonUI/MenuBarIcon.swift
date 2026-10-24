import AppKit
import SwiftUI

/// O ícone da menu bar: o cubo do mascote em versão chapada (`CubeGlyph`), em uma cor só.
///
/// É uma imagem "template": o macOS pinta de preto ou branco conforme o tema da menu
/// bar, como os ícones do sistema. Um desenho 3D com sombra ficaria borrado em 18 pontos.
@MainActor
public enum MenuBarIcon {
    public static let image: NSImage = {
        let side: CGFloat = 18
        let renderer = ImageRenderer(content: CubeGlyph().frame(width: side, height: side))
        // Desenha em 3x, para ficar nítido em qualquer tela (o macOS reduz sozinho).
        renderer.scale = 3
        let image = renderer.cgImage.map { NSImage(cgImage: $0, size: NSSize(width: side, height: side)) }
            ?? NSImage(size: NSSize(width: side, height: side))
        image.isTemplate = true
        return image
    }()
}
