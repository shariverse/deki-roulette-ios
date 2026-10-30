import CoreGraphics
import Foundation

/// スピン中にページを暗くする幕（SPEC §5.2）の判定と、盤面の位置に抜く穴の幾何。
/// 幕はページ全体に 1 枚だけ重ね、盤面の枠の内接円だけを抜く。指定・印は受け取らない（暗転の出方は指定の有無で変えない）。
enum SpinSpotlight {
    /// 幕に抜く穴。中心から `radius` までは幕を掛けず、そこから `radius + feather` までで幕の濃さに戻す。
    struct Hole: Equatable {
        let center: CGPoint
        let radius: CGFloat
        let feather: CGFloat

        /// 幕を掛け切る半径。
        var outerRadius: CGFloat { radius + feather }
    }

    /// 幕の不透明度。抽選したスピンの間（`spinning`）だけ掛け、止まった瞬間に戻す。
    /// 指で動かしている間・閾値未満で離したあとの惰性・結果表示中・待機中は `spinning` が立たないので掛からない。
    static func opacity(spinning: Bool) -> Double {
        spinning ? 1 : 0
    }

    /// 盤面の枠 `frame`（幕と同じ座標）に抜く穴。盤面の描画（`WheelFaceView`・`WheelDragArea`）と同じく、
    /// 枠の中央を中心に `min(width, height)` を直径とする内接円を抜き、縁は外へ `Config.spinSpotlightFeatherRatio` × 直径だけぼかす。
    /// 3D の盤が傾いて枠の外へはみ出す分（`overscan`）は含めない。大きさの無い枠では nil（穴を抜かない）。
    static func hole(in frame: CGRect) -> Hole? {
        let side = min(frame.width, frame.height)
        guard side > 0, side.isFinite else { return nil }
        return Hole(
            center: CGPoint(x: frame.midX, y: frame.midY),
            radius: side / 2,
            feather: side * Config.spinSpotlightFeatherRatio
        )
    }

    /// 画面の座標（`.global`）で伝えた盤面の枠 `frame` に抜く穴を、原点が `layerOrigin`（画面の座標）の幕の座標で返す。
    /// 幕はナビゲーションバー・安全領域まで覆うよう `NavigationStack` の外に重ね、盤面はその中のスクロールする本文にあるので、
    /// 同じ画面の座標で測って幕の原点を引く（スクロールしても穴が盤面に付いていく）。
    static func hole(inGlobal frame: CGRect, layerOrigin: CGPoint) -> Hole? {
        hole(in: frame.offsetBy(dx: -layerOrigin.x, dy: -layerOrigin.y))
    }

    /// 幕の範囲 `rect` に対する穴の中心の位置（左上 0・右下 1 の割合。`UnitPoint` に使う）。
    /// 幕は放射状のグラデーション 1 枚で塗るので、グラデーションの中心を穴の中心に合わせる。範囲の大きさが無ければ中央。
    static func unitCenter(of hole: Hole, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: (hole.center.x - rect.minX) / rect.width, y: (hole.center.y - rect.minY) / rect.height)
    }
}
