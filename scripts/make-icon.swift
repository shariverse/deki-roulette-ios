// アプリアイコンを描き、Icon Composer の .icon（icon.json と Assets/ のレイヤー画像）に組み立てる。
// 背景は icon.json の fill に置き、前景はレイヤーに分けて groups に入れる（iOS 26 以降は group ごとに Liquid Glass の
// 奥行きが付き、それより前は Xcode が書き出す平面の画像になる）。既定のアイコン（AppIcon）の絵柄は Web 版 og.png と同じく、
// 盤面だけの中立な絵。
// 使い方:
//   swift scripts/make-icon.swift <出力先のディレクトリ>
//     アプリに入れるアイコンを書き出す。例: swift scripts/make-icon.swift DekiRoulette/Resources → DekiRoulette/Resources/AppIcon.icon を作り直す
import CoreGraphics
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

// MARK: - 書き出し

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(64)
}

let usage = "使い方: swift scripts/make-icon.swift <出力先のディレクトリ>"

let arguments = Array(CommandLine.arguments.dropFirst())
let fm = FileManager.default
var isDirectory: ObjCBool = false
switch (arguments.count, arguments.first) {
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
