import Foundation

/// 結果が出ている間、盤面の中心より下に重ねる帯の寸法。盤面と同じく Dynamic Type には追従させず、直径に比例させる。
///
/// 帯の中心は盤面の中心から半径 × `centerOffsetRatio` だけ下に置く。中心のハブ（直径 `baseHubDiameter`）とは重ねず、
/// 帯（カプセル）は盤面のスライスの円（半径は外枠から `baseSliceInset` 内側）に収める。2D と 3D で同じ寸法を使う。
enum ResultBand {
    /// 基準の直径での文字サイズ（pt）。盤面のラベル（最大 15pt）より大きくして結果を読ませる。
    static let baseFontSize: Double = 28
    /// 収まらないときに縮める下限の倍率。それでも収まらなければ末尾を省略する。
    static let minimumScaleFactor: Double = 0.5
    /// 帯の幅の上限（直径に対する割合）。
    static let maxWidthRatio: Double = 0.72
    /// 帯の中心を盤面の中心から下げる距離（半径に対する割合）。
    static let centerOffsetRatio: Double = 0.4
    /// 文字の左右・上下の余白（基準の直径での pt）。
    static let baseHorizontalPadding: Double = 14
    static let baseVerticalPadding: Double = 5
    /// 1 行の高さの見積もり（文字サイズに対する割合）。ハブ・円との重なりの確認に使う。
    static let lineHeightRatio: Double = 1.2
    /// 中心のハブの直径（基準の直径での pt）。`RouletteWheelView` のハブと同じ。
    static let baseHubDiameter: Double = 38
    /// 盤面の外枠からスライスの円までの距離（基準の直径での pt）。`RouletteWheelView` と同じ（`WheelGeometry.sliceInset`）。
    static let baseSliceInset: Double = WheelGeometry.sliceInset

    // MARK: 登場演出（停止の演出が ON のとき）

    /// 帯が現れ始める大きさ（倍率）。ここからばね（`popInDuration` / `popInBounce`）で少し行き過ぎて 1 に収まる。
    static let popInStartScale: Double = 0.6
    /// 登場のばねの長さ（秒）と弾み（SwiftUI の `Animation.spring(duration:bounce:)` の値）。
    static let popInDuration: Double = 0.45
    static let popInBounce: Double = 0.35

    /// 登場のばねがいちばん行き過ぎたときの大きさ（倍率）。弾み b のばねの減衰比は 1 - b で、行き過ぎは
    /// 動く幅 × e^(-ζπ/√(1-ζ²))。帯がこの大きさでもスライスの円からはみ出さないことをテストで確かめる。
    static var popInPeakScale: Double {
        let damping = 1 - popInBounce
        guard damping < 1 else { return 1 }
        let overshoot = exp(-damping * .pi / (1 - damping * damping).squareRoot())
        return 1 + (1 - popInStartScale) * overshoot
    }

    private static func ratio(_ diameter: Double) -> Double {
        max(0, diameter) / WheelLabel.referenceDiameter
    }

    /// 文字サイズ（pt）。
    static func fontSize(diameter: Double) -> Double {
        baseFontSize * ratio(diameter)
    }

    /// 帯の幅の上限（pt）。
    static func maxWidth(diameter: Double) -> Double {
        max(0, diameter) * maxWidthRatio
    }

    /// 文字の左右の余白（pt）。
    static func horizontalPadding(diameter: Double) -> Double {
        baseHorizontalPadding * ratio(diameter)
    }

    /// 文字の上下の余白（pt）。
    static func verticalPadding(diameter: Double) -> Double {
        baseVerticalPadding * ratio(diameter)
    }

    /// 帯の高さの見積もり（pt）。1 行の文字の高さ + 上下の余白。
    static func height(diameter: Double) -> Double {
        fontSize(diameter: diameter) * lineHeightRatio + verticalPadding(diameter: diameter) * 2
    }

    /// 盤面の中心から帯の中心までの距離（pt、下向き）。
    static func centerOffset(diameter: Double) -> Double {
        max(0, diameter) / 2 * centerOffsetRatio
    }

    /// 中心のハブの半径（pt）。
    static func hubRadius(diameter: Double) -> Double {
        baseHubDiameter / 2 * ratio(diameter)
    }

    /// スライスの円の半径（pt）。
    static func sliceRadius(diameter: Double) -> Double {
        max(0, max(0, diameter) / 2 - baseSliceInset * ratio(diameter))
    }
}
