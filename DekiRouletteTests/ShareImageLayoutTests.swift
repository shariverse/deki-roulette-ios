import Foundation
import Testing
@testable import DekiRoulette

struct ShareImageLayoutTests {
    private let side = ShareImageLayout.defaultSide
    private let sides = [540.0, 1080, 2160]

    @Test func 基本の一辺は1080px() {
        #expect(ShareImageLayout.defaultSide == 1080)
    }

    // MARK: 共通

    @Test(arguments: [540.0, 1080, 2160])
    func アプリ名は下の余白のすぐ上に置き内容の範囲と重ならない(side: Double) {
        let brandTop = ShareImageLayout.brandCenterY(side: side) - ShareImageLayout.brandLineHeight(side: side) / 2
        let brandBottom = ShareImageLayout.brandCenterY(side: side) + ShareImageLayout.brandLineHeight(side: side) / 2
        #expect(abs(brandBottom - (side - ShareImageLayout.margin(side: side))) < 1e-9)
        #expect(ShareImageLayout.contentRange(side: side).upperBound < brandTop)
        #expect(ShareImageLayout.contentRange(side: side).lowerBound == ShareImageLayout.margin(side: side))
    }

    @Test func 余白と文字サイズは一辺に比例する() {
        #expect(ShareImageLayout.margin(side: 2160) == ShareImageLayout.margin(side: 1080) * 2)
        #expect(ShareImageLayout.brandFontSize(side: 2160) == ShareImageLayout.brandFontSize(side: 1080) * 2)
        #expect(abs(ShareImageLayout.brandCenterY(side: 2160) - ShareImageLayout.brandCenterY(side: 1080) * 2) < 1e-9)
    }

    @Test func アプリ名は結果の帯より小さく盤面のラベルより大きい() {
        let layout = ShareImageLayout.roulette(side: side)
        let brand = ShareImageLayout.brandFontSize(side: side)
        #expect(brand < ResultBand.fontSize(diameter: layout.wheelDiameter))
        for count in Config.minItems...Config.maxItems {
            #expect(brand > WheelLabel.fontSize(count: count, diameter: layout.wheelDiameter))
        }
    }

    // MARK: ルーレット

    @Test(arguments: [540.0, 1080, 2160])
    func 盤面は針を含めて余白の内側に収まる(side: Double) {
        let layout = ShareImageLayout.roulette(side: side)
        let margin = ShareImageLayout.margin(side: side)
        #expect(layout.wheelDiameter > 0)
        #expect(layout.pointerTop >= margin - 1e-9)
        #expect(layout.wheelCenter.x - layout.wheelDiameter / 2 >= margin - 1e-9)
        #expect(layout.wheelCenter.x + layout.wheelDiameter / 2 <= side - margin + 1e-9)
        #expect(layout.wheelBottom <= ShareImageLayout.contentRange(side: side).upperBound + 1e-9)
        // 左右中央
        #expect(layout.wheelCenter.x == side / 2)
    }

    @Test func 盤面は内容の範囲を縦いっぱいに使う() {
        // 1080 では縦（針の飛び出し + 直径）が先に当たる。幅には余りが出る
        let layout = ShareImageLayout.roulette(side: side)
        let range = ShareImageLayout.contentRange(side: side)
        #expect(abs(layout.pointerTop - range.lowerBound) < 1e-9)
        #expect(abs(layout.wheelBottom - range.upperBound) < 1e-9)
        #expect(layout.wheelDiameter < side - ShareImageLayout.margin(side: side) * 2)
        // 画面の基準（320pt）より十分大きく、ラベルの省略は iPad の横並び（480pt）より緩くなる
        #expect(layout.wheelDiameter > Double(Theme.Layout.wheelMaxWidthRegular))
    }

    @Test func 針は画面と同じ比率で盤面に合わせる() {
        let layout = ShareImageLayout.roulette(side: side)
        let scale = layout.wheelDiameter / WheelLabel.referenceDiameter
        #expect(abs(layout.pointerSize.width - ShareImageLayout.basePointerWidth * scale) < 1e-9)
        #expect(abs(layout.pointerSize.height - ShareImageLayout.basePointerHeight * scale) < 1e-9)
        #expect(abs(layout.pointerOverhang - ShareImageLayout.basePointerOverhang * scale) < 1e-9)
        // 針の下端は盤面の中に入る
        #expect(layout.pointerTop + layout.pointerSize.height > layout.wheelTop)
    }

    @Test(arguments: [540.0, 1080, 2160])
    func 帯は盤面の中心より下でハブと重ならず盤面に収まる(side: Double) {
        let layout = ShareImageLayout.roulette(side: side)
        let d = layout.wheelDiameter
        #expect(layout.bandCenter.x == layout.wheelCenter.x)
        #expect(abs((layout.bandCenter.y - layout.wheelCenter.y) - ResultBand.centerOffset(diameter: d)) < 1e-9)
        let bandTop = layout.bandCenter.y - ResultBand.height(diameter: d) / 2
        #expect(bandTop > layout.wheelCenter.y + ResultBand.hubRadius(diameter: d))
        #expect(layout.bandCenter.y + ResultBand.height(diameter: d) / 2 < layout.wheelCenter.y + ResultBand.sliceRadius(diameter: d))
    }

    @Test func ルーレットの寸法は一辺に比例する() {
        let a = ShareImageLayout.roulette(side: 1080)
        let b = ShareImageLayout.roulette(side: 2160)
        #expect(abs(b.wheelDiameter - a.wheelDiameter * 2) < 1e-9)
        #expect(abs(b.wheelCenter.y - a.wheelCenter.y * 2) < 1e-9)
        #expect(abs(b.pointerSize.height - a.pointerSize.height * 2) < 1e-9)
    }

    // MARK: 順番決め

    @Test func 行数の上限は1080pxで10行() {
        #expect(ShareImageLayout.order(side: side).maxRows == 10)
    }

    @Test func 上限までは全件を並べ超えたら最後の行をまとめる() {
        let layout = ShareImageLayout.order(side: side)
        let max = layout.maxRows
        for count in Config.minItems...max {
            let rows = layout.rows(count: count)
            #expect(rows == ShareImageLayout.Order.Rows(shown: count, omitted: 0))
            #expect(rows.total == count)
        }
        for count in (max + 1)...Config.maxItems {
            let rows = layout.rows(count: count)
            #expect(rows.shown == max - 1)
            #expect(rows.omitted == count - (max - 1))
            #expect(rows.omitted >= 2, "まとめる行には 2 件以上が入る（1 件だけなら並べたほうが短い）")
            #expect(rows.total == max)
            #expect(rows.shown + rows.omitted == count)
        }
    }

    @Test(arguments: [540.0, 1080, 2160])
    func 行の束は内容の範囲に収まり上下中央に置く(side: Double) {
        let layout = ShareImageLayout.order(side: side)
        let range = layout.contentRange
        for count in 0...Config.maxItems {
            let total = layout.rows(count: count).total
            let top = layout.rowsTop(count: count)
            let bottom = top + layout.rowsHeight(total: total)
            #expect(top >= range.lowerBound - 1e-9, "count=\(count)")
            #expect(bottom <= range.upperBound + 1e-9, "count=\(count)")
            #expect(abs((top - range.lowerBound) - (range.upperBound - bottom)) < 1e-9, "count=\(count)")
            if total > 0 {
                let last = layout.rowTop(index: total - 1, count: count)
                #expect(abs(last + layout.rowHeight - bottom) < 1e-9)
            }
        }
    }

    @Test func 行は左右の余白の内側に置く() {
        let layout = ShareImageLayout.order(side: side)
        let margin = ShareImageLayout.margin(side: side)
        #expect(layout.rowsLeft == margin)
        #expect(layout.rowWidth == side - margin * 2)
        #expect(layout.labelWidth > 0)
        #expect(layout.labelWidth < layout.rowWidth)
    }

    @Test func ラベルは項目の最大文字数をそのまま置ける() {
        // 全角 20 文字（`Config.maxLabelLength`）が 1 行に収まる。超える場合だけ `WheelLabel.truncate` で省略する
        let layout = ShareImageLayout.order(side: side)
        #expect(layout.labelLimit >= Config.maxLabelLength)
        #expect(Double(layout.labelLimit) * layout.fontSize <= layout.labelWidth)
    }

    @Test func 順番決めの寸法は一辺に比例し行数は変わらない() {
        let a = ShareImageLayout.order(side: 1080)
        let b = ShareImageLayout.order(side: 2160)
        #expect(abs(b.rowHeight - a.rowHeight * 2) < 1e-9)
        #expect(abs(b.fontSize - a.fontSize * 2) < 1e-9)
        #expect(abs(b.rankWidth - a.rankWidth * 2) < 1e-9)
        #expect(b.maxRows == a.maxRows)
        #expect(b.labelLimit == a.labelLimit)
    }

    // MARK: 不正な入力

    @Test(arguments: [0.0, -10, .infinity, .nan])
    func 一辺が0以下や不正でも落ちない(side: Double) {
        let roulette = ShareImageLayout.roulette(side: side)
        #expect(roulette.wheelDiameter == 0)
        #expect(roulette.pointerSize == .zero)
        let order = ShareImageLayout.order(side: side)
        #expect(order.maxRows == 0)
        #expect(order.labelLimit == 0)
        #expect(order.rows(count: 5) == ShareImageLayout.Order.Rows(shown: 0, omitted: 5))
        #expect(order.rowsTop(count: 5) == 0)
        #expect(ShareImageLayout.margin(side: side) == 0)
    }
}
