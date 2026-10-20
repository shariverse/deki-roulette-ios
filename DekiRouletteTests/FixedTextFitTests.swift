import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import DekiRoulette

/// 盤面のラベル・結果の帯・共有画像の文字（同梱の書体の固定サイズ）が、決めてある寸法に収まることを、実際の字幅で確かめる。
/// いちばん広い文字（全角のかな・英字の W）で上限の文字数のラベルを作って測る。
struct FixedTextFitTests {
    /// 全角のかな・全角の英字・半角の英字の広い文字。Zen Maru Gothic では全角が 1em、`W` が約 0.83em。
    private static let widestCharacters: [Character] = ["あ", "Ｗ", "W", "M"]

    private static func size(_ text: String, font: UIFont) -> CGSize {
        NSAttributedString(string: text, attributes: [.font: font]).size()
    }

    /// 文字の外形（インク）の範囲。左右の余白（サイドベアリング）を除いた、実際に塗られる横の範囲。
    private static func inkBounds(_ text: String, font: UIFont) -> CGRect {
        NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(with: CGSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin, .usesDeviceMetrics], context: nil)
    }

    /// 盤面のラベルは半径方向に、中心から `WheelLabel.radiusFraction` × スライスの半径のところを中心に置く（`fixedSize` なので省略された文字列の幅のまま）。
    /// 左半分は 180 度返すので、文字の並びの向きが内向き・外向きのどちらでも、いちばん長いラベルの文字（絵文字付きを含む）が、
    /// 内側はハブに、外側は盤面の縁の外周（スライスの円の外 `Theme.Wheel3D.rimWidth`。2D の縁も同じ幅）に掛からない。
    @Test(arguments: [2, 5, 6, 8, 9, 24])
    func 盤面のラベルはハブと縁の外周の間に収まる(count: Int) throws {
        for diameter in [240.0, WheelLabel.referenceDiameter, Double(Theme.Layout.wheelMaxWidthRegular)] {
            let font = Theme.Typography.uiFont(size: WheelLabel.fontSize(count: count, diameter: diameter), weight: .bold)
            try #require(font.fontName == AppFont.Face.bold.postScriptName)
            let limit = WheelLabel.limit(count: count, diameter: diameter)
            let sliceRadius = WheelGeometry.sliceRadius(diameter: diameter)
            let center = sliceRadius * WheelLabel.radiusFraction
            let rimOuter = sliceRadius + Double(Theme.Wheel3D.rimWidth) * diameter / WheelLabel.referenceDiameter
            let hub = ResultBand.hubRadius(diameter: diameter)
            for character in Self.widestCharacters {
                for appearance in [ItemAppearance.auto, .emoji("🍣")] {
                    let label = WheelLabel.display(String(repeating: character, count: Config.maxLabelLength), appearance: appearance, limit: limit)
                    let width = Double(Self.size(label, font: font).width)
                    let ink = Self.inkBounds(label, font: font)
                    // 文字の並びが外向き（右半分）と内向き（左半分。中心について折り返す）の両方
                    let outward = (center - width / 2 + Double(ink.minX), center - width / 2 + Double(ink.maxX))
                    let inward = (center + width / 2 - Double(ink.maxX), center + width / 2 - Double(ink.minX))
                    for (inner, outer) in [outward, inward] {
                        #expect(inner >= hub, "count \(count) diameter \(diameter) \(label): inner \(inner) < hub \(hub)")
                        #expect(outer <= rimOuter, "count \(count) diameter \(diameter) \(label): outer \(outer) > rim \(rimOuter)")
                    }
                }
            }
        }
    }

    /// 結果の帯の高さの見積もり（`ResultBand.lineHeightRatio`）が、同梱の書体の 1 行の高さを下回らない（ハブ・スライスの円との重なりの確認に使うため）。
    @Test func 結果の帯の行の高さの見積もりは実際の行の高さ以上() {
        let size = ResultBand.fontSize(diameter: WheelLabel.referenceDiameter)
        let font = Theme.Typography.uiFont(size: size, weight: .black)
        #expect(font.fontName == AppFont.Face.black.postScriptName)
        #expect(Double(font.lineHeight) <= size * ResultBand.lineHeightRatio + 1e-9)
    }

    /// 共有画像の順番決めの行: 順位の欄に「24.」が、ラベルの欄に上限の文字数のラベルが収まり、1 行の高さが行に収まる。
    @Test func 共有画像の順番の行に収まる() {
        let layout = ShareImageLayout.order(side: ShareImageLayout.defaultSide)
        let rankFont = Theme.Typography.uiFont(size: layout.fontSize, weight: .black)
        let labelFont = Theme.Typography.uiFont(size: layout.fontSize, weight: .bold)
        #expect(rankFont.fontName == AppFont.Face.black.postScriptName)
        #expect(labelFont.fontName == AppFont.Face.bold.postScriptName)
        // 画面では順位に `.monospacedDigit()` を掛けているが、同梱の書体に等幅の数字（`tnum`）が無いので字幅は同じ
        for rank in ["10.", "24."] {
            #expect(Double(Self.size(rank, font: rankFont).width) <= layout.rankWidth)
        }
        for character in Self.widestCharacters {
            let label = String(repeating: character, count: Config.maxLabelLength)
            #expect(Double(Self.size(label, font: labelFont).width) <= layout.labelWidth)
            let emoji = WheelLabel.display(label, appearance: .emoji("🍣"), limit: layout.labelLimit)
            #expect(Double(Self.size(emoji, font: labelFont).width) <= layout.labelWidth)
        }
        #expect(Double(labelFont.lineHeight) <= layout.rowHeight)
    }

    /// 共有画像のアプリ名は画像の幅に収まる。
    @Test func 共有画像のアプリ名は画像に収まる() {
        let side = ShareImageLayout.defaultSide
        let font = Theme.Typography.uiFont(size: ShareImageLayout.brandFontSize(side: side), weight: .bold)
        for name in ["デキレーレット", "DekiRoulette"] {
            #expect(Double(Self.size(name, font: font).width) <= side)
        }
    }
}
