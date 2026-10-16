import CoreGraphics
import Foundation

/// 共有シートに渡す結果の画像の寸法とレイアウト。正方形 1 枚（基本は `defaultSide` = 1080px 四方）を前提に、
/// 画像の一辺からすべての位置と大きさを決める。描画（View）はここに含めず、`ImageRenderer` で焼く View が
/// この値をそのまま座標に使う（単位は描画の単位。`scale` を 1 にすれば px と一致する）。
///
/// 画像には盤面と結果（ルーレット）または順位（順番決め）とアプリ名だけを載せる。項目リスト・印・指定の有無は
/// ここでは扱わず、受け取る口も作らない（SPEC §6.5・§7.3）。
enum ShareImageLayout {
    /// 基本の一辺（px）。X・Instagram・LINE のどれでも縮めずに出せる正方形。
    static let defaultSide: Double = 1080

    /// 画像の縁から内容までの余白（一辺に対する割合）。
    static let marginRatio = 0.08
    /// アプリ名の文字サイズ（一辺に対する割合）。
    static let brandFontRatio = 0.036
    /// アプリ名の 1 行の高さの見積もり（文字サイズに対する割合）。`ResultBand.lineHeightRatio` と同じ。
    static let brandLineHeightRatio = ResultBand.lineHeightRatio
    /// 内容（盤面・カード）とアプリ名の間隔（一辺に対する割合）。
    static let brandGapRatio = 0.03

    /// 針の大きさ（盤面の基準直径 `WheelLabel.referenceDiameter` での pt）。画面の針（`RouletteWheelView`、22×26pt の固定）を
    /// 基準直径での大きさとみなし、共有画像では盤面の直径に比例させる。
    static let basePointerWidth: Double = 22
    static let basePointerHeight: Double = 26
    /// 針が盤面の上端から外へ出る長さ（基準直径での pt）。画面の針の `offset(y: -6)` を基準直径での値とみなす。
    static let basePointerOverhang: Double = 6

    /// 順番決めのカードの 1 行の高さ（一辺に対する割合）。
    static let orderRowHeightRatio = 0.064
    /// 行と行の間隔（一辺に対する割合）。
    static let orderRowSpacingRatio = 0.012
    /// 行の文字サイズ（一辺に対する割合）。
    static let orderFontRatio = 0.03
    /// 行の左右の内側の余白（一辺に対する割合）。
    static let orderRowPaddingRatio = 0.02
    /// 順位の欄の幅（一辺に対する割合）。2 桁の順位が入る（順位の書き方は描画側が決める）。
    static let orderRankWidthRatio = 0.045
    /// 順位の欄とラベルの間隔（一辺に対する割合）。
    static let orderRankGapRatio = 0.012

    // MARK: 共通

    /// 画像の縁から内容までの余白。
    static func margin(side: Double) -> Double {
        clamp(side) * marginRatio
    }

    /// アプリ名の文字サイズ。
    static func brandFontSize(side: Double) -> Double {
        clamp(side) * brandFontRatio
    }

    /// アプリ名の 1 行の高さの見積もり。
    static func brandLineHeight(side: Double) -> Double {
        brandFontSize(side: side) * brandLineHeightRatio
    }

    /// アプリ名の行の中心の y 座標。画像の下の余白のすぐ上に置く。
    static func brandCenterY(side: Double) -> Double {
        clamp(side) - margin(side: side) - brandLineHeight(side: side) / 2
    }

    /// 内容（盤面・カード）を置ける縦の範囲。上の余白から、アプリ名との間隔の上端まで。
    static func contentRange(side: Double) -> ClosedRange<Double> {
        let top = margin(side: side)
        let bottom = clamp(side) - margin(side: side) - brandLineHeight(side: side) - clamp(side) * brandGapRatio
        return top...max(top, bottom)
    }

    // MARK: ルーレット

    /// ルーレットの画像の寸法。盤面は左右の余白いっぱいに広げ、縦は針の飛び出しとアプリ名の分を除いた範囲に収める。
    struct Roulette: Equatable {
        /// 画像の一辺。
        let side: Double
        /// 盤面の直径。`WheelLabel` / `ResultBand` にはこの値を渡す。
        let wheelDiameter: Double
        /// 盤面の中心。
        let wheelCenter: CGPoint
        /// 針の大きさ。
        let pointerSize: CGSize
        /// 針が盤面の上端から外へ出る長さ。針の下端は盤面の上端からこの分だけ内側に入る。
        let pointerOverhang: Double

        /// 盤面の上端。
        var wheelTop: Double { wheelCenter.y - wheelDiameter / 2 }
        /// 盤面の下端。
        var wheelBottom: Double { wheelCenter.y + wheelDiameter / 2 }
        /// 針の上端（画像の中で最も上に来る内容）。
        var pointerTop: Double { wheelTop - pointerOverhang }
        /// 結果の帯の中心。盤面の中心から `ResultBand.centerOffset` だけ下。
        var bandCenter: CGPoint {
            CGPoint(x: wheelCenter.x, y: wheelCenter.y + ResultBand.centerOffset(diameter: wheelDiameter))
        }
    }

    /// 一辺 `side` のルーレットの画像の寸法。
    static func roulette(side rawSide: Double) -> Roulette {
        let side = clamp(rawSide)
        let margin = margin(side: side)
        let range = contentRange(side: side)
        // 針の飛び出しは直径に比例するので、直径 d について d + overhang(d) = 高さ を解く
        let overhangRatio = basePointerOverhang / WheelLabel.referenceDiameter
        let byHeight = (range.upperBound - range.lowerBound) / (1 + overhangRatio)
        let byWidth = side - margin * 2
        let diameter = max(0, min(byWidth, byHeight))
        let scale = diameter / WheelLabel.referenceDiameter
        let overhang = basePointerOverhang * scale
        return Roulette(
            side: side,
            wheelDiameter: diameter,
            wheelCenter: CGPoint(x: side / 2, y: range.lowerBound + overhang + diameter / 2),
            pointerSize: CGSize(width: basePointerWidth * scale, height: basePointerHeight * scale),
            pointerOverhang: overhang
        )
    }

    // MARK: 順番決め

    /// 順番決めの画像の寸法。順位の行を上から並べ、行数が上限を超えるときは最後の行を「ほか M 件」にする。
    struct Order: Equatable {
        /// 画像の一辺。
        let side: Double
        /// 行（カード）の左端。
        let rowsLeft: Double
        /// 行（カード）の幅。
        let rowWidth: Double
        /// 1 行の高さ。
        let rowHeight: Double
        /// 行と行の間隔。
        let rowSpacing: Double
        /// 行の文字サイズ（順位・ラベルとも）。
        let fontSize: Double
        /// 行の左右の内側の余白。
        let rowPadding: Double
        /// 順位の欄の幅。
        let rankWidth: Double
        /// 順位の欄とラベルの間隔。
        let rankGap: Double
        /// 画像に置ける行数の上限（「ほか M 件」の行を含む）。
        let maxRows: Int
        /// 行を置ける縦の範囲。
        let contentRange: ClosedRange<Double>

        /// ラベルを置ける幅。
        var labelWidth: Double { max(0, rowWidth - rowPadding * 2 - rankWidth - rankGap) }

        /// ラベルの最大文字数。全角 1 文字を文字サイズと同じ幅とみなして数え、超える分は `WheelLabel.truncate` で省略する。
        var labelLimit: Int {
            guard fontSize > 0 else { return 0 }
            return Int((labelWidth / fontSize).rounded(.down))
        }

        /// 行の内訳。`shown` 件を順位つきで並べ、`omitted` が 1 以上なら最後に「ほか `omitted` 件」の行を足す。
        struct Rows: Equatable {
            let shown: Int
            let omitted: Int
            /// 画像に置く行の数（「ほか M 件」の行を含む）。
            var total: Int { shown + (omitted > 0 ? 1 : 0) }
        }

        /// `count` 件の結果に対して置く行の内訳。上限に収まるなら全件、収まらなければ上限より 1 つ少ない件数を並べて残りをまとめる。
        /// 行を 1 つも置けない（`maxRows == 0`）ときは何も置かない。`total` は常に `maxRows` 以下。
        func rows(count: Int) -> Rows {
            let count = max(0, count)
            guard maxRows > 0 else { return Rows(shown: 0, omitted: 0) }
            guard count > maxRows else { return Rows(shown: count, omitted: 0) }
            let shown = max(0, maxRows - 1)
            return Rows(shown: shown, omitted: count - shown)
        }

        /// 行の束の高さ。
        func rowsHeight(total: Int) -> Double {
            guard total > 0 else { return 0 }
            return Double(total) * rowHeight + Double(total - 1) * rowSpacing
        }

        /// 行の束の上端。範囲の中で上下中央に置く。
        func rowsTop(count: Int) -> Double {
            let height = rowsHeight(total: rows(count: count).total)
            let available = contentRange.upperBound - contentRange.lowerBound
            return contentRange.lowerBound + max(0, available - height) / 2
        }

        /// 上から `index` 番目（0 始まり）の行の上端。
        func rowTop(index: Int, count: Int) -> Double {
            rowsTop(count: count) + Double(max(0, index)) * (rowHeight + rowSpacing)
        }
    }

    /// 一辺 `side` の順番決めの画像の寸法。
    static func order(side rawSide: Double) -> Order {
        let side = clamp(rawSide)
        let margin = margin(side: side)
        let range = contentRange(side: side)
        let rowHeight = side * orderRowHeightRatio
        let rowSpacing = side * orderRowSpacingRatio
        let available = range.upperBound - range.lowerBound
        let maxRows = rowHeight > 0 ? Int(((available + rowSpacing) / (rowHeight + rowSpacing)).rounded(.down)) : 0
        return Order(
            side: side,
            rowsLeft: margin,
            rowWidth: max(0, side - margin * 2),
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            fontSize: side * orderFontRatio,
            rowPadding: side * orderRowPaddingRatio,
            rankWidth: side * orderRankWidthRatio,
            rankGap: side * orderRankGapRatio,
            maxRows: max(0, maxRows),
            contentRange: range
        )
    }

    private static func clamp(_ side: Double) -> Double {
        side.isFinite ? max(0, side) : 0
    }
}
