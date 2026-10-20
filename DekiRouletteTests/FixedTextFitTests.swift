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
    /// いちばん長いラベルの文字が、内側はハブに、外側は盤面の外枠に掛からない。
    @Test(arguments: [2, 5, 6, 8, 9, 24])
    func 盤面のラベルはハブと外枠の間に収まる(count: Int) {
        for diameter in [240.0, WheelLabel.referenceDiameter, Double(Theme.Layout.wheelMaxWidthRegular)] {
            let font = Theme.Typography.uiFont(size: WheelLabel.fontSize(count: count, diameter: diameter), weight: .bold)
            let limit = WheelLabel.limit(count: count, diameter: diameter)
            let center = WheelGeometry.sliceRadius(diameter: diameter) * WheelLabel.radiusFraction
            for character in Self.widestCharacters {
                let label = WheelLabel.display(String(repeating: character, count: Config.maxLabelLength), appearance: .auto, limit: limit)
                let width = Double(Self.size(label, font: font).width)
                let ink = Self.inkBounds(label, font: font)
                let inner = center - width / 2 + Double(ink.minX)
                let outer = center - width / 2 + Double(ink.maxX)
                #expect(inner >= ResultBand.hubRadius(diameter: diameter), "count \(count) diameter \(diameter) \(character): inner \(inner)")
                #expect(outer <= diameter / 2, "count \(count) diameter \(diameter) \(character): outer \(outer)")
            }
        }
    }

    /// 結果の帯の高さの見積もり（`ResultBand.lineHeightRatio`）が、同梱の書体の 1 行の高さを下回らない（ハブ・スライスの円との重なりの確認に使うため）。
    @Test func 結果の帯の行の高さの見積もりは実際の行の高さ以上() {
        let size = ResultBand.fontSize(diameter: WheelLabel.referenceDiameter)
        let font = Theme.Typography.uiFont(size: size, weight: .black)
        #expect(Double(font.lineHeight) <= size * ResultBand.lineHeightRatio + 1e-9)
    }

    /// 共有画像の順番決めの行: 順位の欄に「24.」が、ラベルの欄に上限の文字数のラベルが収まり、1 行の高さが行に収まる。
    @Test func 共有画像の順番の行に収まる() {
        let layout = ShareImageLayout.order(side: ShareImageLayout.defaultSide)
        let rankFont = Theme.Typography.uiFont(size: layout.fontSize, weight: .black)
        let labelFont = Theme.Typography.uiFont(size: layout.fontSize, weight: .bold)
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
