import Testing
import UIKit
@testable import DekiRoulette

/// 結果の下の X・LINE のロゴのボタン（Discussion #358）。
struct ShareLogoButtonTests {
    /// 読み上げの名前。「X」1 文字の名前は閉じるボタン（✕）と間違えられたので、行き先と動作が分かる名前にする（Discussion #351）。
    @Test func accessibilityNamesSayWhereAndWhat() {
        #expect(L10n.shareToX.contains("X"))
        #expect(L10n.shareToX != "X")
        #expect(L10n.shareToLINE.contains("LINE"))
        #expect(L10n.shareToLINE != "LINE")
    }

    /// ロゴの画像がアプリのバンドルにあり、ライト・ダークのどちらでも読める。
    @Test(arguments: ["ShareLogoX", "ShareLogoLINE"])
    func logoLoadsInBothAppearances(name: String) throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let image = try #require(UIImage(named: name, in: .main, compatibleWith: traits))
            #expect(image.size.width > 0)
            // 元の色のまま描く（テンプレートにしない）
            #expect(image.renderingMode != .alwaysTemplate)
        }
    }

    /// X のロゴは外観で切り替わる（ライトは黒、ダークは白）。LINE は外観に依らず同じ。
    @Test func xLogoSwitchesWithAppearance() throws {
        func centerLuminance(_ name: String, _ style: UIUserInterfaceStyle) throws -> Double {
            let image = try #require(UIImage(named: name, in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: style)))
            let cg = try #require(image.cgImage)
            // 一番濃い画素（ロゴの形のところ）の明るさを見る
            let width = cg.width, height = cg.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            var total = 0.0, count = 0.0
            for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] == 255 {
                total += (Double(pixels[i]) + Double(pixels[i + 1]) + Double(pixels[i + 2])) / (3 * 255)
                count += 1
            }
            return try #require(count > 0 ? total / count : nil)
        }
        #expect(try centerLuminance("ShareLogoX", .light) < 0.2)
        #expect(try centerLuminance("ShareLogoX", .dark) > 0.8)
        #expect(abs(try centerLuminance("ShareLogoLINE", .light) - centerLuminance("ShareLogoLINE", .dark)) < 1e-9)
    }
}
