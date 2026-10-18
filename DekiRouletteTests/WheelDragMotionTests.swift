import CoreGraphics
import Foundation
import Testing
@testable import DekiRoulette

extension WheelDragMotion {
    /// テスト用の盤面の中心と、指を動かす円の半径。
    static let testCenter = CGPoint(x: 160, y: 160)
    static let testRadius = 120.0

    /// 中心から `testRadius` の円周上で、向き `degrees`（画面上の時計回りが正）の指の位置。
    static func testLocation(_ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: Double(testCenter.x) + testRadius * cos(radians), y: Double(testCenter.y) + testRadius * sin(radians)
        )
    }

    /// 時刻 `start` から `duration` 秒、角速度 `velocity`（度/秒）で指を円周に沿って動かした記録。`rate` 回/秒で点を取る。
    static func testCircular(
        velocity: Double, start: TimeInterval = 10, duration: TimeInterval = 1, rate: Double = 120
    ) -> WheelDragMotion {
        var motion = WheelDragMotion(center: testCenter, time: start, location: testLocation(0), angle: 0)
        let steps = Int((duration * rate).rounded())
        for step in 1...steps {
            let elapsed = Double(step) / rate
            let angle = velocity * elapsed
            motion.append(time: start + elapsed, location: testLocation(angle), angle: angle)
        }
        return motion
    }
}

struct WheelDragMotionTests {
    private static let center = WheelDragMotion.testCenter

    private func location(_ degrees: Double) -> CGPoint {
        WheelDragMotion.testLocation(degrees)
    }

    private func drag(
        velocity: Double, start: TimeInterval = 10, duration: TimeInterval = 1, rate: Double = 120
    ) -> WheelDragMotion {
        WheelDragMotion.testCircular(velocity: velocity, start: start, duration: duration, rate: rate)
    }

    // MARK: 時計

    @Test func 指の時刻は演出の時計とのずれを足して直す() {
        // 演出の時計（起動からの秒）が 100 秒のとき、指の時計（2001 年からの秒）が 8 億秒
        let offset = WheelDragMotion.clockOffset(effectNow: 100, gestureNow: 800_000_000)
        #expect(abs((800_000_000.5 + offset) - 100.5) < 1e-6)
    }

    // MARK: 角速度

    @Test(arguments: [180.0, 720, -540])
    func 一定の速さで回すとその角速度になる(velocity: Double) {
        let motion = drag(velocity: velocity)
        let measured = motion.angularVelocity(now: motion.lastTime)
        #expect(abs(measured - velocity) < abs(velocity) * 0.01)
        #expect(abs(motion.intensity(now: motion.lastTime) - min(abs(velocity) / Config.effectFullIntensityVelocity, 1)) < 0.01)
    }

    @Test func 平滑する前の値は指を離したときのフリックの角速度と同じ() {
        let motion = drag(velocity: 400, duration: 0.4)
        let samples = motion.points.map { FlickSpin.Sample(time: $0.time, location: $0.location) }
        let release = FlickSpin.angularVelocity(samples: samples, center: Self.center)
        #expect(abs(motion.rawAngularVelocity(at: motion.lastTime) - release) < 1e-9)
    }

    @Test func 動き始めは平滑でなめらかに上がる() {
        // 止まったところから急に回し始めても、強さは平滑の時定数をかけて上がる（跳ねない）
        let motion = drag(velocity: 720, duration: 0.5)
        let early = motion.angularVelocity(now: 10 + 1.0 / 60)
        #expect(early > 0)
        #expect(early < 720 * 0.5)
        #expect(motion.angularVelocity(now: 10 + 0.4) > 720 * 0.95)
    }

    @Test func 点と点の間の揺れを平滑で抑える() {
        // 60 回/秒の点では、平滑する前の値は点と点の間で窓の分母が伸びて下がり、次の点で戻る（のこぎり状）
        let motion = drag(velocity: 600, duration: 1, rate: 60)
        let times = stride(from: 10.5, to: 10.9, by: 1.0 / 600).map { $0 }
        let raw = times.map { motion.rawAngularVelocity(at: $0) }
        let smooth = times.map { motion.angularVelocity(now: $0) }
        let rawSpread = (raw.max() ?? 0) - (raw.min() ?? 0)
        let smoothSpread = (smooth.max() ?? 0) - (smooth.min() ?? 0)
        #expect(rawSpread > 0)
        #expect(smoothSpread < rawSpread * 0.5)
    }

    @Test func 指を止めると0へ落ちて止まり切る() {
        let motion = drag(velocity: 720, duration: 0.5)
        let last = motion.lastTime
        #expect(motion.isMoving(now: last))
        // 窓を過ぎると平滑の残りだけになり、止まり切ったら 0
        #expect(abs(motion.angularVelocity(now: last + Config.flickSampleWindow + 0.2)) < 720 * 0.1)
        #expect(motion.angularVelocity(now: last + Config.dragEffectSettleTime) == 0)
        #expect(!motion.isMoving(now: last + Config.dragEffectSettleTime))
        #expect(abs(motion.remaining(now: last + 0.1) - (Config.dragEffectSettleTime - 0.1)) < 1e-9)
        #expect(motion.remaining(now: last + 10) == 0)
    }

    @Test func 止まり切ったあとに動かすと止まったところから寄せ直す() {
        var motion = drag(velocity: 720, duration: 0.5)
        let resume = motion.lastTime + Config.dragEffectSettleTime + 0.2
        motion.append(time: resume, location: location(400), angle: 400)
        // 前の点から間が空いたので、窓の中の点は 1 つで角速度は 0 から始まる
        #expect(motion.points.last?.velocity == 0)
    }

    @Test func 過ぎた時刻の値は後から点が増えても変わらない() {
        // 火花は生まれた時刻の強さで決めるので、後の点で前の値が変わると粒が出たり消えたりする
        let before = drag(velocity: 500, duration: 0.5)
        let after = drag(velocity: 500, duration: 0.8)
        for time in stride(from: 10.0, through: 10.5, by: 0.013) {
            #expect(abs(before.angularVelocity(now: time) - after.angularVelocity(now: time)) < 1e-9)
        }
    }

    @Test func 古い記録は捨てる() {
        let motion = drag(velocity: 300, duration: 3)
        #expect(motion.points[0].time >= motion.lastTime - Config.dragEffectHistory - 1e-9)
        // 捨てても直近の値は残る
        #expect(abs(motion.angularVelocity(now: motion.lastTime) - 300) < 3)
    }

    @Test func 中心付近を通る動きは回った角度に数えない() {
        // 中心を横切って反対側へ動かしても、盤面は回らず角速度も 0
        var motion = WheelDragMotion(center: Self.center, time: 0, location: CGPoint(x: 100, y: 160), angle: 0)
        motion.append(time: 0.05, location: CGPoint(x: 220, y: 160), angle: 0)
        #expect(motion.rawAngularVelocity(at: 0.05) == 0)
        #expect(motion.angularVelocity(now: 0.05) == 0)
    }

    // MARK: 角度

    @Test func 角度は点の間を線形に補う() {
        var motion = WheelDragMotion(center: Self.center, time: 1, location: location(0), angle: 0)
        motion.append(time: 1.1, location: location(10), angle: 10)
        #expect(abs(motion.angle(now: 1.05) - 5) < 1e-9)
        #expect(motion.angle(now: 0.5) == 0)
        #expect(motion.angle(now: 2) == 10)
    }

    // MARK: 演出が引く動き

    @Test func 自分で回っている間はその動き_それ以外は指で動かした動き() {
        let linear = CubicBezierCurve(0.33, 0.33, 0.67, 0.67)
        let spin = TimedSpinMotion(motion: SpinMotion(from: 0, to: 360, duration: 1, easing: linear), start: 10)
        let finger = drag(velocity: 300, start: 20, duration: 0.3)
        // 回っている間は動きを優先する
        #expect(WheelEffectMotion.current(spin: spin, drag: finger, now: 10.5) == .spin(spin))
        // 止まり切った動きより、指で動かした動きの残りを引く
        #expect(WheelEffectMotion.current(spin: spin, drag: finger, now: 20.3) == .drag(finger))
        // 指の動きも止まり切ったら、止まり切った動き（角度だけ）
        #expect(WheelEffectMotion.current(spin: spin, drag: finger, now: 30) == .spin(spin))
        #expect(WheelEffectMotion.current(spin: nil, drag: finger, now: 30) == nil)
        #expect(WheelEffectMotion.current(spin: nil, drag: nil, now: 0) == nil)
    }

    @Test func 指を離したあとに始まった惰性は止まり切っても指の動きの残りへ戻らない() {
        let linear = CubicBezierCurve(0.33, 0.33, 0.67, 0.67)
        let finger = drag(velocity: 300, start: 20, duration: 0.3)
        // 指を離した直後に始まった 0.1 秒の短い惰性
        let coast = TimedSpinMotion(motion: SpinMotion(from: 90, to: 92, duration: 0.1, easing: linear), start: finger.lastTime)
        #expect(WheelEffectMotion.current(spin: coast, drag: finger, now: finger.lastTime + 0.05) == .spin(coast))
        // 惰性が止まり切っても、指の動きの残り（0.5 秒）の間に指の動きへ戻らない
        #expect(finger.isMoving(now: finger.lastTime + 0.2))
        #expect(WheelEffectMotion.current(spin: coast, drag: finger, now: finger.lastTime + 0.2) == .spin(coast))
        // 惰性より後に指で動かしたら、指の動き
        let later = drag(velocity: 300, start: finger.lastTime + 1, duration: 0.3)
        #expect(WheelEffectMotion.current(spin: coast, drag: later, now: later.lastTime + 0.2) == .drag(later))
    }

    @Test func 止まり切ったと記録した動きは動いていないとみなす() {
        let linear = CubicBezierCurve(0.33, 0.33, 0.67, 0.67)
        let spin = WheelEffectMotion.spin(
            TimedSpinMotion(motion: SpinMotion(from: 0, to: 360, duration: 1, easing: linear), start: 10)
        )
        #expect(WheelEffectMotion.isMoving(spin, settled: nil, now: 10.5))
        #expect(!WheelEffectMotion.isMoving(spin, settled: spin, now: 10.5))
        #expect(!WheelEffectMotion.isMoving(spin, settled: nil, now: 11))
        #expect(!WheelEffectMotion.isMoving(nil, settled: nil, now: 10.5))
        // 別の動きを止まり切ったと記録していても、今の動きが動いていれば動いている
        let finger = WheelEffectMotion.drag(drag(velocity: 300, start: 10, duration: 0.3))
        #expect(WheelEffectMotion.isMoving(spin, settled: finger, now: 10.5))
    }

    @Test func 盤面に見えている角度() {
        let linear = CubicBezierCurve(0.33, 0.33, 0.67, 0.67)
        let spin = WheelEffectMotion.spin(
            TimedSpinMotion(motion: SpinMotion(from: 0, to: 360, duration: 1, easing: linear), start: 0)
        )
        #expect(abs(spin.displayedAngle(now: 0.5, rotation: 360, dragRotation: 0) - spin.angle(now: 0.5)) < 1e-9)
        // 指で動かしている間は盤面と同じ rotation + dragRotation
        let finger = WheelEffectMotion.drag(drag(velocity: 300, duration: 0.3))
        #expect(finger.displayedAngle(now: 10.3, rotation: 40, dragRotation: 90) == 130)
        #expect(finger.isMoving(now: 10.3))
        #expect(finger.intensity(now: 10.3) > 0)
    }
}
