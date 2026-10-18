import SwiftUI
import Testing
import UIKit
@testable import DekiRoulette

/// テストの引数に渡すため、`@MainActor` の外に置く。
private let styles: [UIUserInterfaceStyle] = [.light, .dark]

/// 配色がライトとダークの両方で読めることを確かめる。
/// 比率は WCAG 2.1 の相対輝度とコントラスト比の定義に従う。本文相当は 4.5:1、
/// アイコンなど大きめの要素は 3:1 を下限にする。
@MainActor
struct ThemeContrastTests {
    // MARK: 文字

    @Test(arguments: styles)
    func 本文と補助テキストは地に対して4_5対1以上(style: UIUserInterfaceStyle) {
        for background in [Theme.ink900, Theme.ink800] {
            #expect(ratio(Theme.ivory, on: background, style) >= 4.5)
            #expect(ratio(Theme.muted, on: background, style) >= 4.5)
        }
    }

    @Test(arguments: styles)
    func 結果と警告の色は地に対して4_5対1以上(style: UIUserInterfaceStyle) {
        for background in [Theme.ink900, Theme.ink800] {
            #expect(ratio(Theme.gold, on: background, style) >= 4.5)
            #expect(ratio(Theme.flareText, on: background, style) >= 4.5)
            for accent in Theme.sliceAccents {
                #expect(ratio(accent, on: background, style) >= 4.5)
            }
        }
    }

    @Test(arguments: styles)
    func 削除ボタンは地に対して3対1以上(style: UIUserInterfaceStyle) {
        #expect(ratio(Theme.ink400, on: Theme.ink800, style) >= 3)
    }

    // MARK: 塗りの上の文字

    @Test(arguments: styles)
    func スライスのラベルは塗りに対して4_5対1以上(style: UIUserInterfaceStyle) {
        for slice in Theme.sliceColors {
            #expect(ratio(Theme.onSlice, on: slice, style) >= 4.5)
        }
    }

    @Test(arguments: styles)
    func 開始ボタンの文字は塗りに対して4_5対1以上(style: UIUserInterfaceStyle) {
        #expect(ratio(Theme.onFlare, on: Theme.flare, style) >= 4.5)
    }

    @Test(arguments: styles)
    func スワイプの削除ボタンの文字は塗りに対して4_5対1以上(style: UIUserInterfaceStyle) {
        #expect(ratio(Theme.onDestructive, on: Theme.destructive, style) >= 4.5)
    }

    /// 沈めたスライスのラベルは読ませる対象ではない（結果は止まったスライスで見せる）が、どの項目かは見分けられるようにする。
    @Test(arguments: styles)
    func 沈めたスライスでもラベルは2_5対1以上(style: UIUserInterfaceStyle) {
        for slice in Theme.sliceColors {
            let dimmed = composite(resolve(Theme.sliceDim, style), over: resolve(slice, style))
            let ink = luminance(resolve(Theme.onSlice, style))
            #expect((luminance(dimmed) + 0.05) / (ink + 0.05) >= 2.5)
        }
    }

    // MARK: 停止の強調

    @Test(arguments: styles)
    func 止まったスライスの縁取りは沈めたスライスに対して3対1以上(style: UIUserInterfaceStyle) {
        let outline = luminance(resolve(Theme.stopOutline, style))
        for slice in Theme.sliceColors {
            let dimmed = luminance(composite(resolve(Theme.sliceDim, style), over: resolve(slice, style)))
            #expect((outline + 0.05) / (dimmed + 0.05) >= 3)
        }
    }

    // MARK: 結果の帯

    @Test(arguments: styles)
    func 結果の帯の文字は地に対して4_5対1以上(style: UIUserInterfaceStyle) {
        #expect(ratio(Theme.resultBandInk, on: Theme.resultBandFill, style) >= 4.5)
    }

    /// 帯は止まったスライスの上に重なる。白系の地が沈めた盤面から浮くこと（枠と影は装飾で、読みやすさは地で取る）。
    @Test(arguments: styles)
    func 結果の帯の地は沈めたスライスに対して3対1以上(style: UIUserInterfaceStyle) {
        let fill = luminance(resolve(Theme.resultBandFill, style))
        for slice in Theme.sliceColors {
            let dimmed = luminance(composite(resolve(Theme.sliceDim, style), over: resolve(slice, style)))
            #expect((fill + 0.05) / (dimmed + 0.05) >= 3)
        }
    }

    // MARK: 共有画像

    @Test(arguments: styles)
    func 共有画像のアプリ名は地に対して4_5対1以上(style: UIUserInterfaceStyle) {
        #expect(ratio(Theme.shareInk, on: Theme.shareBackground, style) >= 4.5)
    }

    /// 共有画像の地は盤面の縁より暗く、盤面の輪郭（外周線）が地から見分けられること。
    @Test(arguments: styles)
    func 共有画像の地に対して盤面の外周線は1_5対1以上(style: UIUserInterfaceStyle) {
        #expect(ratio(Theme.wheelEdge, on: Theme.shareBackground, style) >= 1.5)
    }

    // MARK: 盤面は外観に依らない

    @Test func 盤面の色は外観設定で変わらない() {
        let fixed = [
            Theme.onSlice, Theme.wheelRim, Theme.wheelEdge, Theme.wheelHub, Theme.wheelHubMark,
            Theme.flare, Theme.onFlare, Theme.destructive, Theme.onDestructive, Theme.stopOutline,
            Theme.resultBandFill, Theme.resultBandInk, Theme.shareBackground, Theme.shareInk,
        ] + Theme.sliceColors
        for color in fixed {
            #expect(resolve(color, .light) == resolve(color, .dark))
        }
    }

    @Test func 地と本文は外観設定で入れ替わる() {
        #expect(luminance(resolve(Theme.ink900, .light)) > luminance(resolve(Theme.ink900, .dark)))
        #expect(luminance(resolve(Theme.ivory, .light)) < luminance(resolve(Theme.ivory, .dark)))
    }

    // MARK: 計算

    private func resolve(_ color: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func ratio(_ foreground: Color, on background: Color, _ style: UIUserInterfaceStyle) -> Double {
        let front = luminance(resolve(foreground, style))
        let back = luminance(resolve(background, style))
        let (high, low) = front > back ? (front, back) : (back, front)
        return (high + 0.05) / (low + 0.05)
    }

    /// 半透明の `top` を不透明な `bottom` に重ねたときの見た目の色（sRGB の線形補間）。
    private func composite(_ top: UIColor, over bottom: UIColor) -> UIColor {
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        bottom.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: tr * ta + br * (1 - ta),
            green: tg * ta + bg * (1 - ta),
            blue: tb * ta + bb * (1 - ta),
            alpha: 1
        )
    }

    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

extension UIUserInterfaceStyle: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        self == .dark ? "ダーク" : "ライト"
    }
}
