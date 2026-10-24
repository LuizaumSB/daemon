import SwiftUI

/// O cubo do Daemon desenhado em código: um cubo 3D de verdade (8 vértices girados e
/// projetados na tela), com a cara mudando conforme o estado. Por ser vetor, fica nítido
/// em qualquer tamanho. Tudo é calculado numa grade de 100×100 e depois escalado.
/// Tudo que dá para ajustar no visual do mascote, num lugar só. Para mudar o jeito
/// dele, mexa aqui; o resto do arquivo só usa estes valores.
enum MascotStyle {
    // Ângulo de câmera, em graus.
    /// De lado: positivo mostra a lateral esquerda.
    static let yaw: Double = 18
    /// Para frente: positivo mostra o topo (visto de cima); negativo, a base (visto de baixo).
    static let pitch: Double = -7
    /// Inclinação, como na logo: positivo levanta o lado direito.
    static let tilt: Double = 4

    // Chifres. Posição no topo do cubo (x e z vão de −1 a 1; o cubo tem lado 2).
    static let horns = [HornSpot(x: -0.5, z: 0.15), HornSpot(x: 0.5, z: -0.1)]
    /// Raio da base e altura de cada chifre, na mesma medida do cubo.
    static let hornRadius = 0.15
    static let hornHeight = 0.42

    // Luz e forma.
    /// De onde vem a luz (x: direita, y: cima, z: frente). Define qual face fica clara.
    static let light = (x: 0.45, y: 0.7, z: 0.6)
    /// Luz mínima de uma face na sombra (0 = preto, 1 = sem sombra).
    static let ambient = 0.2
    /// Arredondamento das bordas do cubo (na grade 100×100).
    static let cornerRadius: CGFloat = 7
    /// Grossura dos olhos e da boca (na grade 100×100).
    static let featureWidth: CGFloat = 6.5

    struct HornSpot { let x: Double; let z: Double }
}

struct CubeMascot: View {
    enum Mood: Equatable {
        /// Pronto: a cara da logo, `> <`.
        case idle
        /// Pensando: olhos de bolinha olhando de um lado para o outro.
        case thinking
        /// Esperando o usuário: a cara da logo; quem avisa é o brilho laranja e o pulinho.
        case attention
        /// Terminou uma resposta que o usuário ainda não viu: `^ ^` sorrindo.
        case happy
        /// Sessão parada: `x x`.
        case stopped
    }

    let mood: Mood
    let dark: Bool
    /// Olhos fechados (piscada).
    var blinking = false
    /// Para onde os olhos olham, em unidades da grade (−3 a 3).
    var look: CGFloat = 0
    /// Giro de lado (graus): positivo mostra a lateral esquerda.
    var yaw: Double = MascotStyle.yaw
    /// Giro para frente (graus): positivo mostra o topo; negativo, a base (visto de baixo).
    var pitch: Double = MascotStyle.pitch
    /// Inclinação, como na logo (graus): positivo levanta o lado direito.
    var tilt: Double = MascotStyle.tilt

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 100
            let cube = Projection(yaw: yaw, pitch: pitch, roll: tilt)
            // Visto de cima, os chifres ficam na frente do corpo. Visto de baixo, ficam
            // atrás: a frente do cubo esconde a base e só a ponta aparece acima da borda.
            let hornsInFront = cube.visibleFaces.contains(.top)
            ZStack {
                if !hornsInFront { horns(cube, palette) }
                cubeBody(cube, palette)
                face(cube, palette, scale: scale)
                if hornsInFront { horns(cube, palette) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var palette: Palette { dark ? .dark : .light }

    // MARK: - Corpo

    /// As faces viradas para quem olha, da mais funda para a mais próxima, com quinas
    /// retas (encaixam sem fresta). Depois o conjunto é recortado pelo contorno do cubo
    /// com as quinas arredondadas: só a borda de fora fica macia, como na logo.
    /// A cor de cada face vem da luz: quanto mais virada para a luz, mais clara.
    private func cubeBody(_ cube: Projection, _ p: Palette) -> some View {
        let faces = cube.visibleFaces
        return ZStack {
            ForEach(faces, id: \.self) { face in
                let corners = cube.corners(of: face)
                let light = cube.light(on: face)
                Grid100 { $0.addLines(corners); $0.closeSubpath() }
                    .fill(LinearGradient(
                        colors: [p.color(light: light + 0.06), p.color(light: light - 0.06)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    // Contorno fino da mesma cor: cobre o fio de fundo entre duas faces.
                    .overlay(Grid100 { $0.addLines(corners); $0.closeSubpath() }
                        .stroke(p.color(light: light), lineWidth: 0.6))
            }
            // Luz fina nas quinas da frente que encostam no topo e na lateral: chanfro.
            if faces.contains(.front) {
                Grid100 { path in
                    path.move(to: cube.point(-0.97, -0.75, 1))
                    path.addLine(to: cube.point(-0.97, 0.97, 1))
                    path.addLine(to: cube.point(0.75, 0.97, 1))
                }
                .stroke(p.bevel, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
        }
        .mask(Grid100 { $0.addRoundedPolygon(cube.silhouette, radius: MascotStyle.cornerRadius) })
    }

    /// Cada chifre é um cone: a base é um círculo no topo do cubo (girado, vira uma elipse)
    /// e a ponta fica acima dela. O contorno é o "fecho convexo" da base com a ponta.
    /// Sombreado da esquerda (sombra) para a direita (luz), com um brilho na lateral
    /// iluminada e uma sombra de contato onde encosta no cubo.
    private func horns(_ cube: Projection, _ p: Palette) -> some View {
        ZStack {
            ForEach(MascotStyle.horns, id: \.x) { spot in
                let (x, z, r) = (spot.x, spot.z, MascotStyle.hornRadius)
                let base = cube.hornBase(spot)
                let tip = cube.hornTip(spot)
                let left = base.min { $0.x < $1.x }!, right = base.max { $0.x < $1.x }!
                // Gradiente na grade 100×100: as posições viram frações do quadro.
                let shading = LinearGradient(
                    stops: [.init(color: p.horn.shadow, location: 0),
                            .init(color: p.horn.mid, location: 0.55),
                            .init(color: p.horn.lit, location: 1)],
                    startPoint: UnitPoint(x: left.x / 100, y: left.y / 100),
                    endPoint: UnitPoint(x: right.x / 100, y: right.y / 100)
                )
                ZStack {
                    // Sombra de contato no topo do cubo (só se o topo aparece; visto de
                    // baixo, a base do chifre fica escondida atrás da borda).
                    if cube.visibleFaces.contains(.top) {
                    Grid100 { path in
                        path.addLines((0..<24).map { i -> CGPoint in
                            let t = Double(i) / 24 * 2 * .pi
                            return cube.point(x + r * 1.35 * cos(t), 1, z + r * 1.35 * sin(t))
                        })
                        path.closeSubpath()
                    }
                    .fill(Color.black.opacity(p.horn.contactShadow))
                    }
                    Grid100 { $0.addRoundedPolygon(Projection.convexHull(base + [tip]), radius: 0.8) }
                        .fill(shading)
                    // Brilho descendo pela lateral iluminada, da ponta até perto da base.
                    Grid100 { path in
                        let foot = CGPoint(x: (tip.x * 0.15 + right.x * 0.85) - 1.2, y: right.y - 1)
                        path.move(to: CGPoint(x: tip.x + (foot.x - tip.x) * 0.2, y: tip.y + (foot.y - tip.y) * 0.2))
                        path.addLine(to: foot)
                    }
                    .stroke(p.horn.highlight, style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
                }
            }
        }
    }


    // MARK: - Cara

    /// A cara é desenhada num "papel" 2D e colada na face da frente do cubo com uma
    /// transformação afim, então acompanha qualquer giro.
    @ViewBuilder
    private func face(_ cube: Projection, _ p: Palette, scale: CGFloat) -> some View {
        if cube.visibleFaces.contains(.front) {
            let onFront = CGAffineTransform(translationX: look, y: 0).concatenating(cube.frontTransform)
            let eyes = blinking && mood != .stopped ? Self.closedEyes : Self.eyes(for: mood)
            let mouth = Self.mouth(for: mood)
            let width = Geometry.featureWidth * scale * cube.frontScale
            let features = Self.drawn { eyes(&$0); mouth(&$0) }
            ZStack {
                // Primeiro um traço deslocado (luz ou sombra), depois a cara por cima:
                // parece entalhado na face do cubo, como os olhos vazados da logo.
                Grid100 { $0.addPath(features, transform: onFront) }
                    .stroke(p.carveRim, style: Geometry.round(width))
                    .offset(y: p.carveRimOffset * scale)
                Grid100 { $0.addPath(features, transform: onFront) }
                    .stroke(p.carve, style: Geometry.round(width))
                if mood == .thinking {
                    let dots = Self.drawn { p in
                        for x in [46.5, 71.5] { p.addEllipse(in: CGRect(x: x - 4, y: 51, width: 8, height: 8)) }
                    }
                    Grid100 { $0.addPath(dots, transform: onFront) }
                        .fill(p.carve)
                }
            }
        }
    }

    /// Olhos e boca de uma cara, no "papel" 2D (antes de colar no cubo).
    static func faceDrawing(for mood: Mood) -> Path {
        let eyes = Self.eyes(for: mood), mouth = Self.mouth(for: mood)
        return drawn { eyes(&$0); mouth(&$0) }
    }

    private typealias Drawing = @Sendable (inout Path) -> Void

    private static func drawn(_ draw: (inout Path) -> Void) -> Path {
        var path = Path()
        draw(&path)
        return path
    }

    private static func eyes(for mood: Mood) -> Drawing {
        switch mood {
        case .idle, .attention:
            return { p in
                p.addLines([CGPoint(x: 42, y: 48), CGPoint(x: 51, y: 54), CGPoint(x: 42, y: 60)])
                p.addLines([CGPoint(x: 76, y: 48), CGPoint(x: 67, y: 54), CGPoint(x: 76, y: 60)])
            }
        case .thinking:
            // As bolinhas são preenchidas à parte; aqui não há traço.
            return { _ in }
        case .happy:
            return { p in
                p.addLines([CGPoint(x: 42, y: 57), CGPoint(x: 46.5, y: 51), CGPoint(x: 51, y: 57)])
                p.addLines([CGPoint(x: 67, y: 57), CGPoint(x: 71.5, y: 51), CGPoint(x: 76, y: 57)])
            }
        case .stopped:
            return { p in
                for x in [46.5, 71.5] {
                    p.move(to: CGPoint(x: x - 3.5, y: 50.5)); p.addLine(to: CGPoint(x: x + 3.5, y: 57.5))
                    p.move(to: CGPoint(x: x + 3.5, y: 50.5)); p.addLine(to: CGPoint(x: x - 3.5, y: 57.5))
                }
            }
        }
    }

    private static let closedEyes: Drawing = { p in
        p.move(to: CGPoint(x: 42, y: 55)); p.addLine(to: CGPoint(x: 51, y: 55))
        p.move(to: CGPoint(x: 67, y: 55)); p.addLine(to: CGPoint(x: 76, y: 55))
    }

    private static func mouth(for mood: Mood) -> Drawing {
        switch mood {
        case .idle, .attention, .stopped:
            return { p in p.move(to: CGPoint(x: 51, y: 73)); p.addLine(to: CGPoint(x: 67, y: 73)) }
        case .thinking:
            return { p in p.move(to: CGPoint(x: 55, y: 73)); p.addLine(to: CGPoint(x: 63, y: 73)) }
        case .happy:
            return { p in
                p.move(to: CGPoint(x: 51, y: 70))
                p.addQuadCurve(to: CGPoint(x: 67, y: 70), control: CGPoint(x: 59, y: 79))
            }
        }
    }
}

// MARK: - Versão chapada

/// O mesmo cubo em uma cor só, para a menu bar: silhueta do cubo e dos chifres, com a
/// cara `> <` vazada e um fio vazado entre a frente e a lateral (sugere o volume).
/// Desenhado em preto; vira imagem "template", que o macOS pinta conforme a barra.
struct CubeGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 100
            let cube = Projection(yaw: MascotStyle.yaw, pitch: MascotStyle.pitch, roll: MascotStyle.tilt)
            let face = CubeMascot.faceDrawing(for: .idle).applying(cube.frontTransform)
            ZStack {
                ForEach(MascotStyle.horns, id: \.x) { spot in
                    // Um pouco mais grossos que no mascote, para não sumirem em 18 pontos.
                    let outline = Projection.convexHull(cube.hornBase(spot, radius: MascotStyle.hornRadius * 1.4) + [cube.hornTip(spot)])
                    Grid100 { $0.addRoundedPolygon(outline, radius: 0.8) }.fill(.black)
                }
                Grid100 { $0.addRoundedPolygon(cube.silhouette, radius: MascotStyle.cornerRadius) }
                    .fill(.black)
                // `destinationOut` apaga o que está embaixo: vira um vazado no desenho.
                Grid100 { path in
                    path.move(to: cube.point(-1, 0.92, 1))
                    path.addLine(to: cube.point(-1, -0.92, 1))
                }
                .stroke(.black, style: StrokeStyle(lineWidth: 2.2 * scale, lineCap: .round))
                .blendMode(.destinationOut)
                Grid100 { $0.addPath(face) }
                    .stroke(.black, style: StrokeStyle(lineWidth: 7.5 * scale * cube.frontScale, lineCap: .round, lineJoin: .round))
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            // A grade sobra espaço em volta do cubo (para o mascote animar); aqui o cubo
            // precisa ocupar o ícone inteiro, então é ampliado.
            .scaleEffect(1.32)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 3D

/// O cubo no espaço: lado 2, centrado na origem, com y para cima e z para quem olha.
/// Gira (de lado, para frente e inclinação) e projeta na grade 100×100 sem perspectiva
/// (projeção ortográfica), o que basta para um ícone pequeno.
private struct Projection {
    enum Face: CaseIterable, Hashable { case front, back, left, right, top, bottom }

    private let yaw: Double, pitch: Double, roll: Double
    /// Centro e tamanho do cubo na grade (sobra espaço em cima para os chifres).
    private let center = CGPoint(x: 50, y: 57)
    private let size: Double = 25

    init(yaw: Double, pitch: Double, roll: Double) {
        self.yaw = yaw * .pi / 180
        self.pitch = pitch * .pi / 180
        self.roll = roll * .pi / 180
    }

    /// Gira um ponto: primeiro de lado (eixo y), depois para frente (eixo x), depois inclina (eixo z).
    func rotate(_ x: Double, _ y: Double, _ z: Double) -> (x: Double, y: Double, z: Double) {
        let x1 = x * cos(yaw) + z * sin(yaw), z1 = -x * sin(yaw) + z * cos(yaw)
        let y2 = y * cos(pitch) - z1 * sin(pitch), z2 = y * sin(pitch) + z1 * cos(pitch)
        let x3 = x1 * cos(roll) - y2 * sin(roll), y3 = x1 * sin(roll) + y2 * cos(roll)
        return (x3, y3, z2)
    }

    /// Ponto do cubo na tela (grade 100×100, com y para baixo).
    func point(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let r = rotate(x, y, z)
        return CGPoint(x: center.x + r.x * size, y: center.y - r.y * size)
    }

    private func normal(of face: Face) -> (Double, Double, Double) {
        switch face {
        case .front: return (0, 0, 1)
        case .back: return (0, 0, -1)
        case .left: return (-1, 0, 0)
        case .right: return (1, 0, 0)
        case .top: return (0, 1, 0)
        case .bottom: return (0, -1, 0)
        }
    }

    /// Os quatro cantos da face, em volta dela.
    func corners(of face: Face) -> [CGPoint] {
        let c: [(Double, Double, Double)]
        switch face {
        case .front: c = [(-1, 1, 1), (1, 1, 1), (1, -1, 1), (-1, -1, 1)]
        case .back: c = [(1, 1, -1), (-1, 1, -1), (-1, -1, -1), (1, -1, -1)]
        case .left: c = [(-1, 1, -1), (-1, 1, 1), (-1, -1, 1), (-1, -1, -1)]
        case .right: c = [(1, 1, 1), (1, 1, -1), (1, -1, -1), (1, -1, 1)]
        case .top: c = [(-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1)]
        case .bottom: c = [(-1, -1, 1), (1, -1, 1), (1, -1, -1), (-1, -1, -1)]
        }
        return c.map { point($0.0, $0.1, $0.2) }
    }

    /// Faces viradas para quem olha (normal girada com z > 0), da mais funda para a mais próxima.
    var visibleFaces: [Face] {
        Face.allCases
            .map { face -> (Face, Double) in let n = normal(of: face); return (face, rotate(n.0, n.1, n.2).z) }
            .filter { $0.1 > 0.02 }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Quanto a face recebe da luz (0 a 1).
    func light(on face: Face) -> Double {
        let n = normal(of: face)
        let r = rotate(n.0, n.1, n.2)
        // De cima, da direita e da frente: o topo e a cara ficam claros e a lateral
        // esquerda fica na sombra, como na logo. É esse contraste que dá profundidade.
        let l = MascotStyle.light
        let length = (l.x * l.x + l.y * l.y + l.z * l.z).squareRoot()
        let dot = (r.x * l.x + r.y * l.y + r.z * l.z) / length
        return MascotStyle.ambient + (1 - MascotStyle.ambient) * max(0, dot)
    }

    /// Base de um chifre: um círculo no topo do cubo, girado (vira uma elipse na tela).
    func hornBase(_ spot: MascotStyle.HornSpot, radius: Double = MascotStyle.hornRadius) -> [CGPoint] {
        (0..<24).map { i -> CGPoint in
            let t = Double(i) / 24 * 2 * .pi
            return point(spot.x + radius * cos(t), 1, spot.z + radius * sin(t))
        }
    }

    func hornTip(_ spot: MascotStyle.HornSpot) -> CGPoint {
        point(spot.x + 0.03, 1 + MascotStyle.hornHeight, spot.z)
    }

    /// Contorno do cubo inteiro: o "fecho convexo" dos 8 vértices projetados.
    var silhouette: [CGPoint] {
        var points: [CGPoint] = []
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] { points.append(point(x, y, z)) } } }
        return Self.convexHull(points)
    }

    /// Leva o "papel" da cara para a face da frente girada. Sem perspectiva, um plano
    /// girado é só uma transformação afim (escala, giro e cisalhamento).
    var frontTransform: CGAffineTransform {
        let topLeft = point(-1, 1, 1), topRight = point(1, 1, 1), bottomLeft = point(-1, -1, 1)
        let paper = Geometry.facePaper
        let onFace = CGAffineTransform(
            a: (topRight.x - topLeft.x) / paper.width, b: (topRight.y - topLeft.y) / paper.width,
            c: (bottomLeft.x - topLeft.x) / paper.height, d: (bottomLeft.y - topLeft.y) / paper.height,
            tx: topLeft.x, ty: topLeft.y
        )
        return CGAffineTransform(translationX: -paper.minX, y: -paper.minY).concatenating(onFace)
    }

    /// Quanto a face da frente encolheu com o giro: afina o traço da cara na mesma medida.
    var frontScale: CGFloat {
        let t = frontTransform
        return sqrt(abs(t.a * t.d - t.b * t.c))
    }

    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }
}

// MARK: - Geometria e cores

private enum Geometry {
    /// O "papel" onde a cara é desenhada, em coordenadas da grade.
    static let facePaper = CGRect(x: 28, y: 30, width: 62, height: 60)
    /// Grossura dos olhos e da boca: grossos como os vazados da logo, para ler no tamanho pequeno.
    static let featureWidth = MascotStyle.featureWidth

    static func round(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

/// Cores do cone do chifre: lado na sombra, meio, lado na luz e o brilho.
private struct HornColors {
    let shadow: Color
    let mid: Color
    let lit: Color
    let highlight: Color
    /// Opacidade da sombra que o chifre faz no topo do cubo.
    let contactShadow: Double
}

private struct Palette {
    /// Cor da face sem luz nenhuma e com luz total; cada face fica entre as duas.
    let shade: (Double, Double, Double)
    let lit: (Double, Double, Double)
    let bevel: Color
    let horn: HornColors
    /// Cor da cara (olhos e boca) e do traço que dá o efeito de entalhe.
    let carve: Color
    let carveRim: Color
    let carveRimOffset: CGFloat

    func color(light: Double) -> Color {
        let t = min(max(light, 0), 1)
        return Color(red: shade.0 + (lit.0 - shade.0) * t,
                     green: shade.1 + (lit.1 - shade.1) * t,
                     blue: shade.2 + (lit.2 - shade.2) * t)
    }

    private static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double(hex >> 16 & 0xFF) / 255, Double(hex >> 8 & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func color(_ hex: UInt32) -> Color {
        let c = rgb(hex)
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    /// Cubo claro com a cara escura (o da logo da esquerda).
    static let light = Palette(
        shade: rgb(0x9EA4AE),
        lit: rgb(0xFFFFFF),
        bevel: .white.opacity(0.9),
        horn: HornColors(shadow: color(0xC4C9D0), mid: color(0xE6E9ED), lit: color(0xF7F8FA),
                         highlight: .white.opacity(0.5), contactShadow: 0.08),
        carve: color(0x16171A),
        carveRim: .white.opacity(0.95),
        carveRimOffset: 1.3
    )

    /// Cubo escuro com a cara clara (o da logo da direita).
    static let dark = Palette(
        shade: rgb(0x111214),
        lit: rgb(0x5C606A),
        bevel: .white.opacity(0.3),
        horn: HornColors(shadow: color(0x1C1E22), mid: color(0x2F3238), lit: color(0x4A4E57),
                         highlight: .white.opacity(0.2), contactShadow: 0.25),
        carve: color(0xEEF0F3),
        carveRim: .black.opacity(0.7),
        carveRimOffset: -1.3
    )
}

/// Forma desenhada na grade 100×100 e escalada para o espaço que a view tiver. Como é
/// vetor, fica nítida em qualquer tamanho (diferente de uma imagem reduzida).
private struct Grid100: Shape {
    let draw: @Sendable (inout Path) -> Void

    init(_ draw: @escaping @Sendable (inout Path) -> Void) { self.draw = draw }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        draw(&path)
        let scale = min(rect.width, rect.height) / 100
        return path.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

extension Path {
    /// Polígono com as quinas arredondadas por arcos (sem contorno, então sem moldura).
    /// Em pontos quase alinhados não há quina: o arco ali "escapa" para longe, então
    /// esses pontos ganham uma linha reta. Lados curtos ganham um arco menor.
    mutating func addRoundedPolygon(_ points: [CGPoint], radius: CGFloat) {
        guard points.count > 2 else { return }
        let first = CGPoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2)
        move(to: first)
        for i in 1...points.count {
            let previous = points[i - 1]
            let corner = points[i % points.count]
            let next = points[(i + 1) % points.count]
            let a = CGPoint(x: corner.x - previous.x, y: corner.y - previous.y)
            let b = CGPoint(x: next.x - corner.x, y: next.y - corner.y)
            let lengths = hypot(a.x, a.y) * hypot(b.x, b.y)
            // Seno do ângulo entre os dois lados: perto de zero = alinhados.
            let sine = lengths > 0 ? abs(a.x * b.y - a.y * b.x) / lengths : 0
            // O arco não pode ser maior que metade do lado mais curto, senão também escapa.
            let fitted = min(radius, min(hypot(a.x, a.y), hypot(b.x, b.y)) / 2)
            if sine < 0.05 || fitted < 0.05 {
                addLine(to: corner)
            } else {
                addArc(tangent1End: corner, tangent2End: next, radius: fitted)
            }
        }
        closeSubpath()
    }
}
