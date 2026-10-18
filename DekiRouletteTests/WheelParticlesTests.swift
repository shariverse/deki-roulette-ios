import CoreGraphics
import Foundation
import Testing
@testable import DekiRoulette

struct WheelParticlesTests {
    /// 等速の曲線（制御点が対角線上にあるので進み具合 = 時刻の割合）。
    private static let linear = CubicBezierCurve(0.33, 0.33, 0.67, 0.67)
    private static let origin = CGPoint(x: 160, y: 20)

    /// 角速度 `velocity`（度/秒、負なら反時計回り）で 10 秒間等速に回る動き。時刻 0 に始める。
    private func steady(_ velocity: Double) -> TimedSpinMotion {
        TimedSpinMotion(motion: SpinMotion(from: 0, to: velocity * 10, duration: 10, easing: Self.linear), start: 0)
    }

    private func velocity(intensity: Double) -> Double {
        Config.effectFullIntensityVelocity * intensity
    }

    private func sparks(
        _ motion: TimedSpinMotion?, now: TimeInterval = 5, seed: UInt64 = 42, lowPower: Bool = false, reduceMotion: Bool = false
    ) -> [WheelParticles.Spark] {
        WheelParticles.sparks(
            motion: motion, now: now, seed: seed, origin: Self.origin, scale: 1, lowPower: lowPower, reduceMotion: reduceMotion
        )
    }

    private func confetti(
        elapsed: TimeInterval, seed: UInt64 = 7, lowPower: Bool = false, reduceMotion: Bool = false
    ) -> [WheelParticles.Confetto] {
        WheelParticles.confetti(
            elapsed: elapsed, seed: seed, side: 320, colorCount: Theme.confettiColors.count,
            lowPower: lowPower, reduceMotion: reduceMotion
        )
    }

    // MARK: 火花

    @Test func 火花の上限は60で低電力モードでは3分の1() {
        #expect(WheelParticles.sparkCapacity(lowPower: false) == 60)
        #expect(WheelParticles.sparkCapacity(lowPower: true) == 20)
    }

    @Test(arguments: [false, true])
    func 最高速でも同時に出る火花は上限まで(lowPower: Bool) {
        let motion = steady(velocity(intensity: 1) * 3)
        for step in 0..<40 {
            let now = 0.5 + Double(step) * 0.1
            #expect(sparks(motion, now: now, lowPower: lowPower).count <= WheelParticles.sparkCapacity(lowPower: lowPower))
        }
        // 強さ 1 では生まれうる時刻ごとに 1 粒生まれるので、寿命の短い粒が消えた分を除いて上限に近い
        #expect(sparks(motion, lowPower: lowPower).count >= WheelParticles.sparkCapacity(lowPower: lowPower) / 2)
    }

    @Test func 火花の数は強さに比例する() {
        // 時刻をずらして平均を取る（粒ごとに乱数で生まれるので 1 フレームでは揺れる）
        func average(_ intensity: Double) -> Double {
            let motion = steady(velocity(intensity: intensity))
            let counts = (0..<50).map { sparks(motion, now: 1 + Double($0) * 0.17).count }
            return Double(counts.reduce(0, +)) / Double(counts.count)
        }
        let full = average(1)
        let half = average(0.5)
        let quarter = average(0.25)
        #expect(full > 0)
        #expect(abs(half / full - 0.5) < 0.12)
        #expect(abs(quarter / full - 0.25) < 0.1)
    }

    @Test func 止まっていると火花は出ない() {
        #expect(sparks(steady(0)).isEmpty)
        #expect(sparks(nil).isEmpty)
        // 始まる前と、止まり切ってから寿命が過ぎたあと
        #expect(sparks(steady(velocity(intensity: 1)), now: -1).isEmpty)
        #expect(sparks(steady(velocity(intensity: 1)), now: 10 + Config.wheelSparkLifetime).isEmpty)
    }

    @Test func 動きを減らす設定では火花を出さない() {
        #expect(sparks(steady(velocity(intensity: 1)), reduceMotion: true).isEmpty)
    }

    @Test func 同じ種と時刻なら同じ火花() {
        let motion = steady(velocity(intensity: 0.7))
        #expect(sparks(motion, seed: 3) == sparks(motion, seed: 3))
        #expect(sparks(motion, seed: 3) != sparks(motion, seed: 4))
    }

    @Test func 火花は回転の向きへ飛ぶ() {
        let clockwise = sparks(steady(velocity(intensity: 1)))
        let counter = sparks(steady(-velocity(intensity: 1)))
        #expect(!clockwise.isEmpty && !counter.isEmpty)
        // 時計回りなら針の下の表面は右へ動くので右へ、反時計回りなら左へ
        #expect(clockwise.allSatisfy { $0.position.x >= Self.origin.x })
        #expect(counter.allSatisfy { $0.position.x <= Self.origin.x })
    }

    @Test func 火花は寿命の終わりへ向けて薄くなる() throws {
        var early = SeededGenerator(seed: 1)
        var late = SeededGenerator(seed: 1)
        let young = try #require(WheelParticles.spark(
            age: 0.01, intensity: 1, velocity: 720, origin: Self.origin, scale: 1, using: &early
        ))
        let old = try #require(WheelParticles.spark(
            age: Config.wheelSparkLifetime * WheelParticles.sparkMinLifeFraction * 0.9, intensity: 1, velocity: 720,
            origin: Self.origin, scale: 1, using: &late
        ))
        #expect(young.opacity > old.opacity)
        #expect(old.opacity > 0)
        // 寿命を過ぎたら消える
        var gone = SeededGenerator(seed: 1)
        #expect(WheelParticles.spark(
            age: Config.wheelSparkLifetime, intensity: 1, velocity: 720, origin: Self.origin, scale: 1, using: &gone
        ) == nil)
    }

    @Test func 強さ0の時刻には生まれない() {
        var random = SeededGenerator(seed: 9)
        for _ in 0..<100 {
            #expect(WheelParticles.spark(age: 0.1, intensity: 0, velocity: 0, origin: Self.origin, scale: 1, using: &random) == nil)
        }
    }

    // MARK: 紙吹雪

    @Test func 紙吹雪の上限は80で低電力モードでは3分の1() {
        #expect(WheelParticles.confettiCapacity(lowPower: false) == 80)
        #expect(WheelParticles.confettiCapacity(lowPower: true) == 26)
        #expect(confetti(elapsed: 0.01).count == 80)
        #expect(confetti(elapsed: 0.01, lowPower: true).count == 26)
    }

    @Test func 紙吹雪は約1_6秒で消える() {
        #expect(!confetti(elapsed: 1).isEmpty)
        #expect(confetti(elapsed: Config.wheelConfettiDuration).isEmpty)
        #expect(confetti(elapsed: 5).isEmpty)
        #expect(confetti(elapsed: -0.1).isEmpty)
        // 消える間際は薄い
        let late = confetti(elapsed: Config.wheelConfettiDuration - 0.01)
        #expect(late.allSatisfy { $0.opacity < 0.1 })
    }

    @Test func 紙吹雪ははじけて上がってから落ちる() {
        let start = confetti(elapsed: 0)
        let rising = confetti(elapsed: 0.3)
        let falling = confetti(elapsed: 1.4)
        func meanY(_ pieces: [WheelParticles.Confetto]) -> Double {
            pieces.map { Double($0.position.y) }.reduce(0, +) / Double(max(pieces.count, 1))
        }
        #expect(meanY(rising) < meanY(start))
        #expect(meanY(falling) > meanY(rising))
    }

    @Test func 紙吹雪は盤面の枠の中に収まる() {
        for step in 0..<16 {
            for piece in confetti(elapsed: Double(step) * 0.1) {
                #expect(piece.position.x > -10 && piece.position.x < 330)
                #expect(piece.position.y > -10 && piece.position.y < 330)
            }
        }
    }

    @Test func 紙吹雪の色はスライスの10色から() {
        let pieces = confetti(elapsed: 0.2)
        #expect(pieces.allSatisfy { (0..<Theme.confettiColors.count).contains($0.colorIndex) })
        #expect(Set(pieces.map(\.colorIndex)).count > 5)
    }

    @Test func 動きを減らす設定では紙吹雪を出さない() {
        #expect(confetti(elapsed: 0.2, reduceMotion: true).isEmpty)
    }

    @Test func 同じ種と時刻なら同じ紙吹雪() {
        #expect(confetti(elapsed: 0.5, seed: 11) == confetti(elapsed: 0.5, seed: 11))
        #expect(confetti(elapsed: 0.5, seed: 11) != confetti(elapsed: 0.5, seed: 12))
    }

    // MARK: 共通

    @Test func 種は注入した乱数から引く() {
        var a = SeededGenerator(seed: 5)
        var b = SeededGenerator(seed: 5)
        #expect(WheelParticles.seed(using: &a) == WheelParticles.seed(using: &b))
    }

    @Test func 描き直すのは回っている間か紙吹雪が出ている間だけ() {
        #expect(WheelParticles.animates(reduceMotion: false, moving: true, bursting: false))
        #expect(WheelParticles.animates(reduceMotion: false, moving: false, bursting: true))
        #expect(!WheelParticles.animates(reduceMotion: false, moving: false, bursting: false))
        #expect(!WheelParticles.animates(reduceMotion: true, moving: true, bursting: true))
    }
}
