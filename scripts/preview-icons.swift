// .icon を外観ごとに画像へ書き出し、番号つきで並べた一覧の画像を作る（アイコンの案を選ぶとき・PR のスクリーンショット用）。
// 書き出しには Icon Composer に付属する ictool を使う（Xcode 26 以降。xcode-select で選んでいる Xcode のものを使う）。
// 使い方: swift scripts/preview-icons.swift <.icon を並べたディレクトリ> <出力先のディレクトリ>
//   例: swift scripts/make-icon.swift --candidates $TMPDIR/icon-candidates
//       swift scripts/preview-icons.swift $TMPDIR/icon-candidates $TMPDIR/icon-preview
//   <番号>-<名前>.icon を名前の順に並べ、次の画像を出力先に書く（出力先は無ければ作る）:
//     preview-Default.png / preview-Dark.png / preview-TintedDark.png / preview-ClearLight.png  外観ごとの一覧
//     preview-small.png  60px と 40px で並べた一覧（小さいサイズで潰れる案が分かるように）
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("使い方: swift scripts/preview-icons.swift <.icon を並べたディレクトリ> <出力先のディレクトリ>\n".utf8))
    exit(64)
}
let source = URL(fileURLWithPath: arguments[0], isDirectory: true)
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
let renders = output.appendingPathComponent("renders", isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: renders, withIntermediateDirectories: true)

let icons = try fm.contentsOfDirectory(atPath: source.path).filter { $0.hasSuffix(".icon") }.sorted()
guard !icons.isEmpty else {
    FileHandle.standardError.write(Data(".icon が見つかりません: \(source.path)\n".utf8))
    exit(1)
}

// MARK: - ictool で書き出す

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

// Developer/usr/bin/ictool は別物（--export-image を受け付けない）なので、Icon Composer.app の中のものを使う
let developer = run("/usr/bin/xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
let ictool = URL(fileURLWithPath: developer).deletingLastPathComponent()
    .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool").path
guard fm.isExecutableFile(atPath: ictool) else { fatalError("ictool が見つかりません: \(ictool)") }

func export(_ icon: String, rendition: String, size: Int) -> URL {
    let out = renders.appendingPathComponent("\((icon as NSString).deletingPathExtension)-\(rendition)-\(size).png")
    _ = run(ictool, [source.appendingPathComponent(icon).path, "--export-image", "--output-file", out.path,
                     "--platform", "iOS", "--rendition", rendition, "--width", "\(size)", "--height", "\(size)", "--scale", "1"])
    return out
}

func load(_ url: URL) -> CGImage {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

// MARK: - 一覧の画像

func cg(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// `03-Casino.icon` → `03 Casino`
func label(_ icon: String) -> String {
    (icon as NSString).deletingPathExtension.replacingOccurrences(of: "-", with: " ")
}

func draw(_ ctx: CGContext, _ string: String, size: Double, color: UInt32, centerX: Double, baseline: Double) {
    let font = CTFontCreateWithName("HiraginoSans-W6" as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): cg(color),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.textPosition = CGPoint(x: centerX - width / 2, y: baseline)
    CTLineDraw(line, ctx)
}

struct Sheet {
    let title: String
    /// 背景の上と下の色（クリアは壁紙の上での見え方を見るため、色のある背景にする）
    let background: (UInt32, UInt32)
    let text: UInt32
}

/// 各セルの画像を横に並べ（画像は縮めずに等倍で描く）、下にラベルを付けて columns 列に並べる。
/// cellWidth はセルの幅（ラベルが隣と重ならない幅にする）
func writeSheet(_ sheet: Sheet, cells: [(String, [CGImage])], columns: Int, cellWidth: Double, gap: Double, to url: URL) {
    let pad = 32.0, labelHeight = 40.0, titleHeight = 72.0
    let cell = Double(cells.flatMap { $0.1.map(\.height) }.max()!)
    let rows = (cells.count + columns - 1) / columns
    let width = pad * 2 + Double(columns) * cellWidth + Double(columns - 1) * pad
    let height = titleHeight + pad + Double(rows) * (cell + labelHeight) + Double(rows - 1) * pad / 2 + pad
    let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [cg(sheet.background.0), cg(sheet.background.1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])
    draw(ctx, sheet.title, size: 34, color: sheet.text, centerX: width / 2, baseline: height - 52)
    for (n, (name, images)) in cells.enumerated() {
        let row = n / columns, column = n % columns
        let x = pad + Double(column) * (cellWidth + pad)
        let top = height - titleHeight - pad - Double(row) * (cell + labelHeight + pad / 2)
        let imagesWidth = images.map { Double($0.width) }.reduce(0, +) + gap * Double(images.count - 1)
        var left = x + (cellWidth - imagesWidth) / 2
        for image in images {
            ctx.draw(image, in: CGRect(x: left, y: top - cell, width: Double(image.width), height: Double(image.height)))
            left += Double(image.width) + gap
        }
        draw(ctx, name, size: 22, color: sheet.text, centerX: x + cellWidth / 2, baseline: top - cell - 30)
    }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG を書き出せません: \(url.path)") }
    print("wrote \(url.path)")
}

let sheets: [(rendition: String, sheet: Sheet)] = [
    ("Default", Sheet(title: "Default", background: (0xF2F2F7, 0xF2F2F7), text: 0x1C1C1E)),
    ("Dark", Sheet(title: "Dark", background: (0x1C1C1E, 0x1C1C1E), text: 0xF2F2F7)),
    ("TintedDark", Sheet(title: "TintedDark", background: (0x1C1C1E, 0x1C1C1E), text: 0xF2F2F7)),
    ("ClearLight", Sheet(title: "ClearLight", background: (0x7FA7D9, 0x3E6AA8), text: 0xFFFFFF)),
]
for (rendition, sheet) in sheets {
    let cells = icons.map { (label($0), [load(export($0, rendition: rendition, size: 200))]) }
    writeSheet(sheet, cells: cells, columns: 6, cellWidth: 200, gap: 0, to: output.appendingPathComponent("preview-\(rendition).png"))
}
let small = icons.map { (label($0), [load(export($0, rendition: "Default", size: 60)), load(export($0, rendition: "Default", size: 40))]) }
writeSheet(Sheet(title: "Default 60px / 40px", background: (0xF2F2F7, 0xF2F2F7), text: 0x1C1C1E),
           cells: small, columns: 6, cellWidth: 160, gap: 16, to: output.appendingPathComponent("preview-small.png"))
