import Foundation
import Testing
@testable import DekiRoulette

struct SpinMotionTests {
    /// ボタンのスピン（時計回りに 6 周と 90 度）。
    private let spin = SpinMotion(from: 30, to: 30 + 360 * 6 + 90, duration: Config.spinDuration, easing: Config.spinEasing)

    /// 中央差分で求めた角速度。
    private func numericVelocity(_ motion: SpinMotion, at elapsed: TimeInterval, step: TimeInterval = 1e-5) -> Double {
        (motion.angle(at: elapsed + step) - motion.angle(at: elapsed - step)) / (2 * step)
    }

    // MARK: 角度

    @Test func 始点と終点の角度() {
        #expect(abs(spin.angle(at: 0) - spin.from) < 1e-9)
        #expect(abs(spin.angle(at: spin.duration) - spin.to) < 1e-9)
    }

    @Test func 範囲外の時刻は端で止める() {
        #expect(abs(spin.angle(at: -1) - spin.from) < 1e-9)
        #expect(abs(spin.angle(at: spin.duration + 1) - spin.to) < 1e-9)
    }

    @Test func 角度は曲線の進み具合どおり() {
        for step in 1..<20 {
            let elapsed = spin.duration * Double(step) / 20
            let expected = spin.from + (spin.to - spin.from) * Config.spinEasing.progress(atTime: Double(step) / 20)
            #expect(abs(spin.angle(at: elapsed) - expected) < 1e-9)
        }
    }

    @Test func 時計回りの角度は単調に増える() {
        var previous = -Double.infinity
        for step in 0...200 {
            let angle = spin.angle(at: spin.duration * Double(step) / 200)
            #expect(angle >= previous)
            previous = angle
        }
    }

    @Test func 反時計回りの角度は単調に減る() {
        let counter = SpinMotion(from: 30, to: 30 - 360 * 5 - 45, duration: Config.spinDuration, easing: Config.spinEasing)
        #expect(abs(counter.angle(at: 0) - 30) < 1e-9)
        #expect(abs(counter.angle(at: counter.duration) - counter.to) < 1e-9)
        var previous = Double.infinity
        for step in 0...200 {
            let angle = counter.angle(at: counter.duration * Double(step) / 200)
            #expect(angle <= previous)
            previous = angle
        }
    }

    @Test func 長さが0なら終点() {
        let instant = SpinMotion(from: 10, to: 100, duration: 0, easing: Config.spinEasing)
        #expect(abs(instant.angle(at: 0) - 100) < 1e-9)
        #expect(abs(instant.angularVelocity(at: 0)) < 1e-9)
    }

    // MARK: 角速度

    @Test func 角速度は角度の数値微分と一致する() {
        let counter = SpinMotion(from: 0, to: -1500, duration: Config.spinDuration, easing: Config.spinEasing)
        for motion in [spin, counter] {
            for step in 1..<40 {
                let elapsed = motion.duration * Double(step) / 40
                let analytic = motion.angularVelocity(at: elapsed)
                let numeric = numericVelocity(motion, at: elapsed)
                #expect(abs(analytic - numeric) < 1e-3 * max(abs(analytic), 1))
            }
        }
    }

    @Test func 時計回りは正で反時計回りは負() {
        let counter = SpinMotion(from: 0, to: -1500, duration: Config.spinDuration, easing: Config.spinEasing)
        for step in 0..<20 {
            let elapsed = Config.spinDuration * Double(step) / 20
            #expect(spin.angularVelocity(at: elapsed) > 0)
            #expect(counter.angularVelocity(at: elapsed) < 0)
        }
    }

    @Test func スピンの曲線は始めが最も速く止まり際に0へ落ちる() {
        let start = spin.angularVelocity(at: 0)
        // 始点の傾き y1 / x1 × 平均の速さ
        let expected = Config.spinEasing.y1 / Config.spinEasing.x1 * (spin.to - spin.from) / spin.duration
        #expect(abs(start - expected) < 1e-6)
        var previous = Double.infinity
        for step in 0...100 {
            let velocity = spin.angularVelocity(at: spin.duration * Double(step) / 100)
            #expect(velocity <= previous + 1e-9)
            previous = velocity
        }
        #expect(abs(spin.angularVelocity(at: spin.duration)) < 1e-6)
    }

    @Test func 範囲外の時刻の角速度は0() {
        #expect(spin.angularVelocity(at: -0.01) == 0)
        #expect(spin.angularVelocity(at: spin.duration + 0.01) == 0)
    }

    @Test func フリックの曲線は初速が離した角速度と一致する() {
        let flicks: [(velocity: Double, distance: Double)] = [(900, 360 * 5 + 120), (1500, 360 * 6 + 90), (-1200, 360 * 7 + 10)]
        for (velocity, distance) in flicks {
            let easing = FlickSpin.easing(angularVelocity: velocity, distance: distance, duration: Config.spinDuration)
            let to = velocity > 0 ? 40 + distance : 40 - distance
            let motion = SpinMotion(from: 40, to: to, duration: Config.spinDuration, easing: easing)
            #expect(abs(motion.angularVelocity(at: 0) - velocity) < 1e-6)
            // 動き始めの短い間の平均の速さも離した速さに近い
            let instant = 0.001
            let early = (motion.angle(at: instant) - motion.from) / instant
            #expect(abs(early - velocity) / abs(velocity) < 0.02)
            // 止まる位置と長さは変わらない
            #expect(abs(motion.angle(at: Config.spinDuration) - to) < 1e-9)
        }
    }

    @Test func 惰性の初速は離した角速度と一致し止まると0() throws {
        for velocity in [30.0, 120, -200, 239] {
            let coast = try #require(FlickCoast.coast(angularVelocity: velocity))
            let motion = coast.motion(from: 15)
            #expect(abs(motion.to - (15 + coast.distance)) < 1e-9)
            #expect(abs(motion.duration - coast.duration) < 1e-9)
            #expect(abs(motion.angularVelocity(at: 0) - velocity) < 1e-6)
            #expect(abs(motion.angularVelocity(at: coast.duration)) < 1e-6)
            // 途中の角度は `FlickCoast.Coast.angle(after:)` と同じ
            for step in 0...10 {
                let elapsed = coast.duration * Double(step) / 10
                #expect(abs(motion.angle(at: elapsed) - (15 + coast.angle(after: elapsed))) < 1e-9)
                let numeric = numericVelocity(motion, at: elapsed, step: 1e-6)
                if step > 0, step < 10 {
                    #expect(abs(motion.angularVelocity(at: elapsed) - numeric) < 1e-3 * abs(velocity))
                }
            }
        }
    }

    // MARK: 強さ

    @Test func 強さは止まっていれば0で既定の角速度以上で1() {
        #expect(SpinEffectIntensity.intensity(angularVelocity: 0) == 0)
        #expect(SpinEffectIntensity.intensity(angularVelocity: Config.effectFullIntensityVelocity) == 1)
        #expect(SpinEffectIntensity.intensity(angularVelocity: 5000) == 1)
        #expect(SpinEffectIntensity.intensity(angularVelocity: -5000) == 1)
        #expect(SpinEffectIntensity.intensity(angularVelocity: .infinity) == 1)
        #expect(SpinEffectIntensity.intensity(angularVelocity: .nan) == 0)
    }

    @Test func 強さは途中では角速度に比例し向きに依らない() {
        #expect(abs(Config.effectFullIntensityVelocity - 720) < 1e-9)
        #expect(abs(SpinEffectIntensity.intensity(angularVelocity: 360) - 0.5) < 1e-9)
        #expect(abs(SpinEffectIntensity.intensity(angularVelocity: -180) - 0.25) < 1e-9)
    }

    @Test func スピンの強さは回り始めが1で止まると0() {
        #expect(spin.intensity(at: 0) == 1)
        #expect(spin.intensity(at: spin.duration) < 1e-6)
        #expect(spin.intensity(at: spin.duration + 1) == 0)
        let middle = spin.intensity(at: spin.duration * 0.6)
        #expect(middle > 0)
        #expect(middle < 1)
    }

    // MARK: 平滑

    @Test func 平滑は経過時間に応じて新しい値へ寄せる() {
        let tau = Config.effectSmoothingTime
        #expect(SpinEffectIntensity.smoothed(0, toward: 100, elapsed: 0) == 0)
        #expect(SpinEffectIntensity.smoothed(0, toward: 100, elapsed: 1, timeConstant: 0) == 100)
        // 時定数ぶんで 1 - 1/e だけ寄る
        let oneTau = SpinEffectIntensity.smoothed(0, toward: 100, elapsed: tau)
        #expect(abs(oneTau - 100 * (1 - exp(-1))) < 1e-9)
        // 十分に経てば新しい値に追いつく
        #expect(abs(SpinEffectIntensity.smoothed(0, toward: 100, elapsed: tau * 40) - 100) < 1e-9)
        // 下げる向きも同じ
        #expect(abs(SpinEffectIntensity.smoothed(100, toward: 0, elapsed: tau) - 100 * exp(-1)) < 1e-9)
    }

    @Test func 平滑はフレームの刻みに依らない() {
        let tau = Config.effectSmoothingTime
        var fine = 0.0
        for _ in 0..<4 { fine = SpinEffectIntensity.smoothed(fine, toward: 1, elapsed: tau / 4) }
        let coarse = SpinEffectIntensity.smoothed(0, toward: 1, elapsed: tau)
        #expect(abs(fine - coarse) < 1e-9)
    }

    // MARK: 開始時刻つきの動き

    @Test func 開始時刻つきの動きは今の時刻から経過時間を引いて引く() {
        let timed = TimedSpinMotion(motion: spin, start: 100)
        #expect(abs(timed.angle(now: 100) - spin.from) < 1e-9)
        #expect(abs(timed.angle(now: 102) - spin.angle(at: 2)) < 1e-9)
        #expect(abs(timed.angle(now: 100 + spin.duration + 5) - spin.to) < 1e-9)
        #expect(abs(timed.intensity(now: 101) - spin.intensity(at: 1)) < 1e-9)
    }

    @Test func 長さを過ぎたら止まっているとみなす() {
        let timed = TimedSpinMotion(motion: spin, start: 100)
        #expect(!timed.isMoving(now: 99.9))
        #expect(timed.isMoving(now: 100))
        #expect(timed.isMoving(now: 100 + spin.duration - 0.01))
        #expect(!timed.isMoving(now: 100 + spin.duration))
        #expect(!timed.isMoving(now: 100 + spin.duration + 10))
        // 止まり切った惰性は角速度も強さも 0
        #expect(timed.intensity(now: 100 + spin.duration + 10) == 0)
    }

    @Test func 止まり切るまでの残り() {
        let timed = TimedSpinMotion(motion: spin, start: 100)
        #expect(abs(timed.remaining(now: 101) - (spin.duration - 1)) < 1e-9)
        #expect(timed.remaining(now: 100 + spin.duration + 1) == 0)
    }

    @Test func 長さが0の動きは動いていない() {
        let instant = TimedSpinMotion(motion: SpinMotion(from: 0, to: 90, duration: 0, easing: Config.spinEasing), start: 0)
        #expect(!instant.isMoving(now: 0))
    }
}
