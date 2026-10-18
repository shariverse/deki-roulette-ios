// アプリアイコン (1024x1024) を描く。Web 版 og.png と同じく、盤面だけの中立な絵にする。
// iOS は 1 枚の絵（背景 + 盤面）。visionOS は 2 層（背景の Back と、透明な地に盤面を描いた Front）に分ける。
// 使い方: swift scripts/make-icon.swift <iOS 用の AppIcon.png のパス> [<AppIcon.solidimagestack のディレクトリ>]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let colors: [UInt32] = [0xFF8080, 0xFFA366, 0xF2CE5C, 0xA3DB6B, 0x5FD6A8, 0x5CC9E0, 0x7BAEF5, 0xA48CF0, 0xCE8CEE, 0xFF85C0]

func cg(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func makeContext() -> CGContext {
    CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// アイコンの地。visionOS では Back 層になる。
func drawBackground(_ ctx: CGContext) {
    ctx.setFillColor(cg(0x17111F))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
}

/// 盤面と針。visionOS では Front 層になる（地は透明のまま）。
func drawWheel(_ ctx: CGContext) {
    let center = CGPoint(x: size / 2, y: size / 2)
    let radius = size * 0.38
    ctx.setFillColor(cg(0x2A2138))
    ctx.addArc(center: center, radius: radius + 34, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    let slice = .pi * 2 / Double(colors.count)
    for (i, hex) in colors.enumerated() {
        // 12 時から時計回りに並べる。CG は y 軸上向きなので角度を反転する
        let start = .pi / 2 - Double(i) * slice
        let end = start - slice
        ctx.move(to: center)
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        ctx.closePath()
        ctx.setFillColor(cg(hex))
        ctx.fillPath()
    }
    ctx.setStrokeColor(cg(0x17111F))
    ctx.setLineWidth(6)
    for i in 0..<colors.count {
        let a = .pi / 2 - Double(i) * slice
        ctx.move(to: center)
        ctx.addLine(to: CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius))
        ctx.strokePath()
    }

    ctx.setFillColor(cg(0x1F1829))
    ctx.addArc(center: center, radius: 62, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()
    ctx.setStrokeColor(cg(0xF5EFE6))
    ctx.setLineWidth(8)
    ctx.addArc(center: center, radius: 62, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.setFillColor(cg(0xF5EFE6))
    ctx.addArc(center: center, radius: 20, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    // 針
    ctx.setFillColor(cg(0xFF4E63))
    let tipY = center.y + radius - 40
    ctx.move(to: CGPoint(x: center.x, y: tipY))
    ctx.addLine(to: CGPoint(x: center.x - 36, y: tipY + 90))
    ctx.addLine(to: CGPoint(x: center.x + 36, y: tipY + 90))
    ctx.closePath()
    ctx.fillPath()
}

func write(_ ctx: CGContext, to path: String) {
    let out = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(out.path)")
}

let flat = makeContext()
drawBackground(flat)
drawWheel(flat)
write(flat, to: CommandLine.arguments[1])

// 2 つ目が渡されたら visionOS の 2 層も描く（Back は地だけ、Front は透明な地に盤面だけ）
if CommandLine.arguments.count > 2 {
    let stack = CommandLine.arguments[2]
    let back = makeContext()
    drawBackground(back)
    write(back, to: "\(stack)/Back.solidimagestacklayer/Content.imageset/AppIconBack.png")

    let front = makeContext()
    drawWheel(front)
    write(front, to: "\(stack)/Front.solidimagestacklayer/Content.imageset/AppIconFront.png")
}
