import SwiftUI
import Testing
import UIKit
@testable import DekiRoulette

/// ルーレットの結果画像を `ImageRenderer` で焼き、画素数と、地・ハブ・針・止まったスライスと沈めたスライス・帯の色を画素で確かめる。
@MainActor
struct RouletteShareImageTests {
    /// ラベルは空にして、ラベルの文字が画素の確認に掛からないようにする。
    private let items = ItemLabel.makeItems(["", "", "", ""])
    /// 45 度回した 4 件の盤面では、12 時（針の下）に添字 3 のスライスが来る（315〜405 度）。帯の位置（180 度）は添字 1 の中央。
    private let rotation = 45.0
    private let outcome = SpinOutcome(index: 3, label: "■■■")

    /// 描いた画素（RGBA8、sRGB）。
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func color(at point: CGPoint) -> SIMD3<Double> {
            let x = min(max(Int(point.x), 0), width - 1)
            let y = min(max(Int(point.y), 0), height - 1)
            let offset = (y * width + x) * 4
            return SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])) / 255
        }
    }

    @Test func 画像は基本の一辺の正方形で倍率は1() throws {
        let image = try #require(ShareImageRenderer.roulette(items: items, outcome: outcome, rotation: rotation))
        #expect(image.scale == 1)
        #expect(image.size == CGSize(width: ShareImageLayout.defaultSide, height: ShareImageLayout.defaultSide))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == Int(ShareImageLayout.defaultSide))
        #expect(cgImage.height == Int(ShareImageLayout.defaultSide))
    }

    @Test func 一辺を変えると画素数もその一辺になる() throws {
        let image = try #require(ShareImageRenderer.roulette(items: items, outcome: outcome, rotation: rotation, side: 540))
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == 540)
        #expect(cgImage.height == 540)
    }

    @Test func 地は固定の色でハブの中心は盤面の印の色() throws {
        let pixels = try render()
        let layout = ShareImageLayout.roulette(side: ShareImageLayout.defaultSide)
        #expect(isClose(pixels.color(at: CGPoint(x: 10, y: 10)), srgb(Theme.shareBackground)))
        #expect(isClose(pixels.color(at: CGPoint(x: 1070, y: 1070)), srgb(Theme.shareBackground)))
        #expect(isClose(pixels.color(at: layout.wheelCenter), srgb(Theme.wheelHubMark)))
    }

    @Test func 針は盤面の上端から飛び出して開始ボタンの色() throws {
        let pixels = try render()
        let layout = ShareImageLayout.roulette(side: ShareImageLayout.defaultSide)
        let nearTop = CGPoint(x: layout.wheelCenter.x, y: layout.pointerTop + 3)
        #expect(isClose(pixels.color(at: nearTop), srgb(Theme.flare)))
        // 針の上の余白は地。止まったスライスの光彩（`stopGlowRadius` の数倍まで届く）が掛からない、画像の縁に近いところで見る
        let aboveGlow = CGPoint(x: layout.wheelCenter.x, y: ShareImageLayout.margin(side: layout.side) / 4)
        #expect(isClose(pixels.color(at: aboveGlow), srgb(Theme.shareBackground)))
    }

    @Test func 止まったスライスは塗りのままで他のスライスは沈む() throws {
        let pixels = try render()
        let layout = ShareImageLayout.roulette(side: ShareImageLayout.defaultSide)
        let stopped = pixels.color(at: location(angle: 0, fraction: 0.8, layout: layout))
        #expect(isClose(stopped, srgb(Theme.sliceColor(at: 3, count: 4))))
        for (angle, index) in [(90.0, 0), (270.0, 2)] {
            let color = pixels.color(at: location(angle: angle, fraction: 0.8, layout: layout))
            let dimmed = composite(Theme.sliceDim, over: Theme.sliceColor(at: index, count: 4))
            #expect(isClose(color, dimmed), "\(angle)")
            #expect(!isClose(color, srgb(Theme.sliceColor(at: index, count: 4))), "\(angle)")
        }
    }

    @Test func 結果の帯は盤面の中心より下に載る() throws {
        let pixels = try render()
        let layout = ShareImageLayout.roulette(side: ShareImageLayout.defaultSide)
        // 帯の中心は文字（■）か地のどちらか。沈めたスライスの色ではない
        let center = pixels.color(at: layout.bandCenter)
        #expect(isClose(center, srgb(Theme.resultBandFill)) || isClose(center, srgb(Theme.resultBandInk)))
        #expect(!isClose(center, composite(Theme.sliceDim, over: Theme.sliceColor(at: 1, count: 4))))
    }

    @Test func 色の項目は選んだ色で塗り他は今の規則で沈める() throws {
        // 止まる添字 3 に紫、沈める添字 0 に水色を選ぶ。添字 2 は自動のまま
        let styled = [
            Item(label: "", appearance: .color(.cyan)),
            Item(label: ""),
            Item(label: ""),
            Item(label: "", appearance: .color(.purple)),
        ]
        let pixels = try render(items: styled)
        let layout = ShareImageLayout.roulette(side: ShareImageLayout.defaultSide)
        let purple = Theme.sliceColors[SliceColor.purple.paletteIndex]
        let stopped = pixels.color(at: location(angle: 0, fraction: 0.8, layout: layout))
        #expect(isClose(stopped, srgb(purple)), "\(stopped)")
        #expect(!isClose(stopped, srgb(Theme.sliceColor(at: 3, count: 4))), "\(stopped)")
        let cyan = Theme.sliceColors[SliceColor.cyan.paletteIndex]
        let dimmedCyan = pixels.color(at: location(angle: 90, fraction: 0.8, layout: layout))
        #expect(isClose(dimmedCyan, composite(Theme.sliceDim, over: cyan)), "\(dimmedCyan)")
        let dimmedAuto = pixels.color(at: location(angle: 270, fraction: 0.8, layout: layout))
        #expect(isClose(dimmedAuto, composite(Theme.sliceDim, over: Theme.sliceColor(at: 2, count: 4))), "\(dimmedAuto)")
    }

    @Test func 絵文字の項目は結果の帯で絵文字が描かれる() throws {
        // 止まる添字 3 を絵文字 🟦（青い四角）、ラベルは空にする。帯の中央は絵文字だけになり、帯の地や文字の色ではなく青になる
        let styled = [Item(label: ""), Item(label: ""), Item(label: ""), Item(label: "", appearance: .emoji("🟦"))]
        let pixels = try render(items: styled, outcome: SpinOutcome(index: 3, label: ""))
        let layout = ShareImageLayout.roulette(side: ShareImageLayout.defaultSide)
        let center = pixels.color(at: layout.bandCenter)
        #expect(center.z > center.x + 0.3, "\(center)")
        #expect(!isClose(center, srgb(Theme.resultBandFill)), "\(center)")
    }

    // MARK: 計算

    private func render(items: [Item]? = nil, outcome: SpinOutcome? = nil) throws -> Pixels {
        let image = try #require(
            ShareImageRenderer.roulette(items: items ?? self.items, outcome: outcome ?? self.outcome, rotation: rotation)
        )
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

    /// 盤面の角度 `angle`（12 時が 0 度、時計回り）・スライスの半径の割合 `fraction` の画素の位置（画像は y が下向き）。
    private func location(angle: Double, fraction: Double, layout: ShareImageLayout.Roulette) -> CGPoint {
        let radius = ResultBand.sliceRadius(diameter: layout.wheelDiameter) * fraction
        let rad = angle * .pi / 180
        return CGPoint(x: layout.wheelCenter.x + radius * sin(rad), y: layout.wheelCenter.y - radius * cos(rad))
    }

    private func srgb(_ color: Color) -> SIMD3<Double> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3(Double(r), Double(g), Double(b))
    }

    /// 半透明の `top` を不透明な `bottom` に重ねたときの見た目の色。
    private func composite(_ top: Color, over bottom: Color) -> SIMD3<Double> {
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        UIColor(top).getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let base = srgb(bottom)
        let alpha = Double(ta)
        return SIMD3(Double(tr), Double(tg), Double(tb)) * alpha + base * (1 - alpha)
    }

    private func isClose(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool {
        let d = a - b
        return max(abs(d.x), abs(d.y), abs(d.z)) < 0.04
    }
}
