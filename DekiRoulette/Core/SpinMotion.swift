import Foundation

/// 盤面が `from` から `to` へ `duration` 秒で `easing` に沿って回る動き（スピン・惰性のどちらにも使う）。
/// 補間は `withAnimation` に任せていて途中の角度は observable でないので、速さに連動する演出は `TimelineView` で
/// 毎フレーム、開始からの経過時間でこの動きから角度と角速度を引く（回転音・触覚の時刻の逆算と同じ曲線を使う）。
/// 項目・指定・印は持たない（角度と曲線だけ）。
struct SpinMotion: Hashable, Sendable {
    /// 回り始めの累積回転角（度）。
    var from: Double
    /// 止まる累積回転角（度）。`to < from` なら反時計回り。
    var to: Double
    /// 補間の長さ（秒）。
    var duration: TimeInterval
    /// 補間の曲線。`Theme.spinAnimation(easing:duration:)` に渡すものと同じ。
    var easing: CubicBezierCurve

    /// 開始から `elapsed` 秒後の累積回転角（度）。始まる前（0 未満）は `from`、長さを過ぎたら `to` で止める。
    func angle(at elapsed: TimeInterval) -> Double {
        guard duration > 0 else { return to }
        if elapsed <= 0 { return from }
        if elapsed >= duration { return to }
        return from + (to - from) * easing.progress(atTime: elapsed / duration)
    }

    /// 開始から `elapsed` 秒後の角速度（度/秒、累積回転角が増える向き＝画面上の時計回りが正）。
    /// 始まる前（0 未満）と長さを過ぎたあとは 0（止まっている）。0...duration の中は曲線の傾き × 平均の速さ。
    func angularVelocity(at elapsed: TimeInterval) -> Double {
        guard duration > 0, elapsed >= 0, elapsed <= duration else { return 0 }
        return (to - from) / duration * easing.slope(atTime: elapsed / duration)
    }

    /// 開始から `elapsed` 秒後の演出の強さ（0...1）。`SpinEffectIntensity.intensity(angularVelocity:)` に角速度を渡したもの。
    func intensity(at elapsed: TimeInterval) -> Double {
        SpinEffectIntensity.intensity(angularVelocity: angularVelocity(at: elapsed))
    }
}

extension FlickCoast.Coast {
    /// 累積回転角 `from` から始める惰性の動き。
    func motion(from: Double) -> SpinMotion {
        SpinMotion(from: from, to: from + distance, duration: duration, easing: easing)
    }
}

/// 速さに連動する演出（電飾の流れ・光の尾・残像・火花・背景の光）の強さ。各演出はこの 0...1 の値だけを見る。
enum SpinEffectIntensity {
    /// 角速度（度/秒、向きに依らない）を 0...1 の強さに写す。`Config.effectFullIntensityVelocity` 以上で 1、止まっていれば 0 で、間は比例。
    static func intensity(angularVelocity: Double) -> Double {
        guard !angularVelocity.isNaN else { return 0 }
        return min(abs(angularVelocity) / Config.effectFullIntensityVelocity, 1)
    }

    /// 演出用に値（ドラッグ中の角速度・強さ）を滑らかにする。前のフレームの値 `current` を、新しい値 `target` へ
    /// `elapsed` 秒ぶん指数で寄せる（時定数 `timeConstant` 秒。フレームの間隔が揺れても同じ速さで追いつく）。
    /// `elapsed` が 0 以下なら `current` のまま、時定数が 0 以下なら `target` に飛ぶ。
    static func smoothed(
        _ current: Double, toward target: Double, elapsed: TimeInterval,
        timeConstant: TimeInterval = Config.effectSmoothingTime
    ) -> Double {
        guard elapsed > 0 else { return current }
        guard timeConstant > 0 else { return target }
        let weight = 1 - exp(-elapsed / timeConstant)
        return current + (target - current) * weight
    }
}

/// 盤面が自分で回る動き（スピン・惰性）と、その開始時刻（`RouletteModel.now()` の時計の秒）。
/// 動きは区間をつないだ `SpinPath`（焦らしの無いスピンと惰性は区間 1 つ）。
/// 演出は `TimelineView` の毎フレームで、同じ時計の今の時刻（`now`）を渡して角度・強さ・動いているかを引く。
struct TimedSpinMotion: Equatable, Sendable {
    let path: SpinPath
    let start: TimeInterval

    init(path: SpinPath, start: TimeInterval) {
        self.path = path
        self.start = start
    }

    /// 区間 1 つの動き。
    init(motion: SpinMotion, start: TimeInterval) {
        self.init(path: SpinPath(motion), start: start)
    }

    /// 時刻 `now` の累積回転角（度）。始まる前は `from`、終わったあとは `to`。
    func angle(now: TimeInterval) -> Double {
        path.angle(at: now - start)
    }

    /// 時刻 `now` の角速度（度/秒、累積回転角が増える向きが正）。止まり切ったあとは 0。
    func angularVelocity(now: TimeInterval) -> Double {
        path.angularVelocity(at: now - start)
    }

    /// 時刻 `now` の演出の強さ（0...1）。止まり切ったあとは 0。
    func intensity(now: TimeInterval) -> Double {
        path.intensity(at: now - start)
    }

    /// 時刻 `now` に盤面がまだ動いているか（開始から長さまでの間）。惰性は止まり切っても次の操作まで
    /// `currentMotion` に残るので、長さを過ぎたら止まっているとみなして毎フレームの描き直しを止める。
    func isMoving(now: TimeInterval) -> Bool {
        let elapsed = now - start
        return path.duration > 0 && elapsed >= 0 && elapsed < path.duration
    }

    /// 時刻 `now` から止まり切るまでの残りの秒。止まっていれば 0。
    func remaining(now: TimeInterval) -> TimeInterval {
        max(path.duration - (now - start), 0)
    }
}
