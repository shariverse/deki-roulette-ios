// アプリアイコンを描き、Icon Composer の .icon（icon.json と Assets/ のレイヤー画像）に組み立てる。
// 背景は icon.json の fill に置き、前景はレイヤーに分けて groups に入れる（iOS 26 以降は group ごとに Liquid Glass の
// 奥行きが付き、それより前は Xcode が書き出す平面の画像になる）。既定のアイコン（AppIcon）の絵柄は Web 版 og.png と同じく、
// 盤面だけの中立な絵。
// 使い方:
//   swift scripts/make-icon.swift <出力先のディレクトリ>
//     アプリに入れるアイコンを書き出す。例: swift scripts/make-icon.swift DekiRoulette/Resources → DekiRoulette/Resources の
//     AppIcon.icon（既定）と AppIcon-<名前>.icon（代替アイコン）、設定画面の見本の画像（Assets.xcassets/<名前>-Preview.imageset）を作り直す
//     出力先は既定のアイコンを置くディレクトリ（AppIcon.icon がある、または名前が Resources）だけを受け付ける
//   swift scripts/make-icon.swift --candidates <出力先のディレクトリ>
//     アイコンの案を <番号>-<名前>.icon で書き出す（00 は今アプリに入っているアイコンで見比べる用、01〜 が案）。
//     出力先は空のディレクトリ（無ければ作る）。案はアプリに入れないので、リポジトリの中には書き出さない。
//     例: dir=$(mktemp -d) && swift scripts/make-icon.swift --candidates "$dir/icons"（一覧の画像は scripts/preview-icons.swift で作る）
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - .icon の組み立て（アイコンに依らない部分）

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
/// 名前の重なりは書き出す前に `validate` で確かめる
func writeIcon(_ design: IconDesign, into directory: URL, packageName: String? = nil) throws {
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

// MARK: - 図形の道具（代替アイコンと案で使う）
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

func stroke(_ ctx: CGContext, _ path: CGPath, _ color: UInt32, width: Double, alpha: Double = 1, cap: CGLineCap = .round, join: CGLineJoin = .round) {
    ctx.addPath(path)
    ctx.setStrokeColor(cg(color, alpha))
    ctx.setLineWidth(width)
    ctx.setLineCap(cap)
    ctx.setLineJoin(join)
    ctx.strokePath()
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

/// ネオン管のように、太く薄い線を重ねてから細い線を引く
func neon(_ ctx: CGContext, _ path: CGPath, _ color: UInt32, width: Double) {
    stroke(ctx, path, color, width: width * 4, alpha: 0.15)
    stroke(ctx, path, color, width: width * 2.2, alpha: 0.3)
    stroke(ctx, path, color, width: width)
}

// MARK: - 代替アイコン（設定画面から選べるアイコン。32 案から選定で採用した案）
// 名前（AppIcon-<名前>）は .icon のファイル名で、project.yml の ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES と同じにする。
// リリースしたら名前を変えない（利用者の選択が UIApplication.alternateIconName に名前で残るため）

let alternateIcons: [IconDesign] = [
    // ルーレット盤: ネオン（案 01）
    IconDesign(name: "AppIcon-Neon", fill: .solid(0x0B0614), groups: [
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
    // ルーレット盤: パステル（案 02）
    IconDesign(name: "AppIcon-Pastel", fill: .solid(0xFFF4E8), groups: [
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
    // ルーレット盤: ボードゲームのスピナー（案 04）
    IconDesign(name: "AppIcon-Spinner", fill: .solid(0xFDF6E3), groups: [
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
    // 的・王冠: 的（案 30）
    IconDesign(name: "AppIcon-Target", fill: .solid(0xF1FAEE), groups: [
        IconGroup(layers: [IconLayer(name: "center") { ctx in fill(ctx, circle(center, 80), 0xE63946) }]),
        IconGroup(layers: [IconLayer(name: "middle") { ctx in fill(ctx, ring(center, outer: 240, inner: 160), 0xE63946, evenOdd: true) }]),
        IconGroup(layers: [IconLayer(name: "outer") { ctx in fill(ctx, ring(center, outer: 400, inner: 320), 0xE63946, evenOdd: true) }]),
    ]),
]

/// アプリに入れるアイコン（`swift scripts/make-icon.swift <出力先>` で書き出す）。先頭が既定のアイコン
let appIcons = [appIcon] + alternateIcons

// MARK: - 案（--candidates で書き出す。アプリには入れない）
// 新しいアイコンを選ぶときに、ここへ案を足して一覧の画像（scripts/preview-icons.swift）で見比べる。キーは案の番号
// （一覧の画像と選定のやり取りで使う。案を消しても他の案の番号は変えない）。採用したら alternateIcons に移し、名前を AppIcon-<名前> にする

let candidates: [Int: IconDesign] = [:]

// MARK: - 書き出し

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(64)
}

/// 引数のパスを、シンボリックリンクと .. を OS と同じ順にたどって解決した絶対パスの要素にする。
/// URL（相対パスのとき）や standardizedFileURL は .. を文字の上で畳むので、リンクの後の .. が実際の書き出し先と食い違う。
/// まだ無い末尾の要素は、ある祖先を realpath で解決してから文字の上で足す
func resolvedComponents(_ path: String) -> [String] {
    var existing = path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
    var rest: [String] = []
    while true {
        if let resolved = realpath(existing, nil) {
            defer { free(resolved) }
            var components = (String(cString: resolved) as NSString).pathComponents
            for part in rest {
                switch part {
                case "", ".": continue
                case "..": if components.count > 1 { components.removeLast() }
                default: components.append(part)
                }
            }
            return components
        }
        rest.insert((existing as NSString).lastPathComponent, at: 0)
        existing = (existing as NSString).deletingLastPathComponent
    }
}

/// リポジトリ（project.yml がある祖先）の中か。DekiRoulette/ の下に置いたものはアプリに入り、DekiRouletteTests/ の下はテストに入る
func isInsideRepository(_ components: [String]) -> Bool {
    (1...components.count).contains { FileManager.default.fileExists(atPath: NSString.path(withComponents: Array(components.prefix($0)) + ["project.yml"])) }
}

/// 書き出す前に全部をまとめて確かめる（途中で止まって、出力先に半端な .icon が残らないように）。
/// .icon の名前とレイヤーの名前（PNG のファイル名になる）が重なると、先に書いたものが上書きされる。
/// APFS は大文字小文字を区別しないので、小文字にそろえて比べる
func validate(_ packages: [(name: String, design: IconDesign)]) {
    func overlaps(_ names: [String]) -> Bool { Set(names.map { $0.lowercased() }).count != names.count }
    if overlaps(packages.map(\.name)) { fail(".icon の名前が重なっています: \(packages.map(\.name))") }
    for (name, design) in packages {
        let layers = design.groups.flatMap { $0.layers.map(\.name) }
        if overlaps(layers) { fail("\(name) のレイヤーの名前が重なっています: \(layers)") }
    }
}

/// 設定画面のアイコンの見本の一辺（pt）。設定画面の `AppIconCell` の大きさと同じにする
let previewPoints = 64

func run(_ executable: String, _ args: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try! process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else { fatalError("\(executable) \(args.joined(separator: " ")) が失敗しました: \(text)") }
    return text
}

/// Icon Composer に付属する ictool（xcode-select で選んでいる Xcode のもの。Developer/usr/bin/ictool は別物で、画像に書き出せない）
func ictoolPath() -> String {
    let developer = run("/usr/bin/xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
    let path = URL(fileURLWithPath: developer).deletingLastPathComponent()
        .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool").path
    guard FileManager.default.isExecutableFile(atPath: path) else { fail("ictool が見つかりません: \(path)") }
    return path
}

/// アイコンの見本を `<catalog>/<名前>-Preview.imageset` に書き出す。アイコンそのものは `UIImage(named:)` で読めない
/// （iOS 26 では UIKit のアサーションで落ち、iOS 18 では nil）ので、ictool で角丸まで付けた Default の見た目を @2x・@3x の画像にする
func writePreview(of icon: URL, name: String, into catalog: URL, ictool: String) throws {
    let fm = FileManager.default
    let imageset = catalog.appendingPathComponent("\(name)-Preview.imageset")
    if fm.fileExists(atPath: imageset.path) { try fm.removeItem(at: imageset) }
    try fm.createDirectory(at: imageset, withIntermediateDirectories: false)
    var images: [[String: Any]] = [["idiom": "universal", "scale": "1x"]]
    for scale in [2, 3] {
        let file = "\(name)-Preview@\(scale)x.png"
        _ = run(ictool, [icon.path, "--export-image", "--output-file", imageset.appendingPathComponent(file).path, "--platform", "iOS",
                         "--rendition", "Default", "--width", "\(previewPoints)", "--height", "\(previewPoints)", "--scale", "\(scale)"])
        images.append(["filename": file, "idiom": "universal", "scale": "\(scale)x"])
    }
    let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try (data + Data("\n".utf8)).write(to: imageset.appendingPathComponent("Contents.json"))
    print("wrote \(imageset.path)")
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
    // 見比べるため、今アプリに入っているアイコン（既定と代替）を 00 として先頭に並べる
    let packages = appIcons.map { ("00-\($0.name)", $0) }
        + candidates.sorted(by: { $0.key < $1.key }).map { (String(format: "%02d-%@", $0.key, $0.value.name), $0.value) }
    validate(packages)
    // 前の案が混ざらないよう、空のディレクトリにだけ書き出す。DekiRoulette/ の下の .icon はすべてアプリに入るので、リポジトリの中には書かない
    let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
    guard !isInsideRepository(resolvedComponents(arguments[1])) else {
        fail("案はアプリに入れないので、リポジトリの外（例: $TMPDIR）に書き出してください: \(output.path)")
    }
    if fm.fileExists(atPath: output.path, isDirectory: &isDirectory) {
        guard isDirectory.boolValue, (try fm.contentsOfDirectory(atPath: output.path)).isEmpty else {
            fail("案の出力先は空のディレクトリにしてください: \(output.path)")
        }
    } else {
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
    }
    for (name, design) in packages { try writeIcon(design, into: output, packageName: name) }
case (1, let path?) where !path.hasPrefix("-"):
    validate(appIcons.map { ($0.name, $0) })
    // 打ち間違いで 2 つ目の AppIcon.icon を作らないよう、既定のアイコンの置き場所だけを受け付ける:
    // .icon や .xcassets などの中ではない既存のディレクトリで、AppIcon.icon が既にあるか、名前が Resources のもの
    let output = URL(fileURLWithPath: path, isDirectory: true)
    let components = resolvedComponents(path)
    let insidePackage = components.contains { ["icon", "xcassets", "appiconset", "imageset"].contains(($0 as NSString).pathExtension.lowercased()) }
    let isIconHome = fm.fileExists(atPath: output.appendingPathComponent("\(appIcon.name).icon").path) || components.last?.lowercased() == "resources"
    let catalog = output.appendingPathComponent("Assets.xcassets")
    guard fm.fileExists(atPath: output.path, isDirectory: &isDirectory), isDirectory.boolValue, !insidePackage, isIconHome,
          fm.fileExists(atPath: catalog.path) else {
        fail("出力先は既定のアイコンと Assets.xcassets を置くディレクトリ（DekiRoulette/Resources）にしてください: \(output.path)")
    }
    let ictool = ictoolPath()
    for design in appIcons { try writeIcon(design, into: output) }
    for design in appIcons {
        try writePreview(of: output.appendingPathComponent("\(design.name).icon"), name: design.name, into: catalog, ictool: ictool)
    }
default:
    fail(usage)
}
