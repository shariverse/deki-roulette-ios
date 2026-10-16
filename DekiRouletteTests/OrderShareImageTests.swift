import SwiftUI
import Testing
import UIKit
@testable import DekiRoulette

/// 順番決めの結果画像を `ImageRenderer` で焼き、画素数と、地・1 位の色・省略の行を画素で確かめる。
@MainActor
struct OrderShareImageTests {
    private let side = ShareImageLayout.defaultSide
    /// ■ はどの書体でも塗りつぶしの字形になるので、文字の色を画素で数えられる。
    private let labels = ["■■■", "■■■", "■■■"]

    /// 描いた画素（RGBA8、sRGB）。
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func color(at x: Int, _ y: Int) -> SIMD3<Double> {
            let x = min(max(x, 0), width - 1)
            let y = min(max(y, 0), height - 1)
            let offset = (y * width + x) * 4
            return SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])) / 255
        }
    }

    @Test func 画像は基本の一辺の正方形で倍率は1() throws {
        let image = try #require(ShareImageRenderer.order(labels: labels))
        #expect(image.scale == 1)
        #expect(image.size == CGSize(width: side, height: side))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == Int(side))
        #expect(cgImage.height == Int(side))
    }

    @Test func 一辺を変えると画素数もその一辺になる() throws {
        let image = try #require(ShareImageRenderer.order(labels: labels, side: 540))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == 540)
        #expect(cgImage.height == 540)
    }

    @Test func 地は固定の色() throws {
        let pixels = try render(labels)
        #expect(isClose(pixels.color(at: 10, 10), srgb(Theme.shareBackground)))
        #expect(isClose(pixels.color(at: 1070, 1070), srgb(Theme.shareBackground)))
    }

    @Test func 一位の行にだけ金色の文字があり他の行は本文の色() throws {
        let pixels = try render(labels)
        let layout = ShareImageLayout.order(side: side)
        let gold = resolved(Theme.gold)
        let ivory = resolved(Theme.ivory)
        #expect(count(in: rowRect(index: 0, count: labels.count, layout: layout), near: gold, pixels: pixels) > 30)
        #expect(count(in: rowRect(index: 0, count: labels.count, layout: layout), near: ivory, pixels: pixels) == 0)
        for index in 1..<labels.count {
            let rect = rowRect(index: index, count: labels.count, layout: layout)
            #expect(count(in: rect, near: gold, pixels: pixels) == 0, "\(index)")
            #expect(count(in: rect, near: ivory, pixels: pixels) > 30, "\(index)")
        }
    }

    @Test func 上限を超える件数では最後の行が省略の件数になる() throws {
        let many = Array(repeating: "■■■", count: Config.maxItems)
        let pixels = try render(many)
        let layout = ShareImageLayout.order(side: side)
        let rows = layout.rows(count: many.count)
        #expect(rows.total == layout.maxRows)
        #expect(rows.omitted > 0)
        let ivory = resolved(Theme.ivory)
        let muted = resolved(Theme.muted)
        // 並べた最後の行は本文の色、省略の行は補助の色だけ
        #expect(count(in: rowRect(index: rows.shown - 1, count: many.count, layout: layout), near: ivory, pixels: pixels) > 30)
        let last = rowRect(index: rows.total - 1, count: many.count, layout: layout)
        #expect(count(in: last, near: ivory, pixels: pixels) == 0)
        #expect(count(in: last, near: muted, pixels: pixels) > 30)
        // 行の束の下は地
        let below = Int(layout.rowTop(index: rows.total, count: many.count)) + 4
        #expect(isClose(pixels.color(at: Int(side / 2), below), srgb(Theme.shareBackground)))
    }

    @Test func 件数が上限ちょうどなら全件を並べて省略の行は出ない() throws {
        let layout = ShareImageLayout.order(side: side)
        let exact = Array(repeating: "■■■", count: layout.maxRows)
        let pixels = try render(exact)
        let rows = layout.rows(count: exact.count)
        #expect(rows == ShareImageLayout.Order.Rows(shown: exact.count, omitted: 0))
        // 最後の行（10 位）は 1 位の色ではなく本文の色で、その下は地
        let last = rowRect(index: exact.count - 1, count: exact.count, layout: layout)
        #expect(count(in: last, near: resolved(Theme.gold), pixels: pixels) == 0)
        #expect(count(in: last, near: resolved(Theme.ivory), pixels: pixels) > 30)
        let below = Int(layout.rowTop(index: exact.count, count: exact.count)) + 4
        #expect(isClose(pixels.color(at: Int(side / 2), below), srgb(Theme.shareBackground)))
    }

    @Test func 二桁の順位は順位の欄に収まる() {
        // 「10.」を画像と同じ書体（太字・丸ゴシック・等幅数字）で測り、欄の幅を超えないことを確かめる
        let layout = ShareImageLayout.order(side: side)
        var font = UIFont.systemFont(ofSize: layout.fontSize, weight: .black)
        if let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: layout.fontSize)
        }
        font = UIFont(descriptor: font.fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType, .selector: kMonospacedNumbersSelector]],
        ]), size: layout.fontSize)
        let width = ("\(layout.maxRows)." as NSString).size(withAttributes: [.font: font]).width
        #expect(width <= layout.rankWidth, "\(width) > \(layout.rankWidth)")
    }

    // MARK: 計算

    private func render(_ labels: [String]) throws -> Pixels {
        let image = try #require(ShareImageRenderer.order(labels: labels))
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        return Pixels(width: width, height: height, bytes: bytes)
    }

    /// 行の内側（枠線を除く）の範囲。
    private func rowRect(index: Int, count: Int, layout: ShareImageLayout.Order) -> CGRect {
        CGRect(
            x: layout.rowsLeft, y: layout.rowTop(index: index, count: count),
            width: layout.rowWidth, height: layout.rowHeight
        ).insetBy(dx: 6, dy: 6)
    }

    /// `rect` の中で `color` に近い画素の数。
    private func count(in rect: CGRect, near color: SIMD3<Double>, pixels: Pixels) -> Int {
        var total = 0
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 2) {
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 2) where isClose(pixels.color(at: x, y), color) {
                total += 1
            }
        }
        return total
    }

    private func srgb(_ color: Color) -> SIMD3<Double> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(Double(r), Double(g), Double(b))
    }

    /// 外観で変わる色を、画像と同じダークで解決した値。
    private func resolved(_ color: Color) -> SIMD3<Double> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(Double(r), Double(g), Double(b))
    }

    private func isClose(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool {
        let d = a - b
        return max(abs(d.x), abs(d.y), abs(d.z)) < 0.04
    }
}
