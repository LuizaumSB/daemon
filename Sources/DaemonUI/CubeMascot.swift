import SwiftUI

/// O cubo do Daemon desenhado em código: um cubo 3D de verdade (8 vértices girados e
/// projetados na tela), pintado chapado em três tons (frente, lateral e topo), com a cara
/// mudando conforme o estado. Por ser vetor, fica nítido em qualquer tamanho. Tudo é
/// calculado numa grade de 100×100 e depois escalado.
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

    // Seguir o ponteiro do mouse (quando está pronto ou com resposta nova).
    /// Giro máximo de lado (graus), igual para a esquerda e para a direita: com o ponteiro
    /// bem à esquerda, o cubo fica virado −36°; bem à direita, +36°; perto, no `yaw` de repouso.
    static let followTurn: Double = 36
    /// Quanto o cubo inclina para cima/baixo do ponteiro, no máximo (graus).
    static let followTilt: Double = 9
    /// Quanto a cara se desloca, no máximo, na face (unidades da grade 100×100).
    static let followLook: CGFloat = 5
    /// Distância (pontos de tela) em que o ponteiro já conta como "longe": giro máximo.
    static let followReach: CGFloat = 300

    // Chifres. Posição no topo do cubo (x e z vão de −1 a 1; o cubo tem lado 2).
    static let horns = [HornSpot(x: -0.5, z: 0.15), HornSpot(x: 0.5, z: -0.1)]
    /// Raio da base e altura de cada chifre, na mesma medida do cubo.
    static let hornRadius = 0.15
    static let hornHeight = 0.42

    // Forma.
    /// Arredondamento das bordas do cubo (na grade 100×100).
    static let cornerRadius: CGFloat = 3
    /// Grossura dos olhos e da boca (na grade 100×100).
    static let featureWidth: CGFloat = 6.5
    /// Vão entre as faces (na grade 100×100). É ele que separa os tons, sem contorno.
    static let faceGap: CGFloat = 1.6

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
    /// Para onde a cara olha, em unidades da grade: `look` para os lados (até ±5) e
    /// `lookY` para cima e para baixo (até ±4; positivo é para baixo).
    var look: CGFloat = 0
    var lookY: CGFloat = 0
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
                if !hornsInFront {
                    // Atrás do cubo, só a parte acima da aresta de cima da frente aparece.
                    // Sem isso, girando, a base do chifre escapa pela quina arredondada e
                    // vira uma cunha grudada no canto.
                    horns(cube, palette).mask(Grid100 { $0.addLines(cube.aboveFrontTop); $0.closeSubpath() })
                }
                cubeBody(cube, palette, scale: scale)
                face(cube, palette, scale: scale)
                if hornsInFront { horns(cube, palette) }
            }
            // Uma camada só: uma sombra aplicada de fora contorna o cubo inteiro, em vez
            // de fazer sombra em cada pedaço (embaixo dos olhos, dentro dos vãos).
            .compositingGroup()
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var palette: Palette { dark ? .dark : .light }

    // MARK: - Corpo

    /// Cada face visível num tom chapado (frente, lateral, topo), com um vão apagado em
    /// volta de cada uma: é o vão que separa os tons, como na logo. Depois o conjunto é
    /// recortado pelo contorno do cubo com as quinas arredondadas.
    private func cubeBody(_ cube: Projection, _ p: Palette, scale: CGFloat) -> some View {
        let faces = cube.visibleFaces
        return ZStack {
            ForEach(faces, id: \.self) { face in
                let corners = cube.corners(of: face)
                Grid100 { $0.addLines(corners); $0.closeSubpath() }
                    .fill(p.tone(of: face))
            }
            // `destinationOut` apaga o que está embaixo: o vão é transparente de verdade,
            // então funciona sobre qualquer fundo. Só nas arestas entre duas faces; na borda
            // de fora ele estragaria o arredondamento das quinas.
            let edges = cube.sharedEdges(among: faces)
            Grid100 { path in
                for (a, b) in edges { path.move(to: a); path.addLine(to: b) }
            }
            .stroke(.black, style: StrokeStyle(lineWidth: MascotStyle.faceGap * scale, lineCap: .round))
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .mask(Grid100 { $0.addRoundedPolygon(cube.silhouette, radius: MascotStyle.cornerRadius) })
    }

    /// Cada chifre é um cone: a base é um círculo no topo do cubo (girado, vira uma elipse)
    /// e a ponta fica acima dela. O contorno é o "fecho convexo" da base com a ponta,
    /// pintado chapado na cor da frente.
    private func horns(_ cube: Projection, _ p: Palette) -> some View {
        ZStack {
            ForEach(MascotStyle.horns, id: \.x) { spot in
                let outline = Projection.convexHull(cube.hornBase(spot) + [cube.hornTip(spot)])
                Grid100 { $0.addRoundedPolygon(outline, radius: 0.8) }
                    .fill(p.horn)
            }
        }
    }

    // MARK: - Cara

    /// A cara é desenhada num "papel" 2D e colada na face da frente do cubo com uma
    /// transformação afim, então acompanha qualquer giro. Ela é pintada (não recortada):
    /// o mascote flutua sobre a mesa, e um recorte mostraria o que estivesse atrás.
    @ViewBuilder
    private func face(_ cube: Projection, _ p: Palette, scale: CGFloat) -> some View {
        if cube.visibleFaces.contains(.front) {
            let eyes: FacePoints.Eyes = blinking && mood != .stopped ? .closed : FacePoints.eyes(for: mood)
            FaceShape(points: FacePoints(eyes: eyes, mouth: FacePoints.mouth(for: mood), look: look, lookY: lookY),
                      onFront: cube.frontTransform)
                .stroke(p.carve, style: Geometry.round(Geometry.featureWidth * scale * cube.frontScale))
        }
    }

    /// Olhos e boca de uma cara, no "papel" 2D (antes de colar no cubo).
    static func faceDrawing(for mood: Mood) -> Path {
        FacePoints(eyes: FacePoints.eyes(for: mood), mouth: FacePoints.mouth(for: mood)).path
    }
}

// MARK: - Cara animável

/// Os pontos da cara, sempre com a mesma estrutura: cada olho são dois traços (4 pontos)
/// e a boca é uma curva (3 pontos). Como toda cara tem os mesmos 11 pontos, trocar de
/// humor é só mover pontos: o SwiftUI interpola um no outro (`>` vira `^`, `x` ou bolinha)
/// em vez de trocar o desenho de uma vez.
struct FacePoints: VectorArithmetic {
    /// x e y de cada ponto, em sequência: olho esquerdo, olho direito, boca.
    var values: [CGFloat]

    enum Eyes { case chevron, closed, happy, cross, dot }
    enum Mouth { case flat, small, smile }

    static func eyes(for mood: CubeMascot.Mood) -> Eyes {
        switch mood {
        case .idle, .attention: return .chevron
        case .thinking: return .dot
        case .happy: return .happy
        case .stopped: return .cross
        }
    }

    static func mouth(for mood: CubeMascot.Mood) -> Mouth {
        switch mood {
        case .idle, .attention, .stopped: return .flat
        case .thinking: return .small
        case .happy: return .smile
        }
    }

    init(values: [CGFloat]) { self.values = values }

    init(eyes: Eyes, mouth: Mouth, look: CGFloat = 0, lookY: CGFloat = 0) {
        var points = Self.eye(eyes, left: true) + Self.eye(eyes, left: false)
        switch mouth {
        case .flat: points += [CGPoint(x: 51, y: 73), CGPoint(x: 59, y: 73), CGPoint(x: 67, y: 73)]
        case .small: points += [CGPoint(x: 55, y: 73), CGPoint(x: 59, y: 73), CGPoint(x: 63, y: 73)]
        case .smile: points += [CGPoint(x: 51, y: 70), CGPoint(x: 59, y: 79), CGPoint(x: 67, y: 70)]
        }
        values = points.flatMap { [$0.x + look, $0.y + lookY] }
    }

    /// Os dois traços de um olho. O esquerdo fica em x = 46,5 e o direito em 71,5.
    private static func eye(_ eyes: Eyes, left: Bool) -> [CGPoint] {
        let x: CGFloat = left ? 46.5 : 71.5
        let p = { (dx: CGFloat, y: CGFloat) in CGPoint(x: x + dx, y: y) }
        switch eyes {
        case .chevron:
            // `>` no olho esquerdo e `<` no direito: a ponta aponta para o meio.
            let s: CGFloat = left ? 1 : -1
            return [p(-4.5 * s, 48), p(4.5 * s, 54), p(4.5 * s, 54), p(-4.5 * s, 60)]
        case .closed: return [p(-4.5, 55), p(0, 55), p(0, 55), p(4.5, 55)]
        case .happy: return [p(-4.5, 57), p(0, 51), p(0, 51), p(4.5, 57)]
        case .cross: return [p(-3.5, 50.5), p(3.5, 57.5), p(3.5, 50.5), p(-3.5, 57.5)]
        // Um "+" curtinho: com a ponta redonda, vira uma bolinha um pouco maior que o traço.
        case .dot: return [p(-0.8, 55), p(0.8, 55), p(0, 54.2), p(0, 55.8)]
        }
    }

    var path: Path {
        let p = stride(from: 0, to: values.count, by: 2).map { CGPoint(x: values[$0], y: values[$0 + 1]) }
        var path = Path()
        for eye in [0, 4] {
            path.move(to: p[eye]); path.addLine(to: p[eye + 1])
            path.move(to: p[eye + 2]); path.addLine(to: p[eye + 3])
        }
        path.move(to: p[8])
        path.addQuadCurve(to: p[10], control: p[9])
        return path
    }

    // O que o SwiftUI precisa para interpolar: somar, subtrair e escalar os pontos.
    static var zero: FacePoints { FacePoints(values: Array(repeating: 0, count: 22)) }
    static func + (a: FacePoints, b: FacePoints) -> FacePoints { FacePoints(values: zip(a.values, b.values).map(+)) }
    static func - (a: FacePoints, b: FacePoints) -> FacePoints { FacePoints(values: zip(a.values, b.values).map(-)) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * CGFloat(rhs) } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + Double($1 * $1) } }
}

/// A cara como `Shape` animável: o `animatableData` são os pontos, então uma troca de
/// humor dentro de uma animação vira um morph.
private struct FaceShape: Shape {
    var points: FacePoints
    let onFront: CGAffineTransform

    var animatableData: FacePoints {
        get { points }
        set { points = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        return points.path.applying(onFront
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
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
    /// Onde a origem do cubo cai na grade. Calculado para o desenho inteiro (cubo + ponta
    /// dos chifres) ficar no meio, em qualquer ângulo: ícone, mascote e menu bar centrados.
    private var center = CGPoint.zero
    private let size: Double = 25

    init(yaw: Double, pitch: Double, roll: Double) {
        self.init(yaw: yaw, pitch: pitch, roll: roll, center: Self.restCenter)
    }

    private init(yaw: Double, pitch: Double, roll: Double, center: CGPoint) {
        self.yaw = yaw * .pi / 180
        self.pitch = pitch * .pi / 180
        self.roll = roll * .pi / 180
        self.center = center
    }

    /// Onde fica o centro do cubo na grade: calculado uma vez, na pose de repouso, pela caixa
    /// em volta do cubo e das pontas dos chifres. Usar sempre o mesmo centro faz o cubo girar
    /// no lugar quando segue o mouse. Recalculando a cada ângulo, a caixa muda de forma e o
    /// cubo "escorregaria" para os lados.
    private static let restCenter: CGPoint = {
        let rest = Projection(yaw: MascotStyle.yaw, pitch: MascotStyle.pitch, roll: MascotStyle.tilt, center: .zero)
        var points = MascotStyle.horns.map { rest.hornTip($0) }
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] { points.append(rest.point(x, y, z)) } } }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGPoint(x: 50 - (xs.min()! + xs.max()!) / 2, y: 50 - (ys.min()! + ys.max()!) / 2)
    }()

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

    /// Região da tela acima da reta da aresta de cima da frente (estendida até as bordas).
    var aboveFrontTop: [CGPoint] {
        let a = point(-1, 1, 1), b = point(1, 1, 1)
        let slope = (b.y - a.y) / (b.x - a.x)
        let y = { (x: CGFloat) in a.y + slope * (x - a.x) }
        return [CGPoint(x: -100, y: y(-100)), CGPoint(x: 200, y: y(200)), CGPoint(x: 200, y: -100), CGPoint(x: -100, y: -100)]
    }

    /// Arestas que duas faces visíveis dividem (na tela): onde entra o vão entre os tons.
    func sharedEdges(among faces: [Face]) -> [(CGPoint, CGPoint)] {
        var edges: [(CGPoint, CGPoint)] = []
        for (i, a) in faces.enumerated() {
            for b in faces[(i + 1)...] {
                let other = corners(of: b)
                let shared = corners(of: a).filter { p in other.contains { hypot(p.x - $0.x, p.y - $0.y) < 0.01 } }
                if shared.count == 2 { edges.append((shared[0], shared[1])) }
            }
        }
        return edges
    }

    /// Contorno do cubo inteiro: o "fecho convexo" dos 8 vértices projetados.
    var silhouette: [CGPoint] {
        var points: [CGPoint] = []
        for x in [-1.0, 1.0] { for y in [-1.0, 1.0] { for z in [-1.0, 1.0] { points.append(point(x, y, z)) } } }
        // Vértices quase colados (a quina de trás aparecendo por um fio) deixariam um lado
        // curtinho, e o arredondamento viraria um chanfro: fica só um deles.
        var outline: [CGPoint] = []
        for p in Self.convexHull(points) where outline.last.map({ hypot(p.x - $0.x, p.y - $0.y) > 3 }) ?? true {
            outline.append(p)
        }
        if outline.count > 3, let first = outline.first, let last = outline.last, hypot(first.x - last.x, first.y - last.y) <= 3 {
            outline.removeLast()
        }
        return outline
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

private struct Palette {
    let front: Color
    let side: Color
    let top: Color
    let horn: Color
    /// Cor da cara: a do fundo onde esse cubo costuma estar, para parecer vazada.
    let carve: Color

    func tone(of face: Projection.Face) -> Color {
        switch face {
        case .front: return front
        case .top: return top
        default: return side
        }
    }

    private static func color(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Cubo claro com a cara escura (para fundo escuro).
    static let light = Palette(front: color(0xF2F2F4), side: color(0x9A9EA7), top: color(0xC9CCD2),
                               horn: color(0xF2F2F4), carve: color(0x1B1D22))

    /// Cubo escuro com a cara clara (para fundo claro).
    static let dark = Palette(front: color(0x16171B), side: color(0x5D5F66), top: color(0xA7A9AE),
                              horn: color(0x16171B), carve: color(0xF7F6F2))
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
