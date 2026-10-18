import Foundation

/// 勢いの足りないフリック（`FlickSpin.spin` が nil）で指を離したあと、盤面が少しだけ惰性で回って止まる動き。抽選はしない。
/// 盤面は離した瞬間の角速度で回り出し、一定の割合で減速して止まる（等減速。曲線は 2 次の ease-out）。
enum FlickCoast {
    /// 惰性の動き。`distance` は回る角度（度、画面上の時計回りが正）、`duration` は止まるまでの時間（秒）。
    /// `easing` は `Theme.spinAnimation(easing:duration:)` の補間と、途中の角度の逆算（`angle(after:)`）が共有する。
    struct Coast: Equatable {
        var distance: Double
        var duration: TimeInterval
        var easing: CubicBezierCurve

        /// 動き始めてから `elapsed` 秒後に回った角度（度、`distance` と同じ符号）。`duration` を過ぎたら `distance`。
        func angle(after elapsed: TimeInterval) -> Double {
            guard duration > 0 else { return distance }
            return distance * easing.progress(atTime: elapsed / duration)
        }
    }

    /// 2 次の ease-out `1 − (1 − t)²` を 3 次ベジェに上げた曲線。始点の傾き `y1 / x1` が 2 なので、
    /// 初速は平均の速さ `distance / duration` の 2 倍になり、終点で速さが 0 になる。
    static let easing = CubicBezierCurve(1.0 / 3, 2.0 / 3, 2.0 / 3, 1)

    /// 指を離した瞬間の角速度（度/秒、時計回りが正）から惰性の動きを決める。向きは角速度の符号。
    /// 回る角度は角速度 × `Config.flickCoastFactor` を `Config.flickCoastMaxAngle` で抑えたもので、
    /// 時間は初速が離した角速度になるよう `2 × 角度 ÷ 角速度` にする（等減速）。
    /// 回る角度が `Config.flickCoastMinAngle` 未満（止めてから離した）なら nil（惰性を付けず、離した角度のまま止める）。
    static func coast(angularVelocity: Double) -> Coast? {
        let speed = abs(angularVelocity)
        let distance = min(speed * Config.flickCoastFactor, Config.flickCoastMaxAngle)
        guard distance >= Config.flickCoastMinAngle, speed > 0 else { return nil }
        return Coast(
            distance: angularVelocity > 0 ? distance : -distance,
            duration: 2 * distance / speed,
            easing: easing
        )
    }
}
