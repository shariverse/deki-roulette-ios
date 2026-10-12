// アプリアイコンを描き、Icon Composer の .icon（icon.json と Assets/ のレイヤー画像）に組み立てる。
// 絵柄は Web 版 og.png と同じく、盤面だけの中立な絵。背景は icon.json の fill に置き、前景はレイヤーに分けて
// groups に入れる（iOS 26 以降は group ごとに Liquid Glass の奥行きが付き、それより前は Xcode が書き出す平面の画像になる）。
// 使い方: swift scripts/make-icon.swift <出力先のディレクトリ>
//   例: swift scripts/make-icon.swift DekiRoulette/Resources  → DekiRoulette/Resources/AppIcon.icon を作り直す
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - .icon の組み立て（案に依らない部分）

/// レイヤーの画像の一辺（Icon Composer の iOS の画面と同じ 1024pt を 1 倍で描く）。角丸・影・余白は描かない（OS がマスクする）
let canvas = 1024.0

/// 1 枚のレイヤー。背景は透明で、正方形の全面を使って描く
struct IconLayer {
    let name: String
    let draw: (CGContext) -> Void
}

/// Liquid Glass の 1 枚の板。`layers` は手前から並べる。
/// `translucency` は板の透け具合（0〜1）。nil なら透かさない（既定。透かすと背景の色が混ざって絵の色がくすむ）
struct IconGroup {
    var translucency: Double? = nil
    let layers: [IconLayer]
}

/// 1 つのアイコン。`groups` は手前から並べる（icon.json の順と同じ）。外観ごとの値は持たない（ダーク・色付き・クリアは自動に任せる）
struct IconDesign {
    let name: String
    let background: UInt32
    let groups: [IconGroup]
}

func cg(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// icon.json の色の書き方（`srgb:r,g,b,a`）
func iconColor(_ hex: UInt32) -> String {
    let parts = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { String(format: "%.5f", Double($0) / 255) }
    return "srgb:" + (parts + ["1.00000"]).joined(separator: ",")
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

/// `<directory>/<name>.icon` を作り直す（前のレイヤー画像が残らないよう、いったん消してから書く）
func writeIcon(_ design: IconDesign, into directory: URL) throws {
    let fm = FileManager.default
    let package = directory.appendingPathComponent("\(design.name).icon")
    let assets = package.appendingPathComponent("Assets")
    if fm.fileExists(atPath: package.path) { try fm.removeItem(at: package) }
    try fm.createDirectory(at: assets, withIntermediateDirectories: true)

    var groups: [[String: Any]] = []
    for group in design.groups {
        var layers: [[String: Any]] = []
        for layer in group.layers {
            let file = "\(layer.name).png"
            writePNG(render(layer), to: assets.appendingPathComponent(file))
            layers.append(["image-name": file, "name": layer.name])
        }
        groups.append([
            "layers": layers,
            // value は enabled が false のときも書く（無いと ictool が読めない）
            "translucency": ["enabled": group.translucency != nil, "value": group.translucency ?? 0.5],
        ])
    }
    let json: [String: Any] = [
        "fill": ["solid": iconColor(design.background)],
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

let appIcon = IconDesign(name: "AppIcon", background: 0x17111F, groups: [
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

// MARK: - 書き出し

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("使い方: swift scripts/make-icon.swift <出力先のディレクトリ>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try writeIcon(appIcon, into: output)
