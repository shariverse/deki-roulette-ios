// アプリアイコンを描き、Icon Composer の .icon（icon.json と Assets/ のレイヤー画像）に組み立てる。
// 背景は icon.json の fill に置き、前景はレイヤーに分けて groups に入れる（iOS 26 以降は group ごとに Liquid Glass の
// 奥行きが付き、それより前は Xcode が書き出す平面の画像になる）。既定のアイコン（AppIcon）の絵柄は Web 版 og.png と同じく、
// 盤面だけの中立な絵。
// 使い方:
//   swift scripts/make-icon.swift <出力先のディレクトリ>
//     アプリに入れるアイコンを書き出す。例: swift scripts/make-icon.swift DekiRoulette/Resources → DekiRoulette/Resources/AppIcon.icon を作り直す
//   swift scripts/make-icon.swift --candidates <出力先のディレクトリ>
//     アイコンの案を <番号>-<名前>.icon で書き出す（00 が今の既定のアイコン、01〜 が案）。出力先は空のディレクトリ（無ければ作る）。
//     案はアプリに入れないので、DekiRoulette/ の下には書き出さない。一覧の画像は scripts/preview-icons.swift で作る
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - .icon の組み立て（案に依らない部分）

/// レイヤーの画像の一辺（Icon Composer の iOS の画面と同じ 1024pt を 1 倍で描く）。角丸・影・余白は描かない（OS がマスクする）
let canvas = 1024.0

/// 1 枚のレイヤー。背景は透明で、正方形の全面を使って描く。`glass` を false にすると、そのレイヤーだけ Liquid Glass の質感を付けない
struct IconLayer {
    let name: String
    var glass = true
    let draw: (CGContext) -> Void
}

/// group の影。既定は Icon Composer と同じ neutral の 0.5
enum IconShadow: Equatable {
    case neutral(Double)
    case layerColor(Double)
    case none
}

/// Liquid Glass の 1 枚の板。`layers` は手前から並べる。
/// `translucency` は板の透け具合（0〜1）。nil なら透かさない（既定。透かすと背景の色が混ざって絵の色がくすむ）。
/// `specular` は板の縁の光
struct IconGroup {
    var translucency: Double? = nil
    var specular = true
    var shadow = IconShadow.neutral(0.5)
    let layers: [IconLayer]
}

/// 背景（icon.json の fill）。グラデーションは上から下へ。`automatic` は 1 色から Icon Composer が自動で付けるグラデーション
enum IconFill {
    case solid(UInt32)
    case gradient(top: UInt32, bottom: UInt32)
    case automatic(UInt32)
}

/// 1 つのアイコン。`groups` は手前から並べる（icon.json の順と同じ）。外観ごとの値は持たない（ダーク・色付き・クリアは自動に任せる）
struct IconDesign {
    let name: String
    let fill: IconFill
    let groups: [IconGroup]
}

func cg(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// icon.json の色の書き方（`srgb:r,g,b,a`）
func iconColor(_ hex: UInt32) -> String {
    let parts = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { String(format: "%.5f", Double($0) / 255) }
    return "srgb:" + (parts + ["1.00000"]).joined(separator: ",")
}

func fillJSON(_ fill: IconFill) -> [String: Any] {
    switch fill {
    case .solid(let color):
        return ["solid": iconColor(color)]
    case .gradient(let top, let bottom):
        // orientation の y は 0 が上
        return ["linear-gradient": [iconColor(top), iconColor(bottom)],
                "orientation": ["start": ["x": 0.5, "y": 0], "stop": ["x": 0.5, "y": 1]]]
    case .automatic(let color):
        return ["automatic-gradient": iconColor(color)]
    }
}

func groupJSON(_ group: IconGroup, layers: [[String: Any]]) -> [String: Any] {
    var json: [String: Any] = [
        "layers": layers,
        // value は enabled が false のときも書く（無いと ictool が読めない）
        "translucency": ["enabled": group.translucency != nil, "value": group.translucency ?? 0.5],
    ]
    // 既定と同じ値は書かない（Icon Composer で開いたときに既定のままに見えるように）
    if !group.specular { json["specular"] = false }
    switch group.shadow {
    case .neutral(let opacity) where opacity != 0.5: json["shadow"] = ["kind": "neutral", "opacity": opacity]
    case .layerColor(let opacity): json["shadow"] = ["kind": "layer-color", "opacity": opacity]
    case .none: json["shadow"] = ["kind": "none", "opacity": 0.5]
    default: break
    }
    return json
}

func render(_ layer: IconLayer) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    layer.draw(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG を書き出せません: \(url.path)") }
}

/// `<directory>/<packageName>.icon` を作り直す（前のレイヤー画像が残らないよう、いったん消してから書く）
func writeIcon(_ design: IconDesign, into directory: URL, packageName: String? = nil) throws {
    // レイヤーの名前は PNG のファイル名になるので、重なると先に書いた画像が上書きされる
    let names = design.groups.flatMap { $0.layers.map(\.name) }
    precondition(Set(names).count == names.count, "\(design.name) のレイヤーの名前が重なっています: \(names)")

    let fm = FileManager.default
    let package = directory.appendingPathComponent("\(packageName ?? design.name).icon")
    let assets = package.appendingPathComponent("Assets")
    if fm.fileExists(atPath: package.path) { try fm.removeItem(at: package) }
    // 出力先そのものは作らない（打ち間違えたパスに .icon を作らないように）
    try fm.createDirectory(at: package, withIntermediateDirectories: false)
    try fm.createDirectory(at: assets, withIntermediateDirectories: false)

    var groups: [[String: Any]] = []
    for group in design.groups {
        var layers: [[String: Any]] = []
        for layer in group.layers {
            let file = "\(layer.name).png"
            writePNG(render(layer), to: assets.appendingPathComponent(file))
            var json: [String: Any] = ["image-name": file, "name": layer.name]
            if !layer.glass { json["glass"] = false }
            layers.append(json)
        }
        groups.append(groupJSON(group, layers: layers))
    }
    let json: [String: Any] = [
        "fill": fillJSON(design.fill),
        "groups": groups,
        "supported-platforms": ["squares": "shared"],
    ]
    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try (data + Data("\n".utf8)).write(to: package.appendingPathComponent("icon.json"))
    print("wrote \(package.path)")
}

// MARK: - 既定のアイコン（AppIcon）

// 色・形・比率は PNG 1 枚で描いていたときと同じ。CG は y 軸が上向きなので、針のある 12 時は y の大きい側
let center = CGPoint(x: canvas / 2, y: canvas / 2)
let wheelRadius = canvas * 0.38
let wheelColors: [UInt32] = [0xFF8080, 0xFFA366, 0xF2CE5C, 0xA3DB6B, 0x5FD6A8, 0x5CC9E0, 0x7BAEF5, 0xA48CF0, 0xCE8CEE, 0xFF85C0]
let wheelSlice = .pi * 2 / Double(wheelColors.count)

func fillCircle(_ ctx: CGContext, radius: Double, color: UInt32) {
    ctx.setFillColor(cg(color))
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()
}

let appIcon = IconDesign(name: "AppIcon", fill: .solid(0x17111F), groups: [
    // 針
    IconGroup(layers: [IconLayer(name: "needle") { ctx in
        ctx.setFillColor(cg(0xFF4E63))
        let tipY = center.y + wheelRadius - 40
        ctx.move(to: CGPoint(x: center.x, y: tipY))
        ctx.addLine(to: CGPoint(x: center.x - 36, y: tipY + 90))
        ctx.addLine(to: CGPoint(x: center.x + 36, y: tipY + 90))
        ctx.closePath()
        ctx.fillPath()
    }]),
    // ハブ
    IconGroup(layers: [IconLayer(name: "hub") { ctx in
        fillCircle(ctx, radius: 62, color: 0x1F1829)
        ctx.setStrokeColor(cg(0xF5EFE6))
        ctx.setLineWidth(8)
        ctx.addArc(center: center, radius: 62, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
        fillCircle(ctx, radius: 20, color: 0xF5EFE6)
    }]),
    // スライスと区切り線（区切り線は背景と同じ色）
    IconGroup(layers: [
        IconLayer(name: "dividers") { ctx in
            ctx.setStrokeColor(cg(0x17111F))
            ctx.setLineWidth(6)
            for i in 0..<wheelColors.count {
                let a = .pi / 2 - Double(i) * wheelSlice
                ctx.move(to: center)
                ctx.addLine(to: CGPoint(x: center.x + cos(a) * wheelRadius, y: center.y + sin(a) * wheelRadius))
                ctx.strokePath()
            }
        },
        IconLayer(name: "slices") { ctx in
            for (i, hex) in wheelColors.enumerated() {
                // 12 時から時計回りに並べる。CG は y 軸上向きなので角度を反転する
                let start = .pi / 2 - Double(i) * wheelSlice
                ctx.move(to: center)
                ctx.addArc(center: center, radius: wheelRadius, startAngle: start, endAngle: start - wheelSlice, clockwise: true)
                ctx.closePath()
                ctx.setFillColor(cg(hex))
                ctx.fillPath()
            }
        },
    ]),
    // 盤面の外周
    IconGroup(layers: [IconLayer(name: "rim") { ctx in
        fillCircle(ctx, radius: wheelRadius + 34, color: 0x2A2138)
    }]),
])

/// アプリに入れるアイコン（`swift scripts/make-icon.swift <出力先>` で書き出す）
let appIcons = [appIcon]

// MARK: - 図形の道具（案で使う）
// 角度は 12 時を 0 度として時計回りに測る（盤面と同じ）。座標は CG のまま y が上向き

func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// c から半径 r、角度 deg（12 時から時計回り）の点
func polar(_ c: CGPoint, _ r: Double, _ deg: Double) -> CGPoint {
    let t = deg * .pi / 180
    return P(c.x + r * sin(t), c.y + r * cos(t))
}

/// 時計回りの角度を CG の角度（3 時から反時計回りのラジアン）にする
func cgAngle(_ deg: Double) -> Double { .pi / 2 - deg * .pi / 180 }

func circle(_ c: CGPoint, _ r: Double) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
}

func ellipse(_ c: CGPoint, _ w: Double, _ h: Double) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), transform: nil)
}

/// c を中心にした幅 w・高さ h の四角（角の丸み radius）
func box(_ c: CGPoint, _ w: Double, _ h: Double, radius: Double = 0) -> CGPath {
    let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    return radius > 0 ? CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil) : CGPath(rect: rect, transform: nil)
}

func poly(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

func line(_ a: CGPoint, _ b: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.move(to: a)
    path.addLine(to: b)
    return path
}

/// 折れ線（閉じない）
func polyline(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    return path
}

/// 正多角形。最初の頂点は rotation 度の向き
func regular(_ c: CGPoint, _ r: Double, sides: Int, rotation: Double = 0) -> CGPath {
    poly((0..<sides).map { polar(c, r, rotation + Double($0) * 360 / Double(sides)) })
}

func star(_ c: CGPoint, outer: Double, inner: Double, points: Int = 5, rotation: Double = 0) -> CGPath {
    poly((0..<points * 2).map { polar(c, $0 % 2 == 0 ? outer : inner, rotation + Double($0) * 180 / Double(points)) })
}

/// 扇形。inner を付けると環の一部になる。from から to へ時計回り
func sector(_ c: CGPoint, _ r: Double, inner: Double = 0, from: Double, to: Double) -> CGPath {
    let path = CGMutablePath()
    if inner > 0 {
        path.move(to: polar(c, inner, from))
    } else {
        path.move(to: c)
    }
    path.addArc(center: c, radius: r, startAngle: cgAngle(from), endAngle: cgAngle(to), clockwise: true)
    if inner > 0 {
        path.addArc(center: c, radius: inner, startAngle: cgAngle(to), endAngle: cgAngle(from), clockwise: false)
    }
    path.closeSubpath()
    return path
}

/// 円弧（閉じない）。from から to へ時計回り
func arc(_ c: CGPoint, _ r: Double, from: Double, to: Double) -> CGPath {
    let path = CGMutablePath()
    path.addArc(center: c, radius: r, startAngle: cgAngle(from), endAngle: cgAngle(to), clockwise: true)
    return path
}

/// 半径 outer と inner の間の環
func ring(_ c: CGPoint, outer: Double, inner: Double) -> CGPath {
    let path = CGMutablePath()
    path.addPath(circle(c, outer))
    path.addPath(circle(c, inner))
    return path
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: UInt32, alpha: Double = 1, evenOdd: Bool = false) {
    ctx.addPath(path)
    ctx.setFillColor(cg(color, alpha))
    ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
}

/// path の範囲で上から下へのグラデーションを塗る
func fillGradient(_ ctx: CGContext, _ path: CGPath, top: UInt32, bottom: UInt32, evenOdd: Bool = false) {
    let bounds = path.boundingBoxOfPath
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [cg(top), cg(bottom)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(path)
    if evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
    ctx.drawLinearGradient(gradient, start: P(bounds.midX, bounds.maxY), end: P(bounds.midX, bounds.minY), options: [])
    ctx.restoreGState()
}

/// path の範囲で、focus から外へ広がるグラデーションを塗る（球の光り方）
func fillRadial(_ ctx: CGContext, _ path: CGPath, inner: UInt32, outer: UInt32, focus: CGPoint, radius: Double) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [cg(inner), cg(outer)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawRadialGradient(gradient, startCenter: focus, startRadius: 0, endCenter: focus, endRadius: radius, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
}

func stroke(_ ctx: CGContext, _ path: CGPath, _ color: UInt32, width: Double, alpha: Double = 1, cap: CGLineCap = .round, join: CGLineJoin = .round) {
    ctx.addPath(path)
    ctx.setStrokeColor(cg(color, alpha))
    ctx.setLineWidth(width)
    ctx.setLineCap(cap)
    ctx.setLineJoin(join)
    ctx.strokePath()
}

/// path の範囲を透明に抜く（同じレイヤーに描いたものだけが抜ける）
func clear(_ ctx: CGContext, _ path: CGPath) {
    ctx.saveGState()
    ctx.setBlendMode(.clear)
    fill(ctx, path, 0x000000)
    ctx.restoreGState()
}

/// path の内側だけに描く
func clipped(_ ctx: CGContext, _ path: CGPath, _ body: () -> Void) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    body()
    ctx.restoreGState()
}

/// c を中心に時計回りに deg 度回した座標系で描く
func rotated(_ ctx: CGContext, around c: CGPoint, _ deg: Double, _ body: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: -deg * .pi / 180)
    ctx.translateBy(x: -c.x, y: -c.y)
    body()
    ctx.restoreGState()
}

/// フォントが無い Mac で黙って別のフォントにならないよう、見つからなければ止める
func font(_ name: String, _ size: Double) -> CTFont {
    let font = CTFontCreateWithName(name as CFString, size, nil)
    guard CTFontCopyPostScriptName(font) as String == name else { fatalError("フォントがありません: \(name)") }
    return font
}

/// 文字の見た目の範囲（グリフの外形）の中心を c に合わせて描く。rotation は時計回り
func text(_ ctx: CGContext, _ string: String, font name: String, size: Double, color: UInt32, at c: CGPoint, rotation: Double = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font(name, size),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): cg(color),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    rotated(ctx, around: c, rotation) {
        ctx.textPosition = .zero
        let bounds = CTLineGetImageBounds(line, ctx)
        ctx.textPosition = P(c.x - bounds.midX, c.y - bounds.midY)
        CTLineDraw(line, ctx)
    }
}

/// 色相・彩度・明度（0〜1）から色を作る
func hsb(_ h: Double, _ s: Double, _ v: Double) -> UInt32 {
    let h6 = (h - floor(h)) * 6
    let f = h6 - floor(h6)
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    let rgb: [(Double, Double, Double)] = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]
    let (r, g, b) = rgb[Int(h6) % 6]
    return UInt32((r * 255).rounded()) << 16 | UInt32((g * 255).rounded()) << 8 | UInt32((b * 255).rounded())
}

/// サイコロの目の位置（一辺 1 の面の中心からの割合）
func pipPositions(_ count: Int) -> [(Double, Double)] {
    let a = 0.27
    switch count {
    case 1: return [(0, 0)]
    case 2: return [(-a, a), (a, -a)]
    case 3: return [(-a, a), (0, 0), (a, -a)]
    case 4: return [(-a, a), (a, a), (-a, -a), (a, -a)]
    case 5: return [(-a, a), (a, a), (-a, -a), (a, -a), (0, 0)]
    default: return [(-a, a), (a, a), (-a, 0), (a, 0), (-a, -a), (a, -a)]
    }
}

/// 正面を向いたサイコロの面（c を中心に時計回りに angle 度傾ける）
func dieBody(_ ctx: CGContext, _ c: CGPoint, size: Double, angle: Double, color: UInt32) {
    rotated(ctx, around: c, angle) { fill(ctx, box(c, size, size, radius: size * 0.2), color) }
}

func diePips(_ ctx: CGContext, _ c: CGPoint, size: Double, angle: Double, count: Int, color: (Int) -> UInt32) {
    rotated(ctx, around: c, angle) {
        for (i, (u, v)) in pipPositions(count).enumerated() {
            fill(ctx, circle(P(c.x + u * size, c.y + v * size), size * 0.085), color(i))
        }
    }
}

/// 平行四辺形の面（origin から e1・e2 に張る）に、一辺 1 の正方形の座標で描いた円を写す（立体のサイコロの目）
func facePip(_ origin: CGPoint, _ e1: CGPoint, _ e2: CGPoint, u: Double, v: Double, r: Double) -> CGPath {
    var transform = CGAffineTransform(a: e1.x, b: e1.y, c: e2.x, d: e2.y, tx: origin.x, ty: origin.y)
    return CGPath(ellipseIn: CGRect(x: u - r, y: v - r, width: r * 2, height: r * 2), transform: &transform)
}

func + (a: CGPoint, b: CGPoint) -> CGPoint { P(a.x + b.x, a.y + b.y) }

/// ネオン管のように、太く薄い線を重ねてから細い線を引く
func neon(_ ctx: CGContext, _ path: CGPath, _ color: UInt32, width: Double) {
    stroke(ctx, path, color, width: width * 4, alpha: 0.15)
    stroke(ctx, path, color, width: width * 2.2, alpha: 0.3)
    stroke(ctx, path, color, width: width)
}

/// 両脇に切り欠きのある券（c を中心に時計回りに angle 度傾ける）
func ticket(_ ctx: CGContext, _ c: CGPoint, angle: Double, color: UInt32, perforation: UInt32, mark: UInt32) {
    rotated(ctx, around: c, angle) {
        fill(ctx, box(c, 600, 300, radius: 40), color)
        for k in 0..<9 {
            fill(ctx, circle(P(c.x + 110, c.y - 120 + Double(k) * 30), 7), perforation)
        }
        fill(ctx, star(P(c.x - 95, c.y), outer: 100, inner: 42), mark)
        fill(ctx, circle(P(c.x + 205, c.y), 36), mark)
        clear(ctx, circle(P(c.x - 300, c.y), 50))
        clear(ctx, circle(P(c.x + 300, c.y), 50))
    }
}

/// カプセルの半分（top なら上半分）。c を中心に時計回りに angle 度傾ける
func capsuleHalf(_ ctx: CGContext, _ c: CGPoint, _ r: Double, angle: Double, top: Bool, color: UInt32) {
    rotated(ctx, around: c, angle) {
        fill(ctx, top ? sector(c, r, from: -90, to: 90) : sector(c, r, from: 90, to: 270), color)
    }
}

/// カプセルの継ぎ目の帯
func capsuleSeam(_ ctx: CGContext, _ c: CGPoint, _ r: Double, angle: Double) {
    rotated(ctx, around: c, angle) {
        clipped(ctx, circle(c, r)) { fill(ctx, box(c, r * 2, r * 0.11), 0xD9DCE6) }
    }
}

/// 扇に開いたトランプの 1 枚。pivot を中心に時計回りに angle 度回す
func fanCard(_ ctx: CGContext, angle: Double, suit: String, color: UInt32) {
    let pivot = P(512, 150)
    let c = P(512, 500)
    rotated(ctx, around: pivot, angle) {
        fill(ctx, box(c, 300, 420, radius: 34), 0xFFFFFF)
        stroke(ctx, box(c, 300, 420, radius: 34), 0xD9D9D9, width: 4)
        text(ctx, suit, font: "HiraginoSans-W6", size: 200, color: color, at: c)
    }
}

// MARK: - 案（--candidates で書き出す。採用が決まったら、採用した案だけを残す）
// 番号は配列の順（01〜）。名前は採用したときに代替アイコンの名前（AppIcon-<名前>）にする前提の英語

let candidates: [IconDesign] = [
    // 01 ルーレット盤: ネオン
    IconDesign(name: "Neon", fill: .solid(0x0B0614), groups: [
        IconGroup(layers: [IconLayer(name: "needle") { ctx in
            let needle = poly([P(512, 790), P(464, 920), P(560, 920)])
            neon(ctx, needle, 0xFF3EA5, width: 10)
            fill(ctx, needle, 0xFF3EA5)
        }]),
        IconGroup(layers: [IconLayer(name: "hub") { ctx in
            neon(ctx, circle(center, 46), 0x3EF0FF, width: 12)
            fill(ctx, circle(center, 16), 0xFFFFFF)
        }]),
        IconGroup(layers: [IconLayer(name: "slices") { ctx in
            let colors: [UInt32] = [0x3EF0FF, 0xFF3EA5, 0xFFE53E, 0x7CFF4F]
            for i in 0..<8 {
                let a = Double(i) * 45
                let slice = sector(center, 330, inner: 90, from: a + 4, to: a + 41)
                fill(ctx, slice, colors[i % 4], alpha: 0.12)
                neon(ctx, slice, colors[i % 4], width: 9)
            }
        }]),
        IconGroup(layers: [IconLayer(name: "rim") { ctx in
            neon(ctx, circle(center, 392), 0xB46BFF, width: 14)
        }]),
    ]),
    // 02 ルーレット盤: パステル
    IconDesign(name: "Pastel", fill: .solid(0xFFF4E8), groups: [
        IconGroup(layers: [IconLayer(name: "pin") { ctx in
            fill(ctx, circle(P(512, 900), 50), 0xFF6F7D)
            fill(ctx, poly([P(468, 880), P(556, 880), P(512, 790)]), 0xFF6F7D)
            fill(ctx, circle(P(512, 900), 18), 0xFFFFFF)
        }]),
        IconGroup(layers: [IconLayer(name: "hub") { ctx in
            fill(ctx, circle(center, 74), 0xFFFFFF)
            fill(ctx, circle(center, 28), 0xFF9AA2)
        }]),
        IconGroup(layers: [
            IconLayer(name: "dividers") { ctx in
                for i in 0..<8 { stroke(ctx, line(center, polar(center, 370, Double(i) * 45)), 0xFFFFFF, width: 12) }
            },
            IconLayer(name: "slices") { ctx in
                let colors: [UInt32] = [0xFFADBE, 0xFFCF9E, 0xF9F19A, 0xBDF5B0, 0x93EDF8, 0x9DBDFC, 0xB9AAFB, 0xF8B8F6]
                for i in 0..<8 { fill(ctx, sector(center, 370, from: Double(i) * 45, to: Double(i + 1) * 45), colors[i]) }
            },
        ]),
        IconGroup(layers: [IconLayer(name: "rim") { ctx in
            fill(ctx, circle(center, 410), 0xFFFFFF)
            stroke(ctx, circle(center, 410), 0xF3D3BA, width: 12)
        }]),
    ]),
    // 03 ルーレット盤: カジノ
    IconDesign(name: "Casino", fill: .gradient(top: 0x1E7A46, bottom: 0x0B3D22), groups: [
        IconGroup(layers: [IconLayer(name: "ball") { ctx in
            let c = polar(center, 305, 0)
            fillRadial(ctx, circle(c, 24), inner: 0xFFFFFF, outer: 0xBDBDBD, focus: P(c.x - 8, c.y + 8), radius: 34)
        }]),
        IconGroup(layers: [IconLayer(name: "turret") { ctx in
            for k in 0..<4 {
                let a = 45 + Double(k) * 90
                stroke(ctx, line(center, polar(center, 190, a)), 0xD4A13A, width: 26)
                fill(ctx, circle(polar(center, 190, a), 22), 0xF6D27A)
            }
            fillGradient(ctx, circle(center, 95), top: 0xF8DE8A, bottom: 0xB8862B)
            fill(ctx, circle(center, 30), 0xF8DE8A)
        }]),
        IconGroup(layers: [
            IconLayer(name: "frets") { ctx in
                for i in 0..<18 {
                    let a = Double(i) * 20 - 10
                    stroke(ctx, line(polar(center, 250, a), polar(center, 360, a)), 0xE8B04A, width: 5)
                }
                stroke(ctx, circle(center, 360), 0xE8B04A, width: 8)
                stroke(ctx, circle(center, 250), 0xE8B04A, width: 8)
            },
            IconLayer(name: "pockets") { ctx in
                fillGradient(ctx, circle(center, 250), top: 0x7A4524, bottom: 0x4A2511)
                for i in 0..<18 {
                    let color: UInt32 = i == 0 ? 0x0F9D58 : (i % 2 == 1 ? 0xD7263D : 0x161616)
                    fill(ctx, sector(center, 360, inner: 250, from: Double(i) * 20 - 10, to: Double(i) * 20 + 10), color)
                }
            },
        ]),
        IconGroup(layers: [IconLayer(name: "rim") { ctx in
            fillGradient(ctx, circle(center, 420), top: 0x8B4A23, bottom: 0x4A2511)
            fill(ctx, circle(center, 372), 0x2B1408)
        }]),
    ]),
    // 04 ルーレット盤: ボードゲームのスピナー
    IconDesign(name: "Spinner", fill: .solid(0xFDF6E3), groups: [
        IconGroup(layers: [IconLayer(name: "cap") { ctx in
            fill(ctx, circle(center, 54), 0xFFFFFF)
            stroke(ctx, circle(center, 54), 0x073B4C, width: 14)
            fill(ctx, circle(center, 16), 0x073B4C)
        }]),
        IconGroup(layers: [IconLayer(name: "arrow") { ctx in
            rotated(ctx, around: center, 40) {
                fill(ctx, poly([P(486, 392), P(538, 392), P(538, 712), P(596, 712), P(512, 842), P(428, 712), P(486, 712)]), 0x073B4C)
                fill(ctx, circle(P(512, 392), 26), 0x073B4C)
            }
        }]),
        IconGroup(layers: [
            IconLayer(name: "dividers") { ctx in
                for i in 0..<4 { stroke(ctx, line(center, polar(center, 376, Double(i) * 90)), 0xFFFFFF, width: 16) }
            },
            IconLayer(name: "quarters") { ctx in
                let colors: [UInt32] = [0xEF476F, 0xFFD166, 0x06D6A0, 0x118AB2]
                for i in 0..<4 { fill(ctx, sector(center, 376, from: Double(i) * 90, to: Double(i + 1) * 90), colors[i]) }
            },
        ]),
        IconGroup(layers: [IconLayer(name: "base") { ctx in
            fill(ctx, circle(center, 400), 0xFFFFFF)
            stroke(ctx, circle(center, 400), 0x073B4C, width: 16)
        }]),
    ]),
    // 05 ルーレット盤: 大きな盤の上半分
    IconDesign(name: "BigWheel", fill: .gradient(top: 0x1B1464, bottom: 0x5F27CD), groups: [
        IconGroup(layers: [IconLayer(name: "pointer") { ctx in
            let pointer = poly([P(452, 880), P(572, 880), P(512, 660)])
            stroke(ctx, pointer, 0xFFFFFF, width: 28)
            fill(ctx, pointer, 0xFFFFFF)
            fill(ctx, circle(P(512, 830), 22), 0xFF3D68)
        }]),
        IconGroup(layers: [IconLayer(name: "hub") { ctx in
            let c = P(512, 60)
            fill(ctx, circle(c, 120), 0xFFFFFF)
            fill(ctx, circle(c, 66), 0xFF3D68)
        }]),
        IconGroup(layers: [
            IconLayer(name: "dividers") { ctx in
                let c = P(512, 60)
                for i in 0..<20 { stroke(ctx, line(c, polar(c, 640, Double(i) * 18 - 9)), 0xFFFFFF, width: 8) }
            },
            IconLayer(name: "slices") { ctx in
                let c = P(512, 60)
                let colors: [UInt32] = [0xFF6B6B, 0xFFD93D, 0x6BCB77, 0x4D96FF]
                for i in 0..<20 { fill(ctx, sector(c, 640, from: Double(i) * 18 - 9, to: Double(i) * 18 + 9), colors[i % 4]) }
            },
        ]),
        IconGroup(layers: [
            IconLayer(name: "bulbs") { ctx in
                let c = P(512, 60)
                for i in 0..<36 { fill(ctx, circle(polar(c, 665, Double(i) * 10 + 5), 11), 0xFFF6D5) }
            },
            IconLayer(name: "rim") { ctx in
                fill(ctx, circle(P(512, 60), 690), 0xFFC93C)
            },
        ]),
    ]),
    // 06 抽象図形: 回る弧
    IconDesign(name: "Arcs", fill: .gradient(top: 0x1A1446, bottom: 0x3A2C8C), groups: [
        IconGroup(layers: [IconLayer(name: "dot") { ctx in fill(ctx, circle(center, 50), 0xFFFFFF) }]),
        IconGroup(layers: [IconLayer(name: "inner") { ctx in stroke(ctx, arc(center, 150, from: 110, to: 380), 0x4ECDC4, width: 80) }]),
        IconGroup(layers: [IconLayer(name: "middle") { ctx in stroke(ctx, arc(center, 260, from: 20, to: 290), 0xFFC857, width: 80) }]),
        IconGroup(layers: [IconLayer(name: "outer") { ctx in stroke(ctx, arc(center, 370, from: 200, to: 470), 0xFF6F61, width: 80) }]),
    ]),
    // 07 抽象図形: 1 切れを引き出したパイ
    IconDesign(name: "Pie", fill: .solid(0x1F2A44), groups: [
        IconGroup(layers: [IconLayer(name: "picked") { ctx in
            fill(ctx, sector(P(512, 560), 350, from: -36, to: 36), 0xFFB703)
        }]),
        IconGroup(layers: [
            IconLayer(name: "gaps") { ctx in
                for k in 0..<5 { stroke(ctx, line(P(512, 470), polar(P(512, 470), 320, 36 + Double(k) * 72)), 0x1F2A44, width: 14) }
            },
            IconLayer(name: "pie") { ctx in
                let colors: [UInt32] = [0x8ECAE6, 0x48CAE4, 0x219EBC, 0x90E0EF]
                for k in 1..<5 {
                    fill(ctx, sector(P(512, 470), 320, from: -36 + Double(k) * 72, to: 36 + Double(k) * 72), colors[k - 1])
                }
            },
        ]),
    ]),
    // 08 抽象図形: 重なる円（板を透かして重なりを見せる）
    IconDesign(name: "Circles", fill: .solid(0x111827), groups: [
        IconGroup(translucency: 0.35, layers: [IconLayer(name: "red") { ctx in fill(ctx, circle(polar(P(512, 490), 150, 0), 240), 0xFF4D6D) }]),
        IconGroup(translucency: 0.35, layers: [IconLayer(name: "yellow") { ctx in fill(ctx, circle(polar(P(512, 490), 150, 120), 240), 0xFFD60A) }]),
        IconGroup(translucency: 0.35, layers: [IconLayer(name: "blue") { ctx in fill(ctx, circle(polar(P(512, 490), 150, 240), 240), 0x3A86FF) }]),
    ]),
    // 09 抽象図形: ひまわりの種のように並ぶ点
    IconDesign(name: "Spiral", fill: .gradient(top: 0x0F2027, bottom: 0x2C5364), groups: [
        IconGroup(layers: [IconLayer(name: "core") { ctx in fill(ctx, circle(center, 34), 0xFFFFFF) }]),
        IconGroup(layers: [IconLayer(name: "dots") { ctx in
            for n in 1..<240 {
                let d = Double(n)
                fill(ctx, circle(polar(center, 25 * d.squareRoot(), d * 137.508), 5 + d * 0.06), hsb(d / 240, 0.65, 1))
            }
        }]),
    ]),
    // 10 サイコロ: 立体
    IconDesign(name: "Cube", fill: .gradient(top: 0xF25C54, bottom: 0xB0122A), groups: [
        IconGroup(layers: [IconLayer(name: "pips") { ctx in
            let near = P(512, 512), a = P(260, 150), b = P(-260, 150), d = P(0, -300)
            fill(ctx, facePip(near, a, b, u: 0.5, v: 0.5, r: 0.17), 0xD62828)
            for (u, v) in [(0.28, 0.28), (0.72, 0.72)] { fill(ctx, facePip(near, b, d, u: u, v: v, r: 0.1), 0x222222) }
            for (u, v) in [(0.25, 0.75), (0.5, 0.5), (0.75, 0.25)] { fill(ctx, facePip(near, a, d, u: u, v: v, r: 0.1), 0x222222) }
        }]),
        IconGroup(layers: [IconLayer(name: "cube") { ctx in
            let near = P(512, 512), a = P(260, 150), b = P(-260, 150), d = P(0, -300)
            let outline = poly([near + a + b, near + a, near + a + d, near + d, near + b + d, near + b])
            stroke(ctx, outline, 0xCFCFD9, width: 30)
            fill(ctx, outline, 0xCFCFD9)
            fill(ctx, poly([near, near + a, near + a + b, near + b]), 0xFFFFFF)
            fill(ctx, poly([near, near + b, near + b + d, near + d]), 0xE9E9EF)
        }]),
    ]),
    // 11 サイコロ: ふたつ
    IconDesign(name: "Dice", fill: .gradient(top: 0x274472, bottom: 0x14213D), groups: [
        IconGroup(layers: [
            IconLayer(name: "front-pips") { ctx in
                diePips(ctx, P(600, 420), size: 360, angle: 12, count: 5) { $0 == 4 ? 0xE63946 : 0x1D3557 }
            },
            IconLayer(name: "front") { ctx in dieBody(ctx, P(600, 420), size: 360, angle: 12, color: 0xFFFFFF) },
        ]),
        IconGroup(layers: [
            IconLayer(name: "back-pips") { ctx in
                diePips(ctx, P(420, 600), size: 340, angle: -16, count: 3) { _ in 0x1D3557 }
            },
            IconLayer(name: "back") { ctx in dieBody(ctx, P(420, 600), size: 340, angle: -16, color: 0xF1FAEE) },
        ]),
    ]),
    // 12 サイコロ: 転がる
    IconDesign(name: "Roll", fill: .solid(0xFFD23F), groups: [
        IconGroup(layers: [
            IconLayer(name: "pips") { ctx in
                diePips(ctx, P(580, 500), size: 420, angle: 22, count: 6) { _ in 0x2B2D42 }
            },
            IconLayer(name: "die") { ctx in dieBody(ctx, P(580, 500), size: 420, angle: 22, color: 0xFFFFFF) },
        ]),
        IconGroup(layers: [IconLayer(name: "streaks") { ctx in
            stroke(ctx, line(P(130, 640), P(290, 640)), 0xE8A317, width: 40)
            stroke(ctx, line(P(90, 500), P(300, 500)), 0xE8A317, width: 40)
            stroke(ctx, line(P(150, 360), P(290, 360)), 0xE8A317, width: 40)
        }]),
    ]),
    // 13 サイコロ: 20 面
    IconDesign(name: "D20", fill: .gradient(top: 0x5A189A, bottom: 0x240046), groups: [
        IconGroup(layers: [IconLayer(name: "number") { ctx in
            text(ctx, "20", font: "AvenirNext-Heavy", size: 130, color: 0xFFFFFF, at: P(512, 500))
        }]),
        IconGroup(layers: [IconLayer(name: "facets") { ctx in
            let h = (0..<6).map { polar(center, 400, Double($0) * 60) }
            let t = [polar(center, 230, 0), polar(center, 230, 120), polar(center, 230, 240)]
            let facets: [([CGPoint], UInt32)] = [
                ([h[5], h[0], t[0]], 0xD9A5FF), ([h[0], h[1], t[0]], 0x9D4EDD), ([h[1], t[1], t[0]], 0xA65EEA),
                ([h[1], h[2], t[1]], 0x7B2CBF), ([h[2], h[3], t[1]], 0x5A189A), ([h[3], t[2], t[1]], 0x7B2CBF),
                ([h[3], h[4], t[2]], 0x6A1FB0), ([h[4], h[5], t[2]], 0x9D4EDD), ([h[5], t[0], t[2]], 0xB565E8),
                (t, 0xC77DFF),
            ]
            for (points, color) in facets { fill(ctx, poly(points), color) }
            for (points, _) in facets { stroke(ctx, poly(points), 0xE0AAFF, width: 7) }
        }]),
    ]),
    // 14 くじ: おみくじ
    IconDesign(name: "Omikuji", fill: .gradient(top: 0xFFF3E0, bottom: 0xFFD8A8), groups: [
        IconGroup(layers: [IconLayer(name: "stick") { ctx in
            rotated(ctx, around: P(512, 712), 18) {
                fill(ctx, box(P(512, 842), 40, 260, radius: 10), 0xF2D7A6)
                fill(ctx, box(P(512, 947), 40, 50, radius: 10), 0xD62839)
            }
        }]),
        IconGroup(layers: [
            IconLayer(name: "label-text") { ctx in
                for (i, character) in ["御", "神", "籤"].enumerated() {
                    text(ctx, character, font: "HiraMinProN-W6", size: 96, color: 0x1A1A1A, at: P(512, 556 - Double(i) * 112))
                }
            },
            IconLayer(name: "label") { ctx in fill(ctx, box(P(512, 444), 170, 380, radius: 6), 0xFFF8EE) },
            IconLayer(name: "box") { ctx in
                fill(ctx, box(P(362, 440), 80, 540), 0xA50E1C)
                fill(ctx, box(P(512, 440), 220, 540), 0xD62839)
                fill(ctx, box(P(662, 440), 80, 540), 0x8A0B17)
                fill(ctx, poly([P(322, 710), P(402, 740), P(622, 740), P(702, 710), P(622, 680), P(402, 680)]), 0x6A0812)
                fill(ctx, ellipse(P(512, 710), 64, 24), 0x2B0105)
            },
        ]),
    ]),
    // 15 くじ: 福引き（ガラポン）
    IconDesign(name: "Garapon", fill: .gradient(top: 0xFFF1C1, bottom: 0xFFC94D), groups: [
        IconGroup(layers: [IconLayer(name: "ball") { ctx in
            fillRadial(ctx, circle(P(700, 300), 50), inner: 0xFFF6C2, outer: 0xF4A100, focus: P(684, 318), radius: 64)
        }]),
        IconGroup(layers: [
            IconLayer(name: "handle") { ctx in
                let drum = P(500, 560)
                stroke(ctx, line(drum, polar(drum, 230, 60)), 0x6F4518, width: 26)
                fill(ctx, circle(polar(drum, 230, 60), 36), 0xD62828)
                fill(ctx, circle(drum, 44), 0x6F4518)
                fill(ctx, circle(drum, 18), 0xE59A54)
            },
            IconLayer(name: "drum") { ctx in
                let octagon = regular(P(500, 560), 270, sides: 8, rotation: 22.5)
                fillGradient(ctx, octagon, top: 0xE59A54, bottom: 0xB5651D)
                stroke(ctx, regular(P(500, 560), 205, sides: 8, rotation: 22.5), 0xC77A35, width: 12)
                stroke(ctx, octagon, 0x6F4518, width: 26)
            },
        ]),
        IconGroup(layers: [IconLayer(name: "stand") { ctx in
            stroke(ctx, line(P(500, 560), P(300, 170)), 0x6F4518, width: 40)
            stroke(ctx, line(P(500, 560), P(700, 170)), 0x6F4518, width: 40)
            fill(ctx, box(P(500, 150), 600, 44, radius: 22), 0x6F4518)
            fill(ctx, box(P(730, 215), 220, 56, radius: 20), 0x8D5524)
        }]),
    ]),
    // 16 くじ: あみだくじ
    IconDesign(name: "Amida", fill: .solid(0xEDF2F4), groups: [
        IconGroup(layers: [IconLayer(name: "path") { ctx in
            let route = polyline([P(257, 800), P(257, 690), P(427, 690), P(427, 560), P(597, 560), P(597, 380), P(767, 380), P(767, 230)])
            stroke(ctx, route, 0xEF233C, width: 36)
            fill(ctx, circle(P(257, 850), 38), 0xEF233C)
            fill(ctx, star(P(767, 165), outer: 68, inner: 30), 0xFFB703)
        }]),
        IconGroup(layers: [IconLayer(name: "ladder") { ctx in
            for x in [257.0, 427, 597, 767] { stroke(ctx, line(P(x, 230), P(x, 800)), 0x2B2D42, width: 26) }
            let rungs: [(Double, Double, Double)] = [(257, 427, 690), (257, 427, 420), (427, 597, 560), (427, 597, 300), (597, 767, 640), (597, 767, 380)]
            for (x0, x1, y) in rungs { stroke(ctx, line(P(x0, y), P(x1, y)), 0x2B2D42, width: 26) }
        }]),
    ]),
    // 17 くじ: 抽選券
    IconDesign(name: "Ticket", fill: .gradient(top: 0x06D6A0, bottom: 0x118AB2), groups: [
        IconGroup(layers: [IconLayer(name: "front") { ctx in
            ticket(ctx, P(550, 420), angle: -12, color: 0xFFD166, perforation: 0xE0A800, mark: 0xEF476F)
        }]),
        IconGroup(layers: [IconLayer(name: "back") { ctx in
            ticket(ctx, P(470, 610), angle: 14, color: 0xEF476F, perforation: 0xF7A1B5, mark: 0xFFFFFF)
        }]),
    ]),
    // 18 くじ: ガチャのカプセル
    IconDesign(name: "Capsule", fill: .gradient(top: 0xC3F0FF, bottom: 0x7FD3F5), groups: [
        IconGroup(layers: [IconLayer(name: "big-top") { ctx in
            capsuleHalf(ctx, P(540, 470), 300, angle: -20, top: true, color: 0xFF5C8A)
            rotated(ctx, around: P(540, 470), -20) { fill(ctx, ellipse(P(420, 640), 130, 70), 0xFFFFFF, alpha: 0.5) }
        }]),
        IconGroup(layers: [
            IconLayer(name: "big-seam") { ctx in capsuleSeam(ctx, P(540, 470), 300, angle: -20) },
            IconLayer(name: "big-bottom") { ctx in capsuleHalf(ctx, P(540, 470), 300, angle: -20, top: false, color: 0xFFFFFF) },
        ]),
        IconGroup(layers: [
            IconLayer(name: "small-seam") { ctx in capsuleSeam(ctx, P(250, 780), 115, angle: 25) },
            IconLayer(name: "small") { ctx in
                capsuleHalf(ctx, P(250, 780), 115, angle: 25, top: true, color: 0xFFD23F)
                capsuleHalf(ctx, P(250, 780), 115, angle: 25, top: false, color: 0xFFFFFF)
            },
        ]),
    ]),
    // 19 トランプ: 扇に開く
    IconDesign(name: "Fan", fill: .gradient(top: 0x2D6A4F, bottom: 0x1B4332), groups: [
        IconGroup(layers: [IconLayer(name: "spade") { ctx in fanCard(ctx, angle: 0, suit: "♠", color: 0x1B1B1B) }]),
        IconGroup(layers: [IconLayer(name: "diamond") { ctx in fanCard(ctx, angle: 20, suit: "♦", color: 0xD62828) }]),
        IconGroup(layers: [IconLayer(name: "heart") { ctx in fanCard(ctx, angle: -20, suit: "♥", color: 0xD62828) }]),
    ]),
    // 20 トランプ: スペードのエース
    IconDesign(name: "Ace", fill: .gradient(top: 0xAE2012, bottom: 0x6A040F), groups: [
        IconGroup(layers: [IconLayer(name: "marks") { ctx in
            rotated(ctx, around: center, -8) {
                text(ctx, "♠", font: "HiraginoSans-W6", size: 360, color: 0x111111, at: P(512, 500))
                text(ctx, "A", font: "AvenirNext-Bold", size: 120, color: 0x111111, at: P(352, 772))
                text(ctx, "♠", font: "HiraginoSans-W6", size: 70, color: 0x111111, at: P(352, 680))
                text(ctx, "A", font: "AvenirNext-Bold", size: 120, color: 0x111111, at: P(672, 252), rotation: 180)
                text(ctx, "♠", font: "HiraginoSans-W6", size: 70, color: 0x111111, at: P(672, 344), rotation: 180)
            }
        }]),
        IconGroup(layers: [IconLayer(name: "card") { ctx in
            rotated(ctx, around: center, -8) { fill(ctx, box(center, 500, 700, radius: 50), 0xFFFFFF) }
        }]),
    ]),
    // 21 トランプ: 裏と表
    IconDesign(name: "Cards", fill: .solid(0x14213D), groups: [
        IconGroup(layers: [
            IconLayer(name: "front-star") { ctx in
                rotated(ctx, around: P(610, 470), 10) { fill(ctx, star(P(610, 470), outer: 150, inner: 62), 0xFCA311) }
            },
            IconLayer(name: "front") { ctx in
                rotated(ctx, around: P(610, 470), 10) {
                    fill(ctx, box(P(610, 470), 420, 580, radius: 40), 0xFFFFFF)
                    stroke(ctx, box(P(610, 470), 420, 580, radius: 40), 0xE5E5E5, width: 6)
                }
            },
        ]),
        IconGroup(layers: [
            IconLayer(name: "back-pattern") { ctx in
                let c = P(430, 540)
                rotated(ctx, around: c, -14) {
                    let inner = box(c, 360, 520, radius: 20)
                    clipped(ctx, inner) {
                        for k in -12...12 {
                            let x = c.x + Double(k) * 56
                            stroke(ctx, line(P(x - 300, c.y - 300), P(x + 300, c.y + 300)), 0xFFFFFF, width: 6, alpha: 0.5)
                            stroke(ctx, line(P(x - 300, c.y + 300), P(x + 300, c.y - 300)), 0xFFFFFF, width: 6, alpha: 0.5)
                        }
                    }
                    stroke(ctx, inner, 0xFFFFFF, width: 12)
                }
            },
            IconLayer(name: "back") { ctx in
                rotated(ctx, around: P(430, 540), -14) { fill(ctx, box(P(430, 540), 420, 580, radius: 40), 0xD62828) }
            },
        ]),
    ]),
    // 22 ダイヤル・メーター: メーター
    IconDesign(name: "Gauge", fill: .gradient(top: 0x1B263B, bottom: 0x0D1B2A), groups: [
        IconGroup(layers: [IconLayer(name: "needle") { ctx in
            let c = P(512, 470)
            rotated(ctx, around: c, 55) { fill(ctx, poly([P(490, 410), P(534, 410), P(517, 770), P(507, 770)]), 0xF8F9FA) }
            fill(ctx, circle(c, 54), 0xF8F9FA)
            fill(ctx, circle(c, 22), 0xE71D36)
        }]),
        IconGroup(layers: [IconLayer(name: "ticks") { ctx in
            let c = P(512, 470)
            for k in 0...12 {
                let a = -120 + Double(k) * 20
                stroke(ctx, line(polar(c, 255, a), polar(c, k % 3 == 0 ? 205 : 225, a)), 0xFFFFFF, width: 10, alpha: 0.85)
            }
        }]),
        IconGroup(layers: [IconLayer(name: "band") { ctx in
            let c = P(512, 470)
            let colors: [UInt32] = [0x2EC4B6, 0x9BE564, 0xFFD23F, 0xFF9F1C, 0xE71D36]
            for (i, color) in colors.enumerated() {
                let from = -120 + Double(i) * 48
                fill(ctx, sector(c, 375, inner: 285, from: from + 1.5, to: from + 46.5), color)
            }
        }]),
    ]),
    // 23 ダイヤル・メーター: 金庫のダイヤル
    IconDesign(name: "Safe", fill: .gradient(top: 0xC9D1D9, bottom: 0x6C757D), groups: [
        IconGroup(layers: [IconLayer(name: "marker") { ctx in
            fill(ctx, poly([P(512, 860), P(478, 930), P(546, 930)]), 0xE63946)
        }]),
        IconGroup(layers: [IconLayer(name: "knob") { ctx in
            fillGradient(ctx, circle(center, 190), top: 0xE9ECEF, bottom: 0x868E96)
            fillGradient(ctx, circle(center, 150), top: 0x868E96, bottom: 0xDEE2E6)
            fill(ctx, circle(center, 30), 0x495057)
        }]),
        IconGroup(layers: [IconLayer(name: "face") { ctx in
            fill(ctx, circle(center, 350), 0x111418)
            for k in 0..<50 {
                let a = Double(k) * 7.2
                let long = k % 5 == 0
                stroke(ctx, line(polar(center, 338, a), polar(center, long ? 296 : 316, a)), 0xE9ECEF, width: long ? 8 : 4)
            }
            for k in 0..<10 {
                text(ctx, "\(k * 10)", font: "AvenirNext-DemiBold", size: 44, color: 0xE9ECEF, at: polar(center, 255, Double(k) * 36), rotation: Double(k) * 36)
            }
        }]),
        IconGroup(layers: [IconLayer(name: "ring") { ctx in
            fillGradient(ctx, circle(center, 400), top: 0x495057, bottom: 0x212529)
            for k in 0..<60 { stroke(ctx, line(polar(center, 362, Double(k) * 6), polar(center, 396, Double(k) * 6)), 0x6C757D, width: 7) }
        }]),
    ]),
    // 24 ダイヤル・メーター: スロット
    IconDesign(name: "Slot", fill: .gradient(top: 0x7B2CBF, bottom: 0x3C096C), groups: [
        IconGroup(layers: [IconLayer(name: "sevens") { ctx in
            for x in [277.0, 512, 747] { text(ctx, "7", font: "AvenirNext-Heavy", size: 210, color: 0xD00000, at: P(x, 512)) }
        }]),
        IconGroup(layers: [IconLayer(name: "windows") { ctx in
            for x in [277.0, 512, 747] { fillGradient(ctx, box(P(x, 512), 200, 290, radius: 28), top: 0xFFFFFF, bottom: 0xDEE2E6) }
        }]),
        IconGroup(layers: [IconLayer(name: "frame") { ctx in
            fillGradient(ctx, box(center, 820, 440, radius: 70), top: 0xFFD60A, bottom: 0xF48C06)
            fill(ctx, box(center, 760, 380, radius: 46), 0x9D0208)
        }]),
    ]),
    // 25 文字・ロゴ: D の中に盤
    IconDesign(name: "Monogram", fill: .gradient(top: 0xFF9966, bottom: 0xFF5E62), groups: [
        IconGroup(layers: [IconLayer(name: "wheel") { ctx in
            let c = P(528, 512)
            let colors: [UInt32] = [0xFF5E62, 0xFFD166, 0x06D6A0, 0x118AB2, 0x8338EC, 0xFF9F1C]
            for i in 0..<6 { fill(ctx, sector(c, 140, from: Double(i) * 60, to: Double(i + 1) * 60), colors[i]) }
            for i in 0..<6 { stroke(ctx, line(c, polar(c, 140, Double(i) * 60)), 0xFFFFFF, width: 8) }
            fill(ctx, circle(c, 24), 0xFFFFFF)
        }]),
        IconGroup(layers: [IconLayer(name: "letter") { ctx in
            let outer = CGMutablePath()
            outer.move(to: P(250, 820))
            outer.addLine(to: P(500, 820))
            outer.addArc(center: P(500, 512), radius: 308, startAngle: cgAngle(0), endAngle: cgAngle(180), clockwise: true)
            outer.addLine(to: P(250, 204))
            outer.closeSubpath()
            stroke(ctx, outer, 0xFFFFFF, width: 40)
            fill(ctx, outer, 0xFFFFFF)
            let counter = CGMutablePath()
            counter.move(to: P(370, 700))
            counter.addLine(to: P(500, 700))
            counter.addArc(center: P(500, 512), radius: 188, startAngle: cgAngle(0), endAngle: cgAngle(180), clockwise: true)
            counter.addLine(to: P(370, 324))
            counter.closeSubpath()
            clear(ctx, counter)
        }]),
    ]),
    // 26 文字・ロゴ: はてな
    IconDesign(name: "Question", fill: .gradient(top: 0x4361EE, bottom: 0x3A0CA3), groups: [
        IconGroup(layers: [IconLayer(name: "mark") { ctx in
            text(ctx, "?", font: "AvenirNext-Heavy", size: 520, color: 0x3A0CA3, at: center)
        }]),
        IconGroup(layers: [IconLayer(name: "circle") { ctx in fill(ctx, circle(center, 340), 0xFFD60A) }]),
    ]),
    // 27 文字・ロゴ: 「運」の印
    IconDesign(name: "Seal", fill: .solid(0xFAF3E3), groups: [
        IconGroup(layers: [IconLayer(name: "kanji") { ctx in
            text(ctx, "運", font: "HiraMinProN-W6", size: 400, color: 0xFAF3E3, at: center)
        }]),
        IconGroup(layers: [IconLayer(name: "seal") { ctx in
            fill(ctx, circle(center, 350), 0xC1121F)
            stroke(ctx, circle(center, 310), 0xFAF3E3, width: 16)
        }]),
    ]),
    // 28 文字・ロゴ: 針と輪
    IconDesign(name: "Needle", fill: .solid(0xF8F9FA), groups: [
        IconGroup(layers: [IconLayer(name: "needle") { ctx in
            let needle = poly([P(382, 900), P(642, 900), P(512, 560)])
            stroke(ctx, needle, 0xFF4E63, width: 40)
            fill(ctx, needle, 0xFF4E63)
        }]),
        IconGroup(layers: [IconLayer(name: "dot") { ctx in fill(ctx, circle(P(512, 470), 46), 0x2B2D42) }]),
        IconGroup(layers: [IconLayer(name: "ring") { ctx in stroke(ctx, circle(P(512, 470), 330), 0x2B2D42, width: 64) }]),
    ]),
    // 29 的・王冠: ダーツ
    IconDesign(name: "Darts", fill: .gradient(top: 0x3D405B, bottom: 0x22223B), groups: [
        IconGroup(layers: [IconLayer(name: "dart") { ctx in
            rotated(ctx, around: center, 45) {
                fill(ctx, poly([P(512, 512), P(505, 560), P(519, 560)]), 0xCED4DA)
                fillGradient(ctx, box(P(512, 650), 40, 180, radius: 14), top: 0x868E96, bottom: 0x495057)
                fill(ctx, box(P(512, 780), 16, 80, radius: 6), 0x212529)
                fill(ctx, poly([P(512, 780), P(430, 860), P(456, 930), P(512, 900), P(568, 930), P(594, 860)]), 0xFFB703)
                stroke(ctx, line(P(512, 790), P(512, 915)), 0xE85D04, width: 8)
            }
        }]),
        IconGroup(layers: [IconLayer(name: "board") { ctx in
            for i in 0..<20 {
                let from = Double(i) * 18 - 9, to = from + 18
                let dark = i % 2 == 0
                fill(ctx, sector(center, 330, from: from, to: to), dark ? 0x1A1A1A : 0xF1E3C8)
                fill(ctx, sector(center, 330, inner: 302, from: from, to: to), dark ? 0xD62828 : 0x2A9D8F)
                fill(ctx, sector(center, 215, inner: 188, from: from, to: to), dark ? 0xD62828 : 0x2A9D8F)
            }
            fill(ctx, circle(center, 50), 0x2A9D8F)
            fill(ctx, circle(center, 22), 0xD62828)
        }]),
        IconGroup(layers: [IconLayer(name: "surround") { ctx in
            fill(ctx, circle(center, 410), 0x111111)
            for i in 0..<20 { fill(ctx, circle(polar(center, 372, Double(i) * 18), 7), 0xE9ECEF) }
        }]),
    ]),
    // 30 的・王冠: 的
    IconDesign(name: "Target", fill: .solid(0xF1FAEE), groups: [
        IconGroup(layers: [IconLayer(name: "center") { ctx in fill(ctx, circle(center, 80), 0xE63946) }]),
        IconGroup(layers: [IconLayer(name: "middle") { ctx in fill(ctx, ring(center, outer: 240, inner: 160), 0xE63946, evenOdd: true) }]),
        IconGroup(layers: [IconLayer(name: "outer") { ctx in fill(ctx, ring(center, outer: 400, inner: 320), 0xE63946, evenOdd: true) }]),
    ]),
    // 31 的・王冠: 王冠
    IconDesign(name: "Crown", fill: .gradient(top: 0x0F4C5C, bottom: 0x07262E), groups: [
        IconGroup(layers: [IconLayer(name: "jewels") { ctx in
            fill(ctx, circle(P(352, 335), 30), 0xE63946)
            fill(ctx, circle(P(512, 335), 30), 0x4CC9F0)
            fill(ctx, circle(P(672, 335), 30), 0x06D6A0)
            fill(ctx, poly([P(512, 590), P(560, 540), P(512, 490), P(464, 540)]), 0xE63946)
        }]),
        IconGroup(layers: [IconLayer(name: "crown") { ctx in
            let body = poly([P(262, 380), P(222, 730), P(372, 570), P(512, 790), P(652, 570), P(802, 730), P(762, 380)])
            stroke(ctx, body, 0xF7B267, width: 24)
            fillGradient(ctx, body, top: 0xFFD166, bottom: 0xF4A261)
            for c in [P(222, 730), P(512, 790), P(802, 730)] { fill(ctx, circle(c, 36), 0xFFE29A) }
            fillGradient(ctx, box(P(512, 335), 540, 110, radius: 24), top: 0xF4A261, bottom: 0xE76F51)
        }]),
    ]),
    // 32 的・王冠: メダル
    IconDesign(name: "Medal", fill: .gradient(top: 0x1C2541, bottom: 0x0B132B), groups: [
        IconGroup(layers: [IconLayer(name: "star") { ctx in
            fill(ctx, star(P(512, 400), outer: 120, inner: 50), 0xFFF3B0)
        }]),
        IconGroup(layers: [IconLayer(name: "medal") { ctx in
            fillGradient(ctx, circle(P(512, 400), 240), top: 0xFFE066, bottom: 0xF4A100)
            stroke(ctx, circle(P(512, 400), 190), 0xFFF3B0, width: 12)
        }]),
        IconGroup(layers: [
            IconLayer(name: "ribbon-right") { ctx in fill(ctx, poly([P(604, 990), P(724, 990), P(554, 560), P(434, 560)]), 0x4361EE) },
            IconLayer(name: "ribbon-left") { ctx in fill(ctx, poly([P(300, 990), P(420, 990), P(590, 560), P(470, 560)]), 0xE63946) },
        ]),
    ]),
]

// MARK: - 書き出し

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(64)
}

let usage = """
    使い方: swift scripts/make-icon.swift <出力先のディレクトリ>
           swift scripts/make-icon.swift --candidates <出力先のディレクトリ>
    """

let arguments = Array(CommandLine.arguments.dropFirst())
let fm = FileManager.default
var isDirectory: ObjCBool = false
switch (arguments.count, arguments.first) {
case (2, "--candidates"):
    // 前の案が混ざらないよう、空のディレクトリにだけ書き出す。DekiRoulette/ の下の .icon はすべてアプリに入るので、そこには書かない
    let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
    guard !output.standardizedFileURL.pathComponents.contains("DekiRoulette") else {
        fail("案はアプリに入れないので、DekiRoulette/ の外（例: $TMPDIR）に書き出してください: \(output.path)")
    }
    if fm.fileExists(atPath: output.path, isDirectory: &isDirectory) {
        guard isDirectory.boolValue, (try fm.contentsOfDirectory(atPath: output.path)).isEmpty else {
            fail("案の出力先は空のディレクトリにしてください: \(output.path)")
        }
    } else {
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
    }
    try writeIcon(appIcon, into: output, packageName: "00-\(appIcon.name)")
    for (i, design) in candidates.enumerated() {
        try writeIcon(design, into: output, packageName: String(format: "%02d-%@", i + 1, design.name))
    }
case (1, let path?) where !path.hasPrefix("-"):
    // 打ち間違いで .icon や .xcassets の中に 2 つ目の AppIcon.icon を作らないよう、既存の普通のディレクトリだけを受け付ける
    let output = URL(fileURLWithPath: path, isDirectory: true)
    guard fm.fileExists(atPath: output.path, isDirectory: &isDirectory), isDirectory.boolValue,
          !["icon", "xcassets", "appiconset", "png"].contains(output.pathExtension) else {
        fail("出力先は既存のディレクトリ（例: DekiRoulette/Resources）にしてください: \(output.path)")
    }
    for design in appIcons { try writeIcon(design, into: output) }
default:
    fail(usage)
}
