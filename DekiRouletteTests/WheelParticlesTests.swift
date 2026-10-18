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

    // MARK: 焦らしの動き（区間の列）

    @Test func 区間の列では全体の長さまで生まれうる() {
        // 主の区間（4.5 秒）のあとの区間も速ければ火花が出る（焦らしの 5.7 秒まで生まれうる時刻がある）
        let path = SpinPath(segments: [
            SpinMotion(from: 0, to: 4.5 * velocity(intensity: 1), duration: Config.spinDuration, easing: Self.linear),
            SpinMotion(
                from: 4.5 * velocity(intensity: 1), to: 5.7 * velocity(intensity: 1),
                duration: Config.spinTeaseDuration, easing: Self.linear
            ),
        ])
        let motion = TimedSpinMotion(path: path, start: 0)
        #expect(abs(path.duration - 5.7) < 1e-9)
        #expect(!sparks(motion, now: 5.6).isEmpty)
        // 止まり切ってから寿命が過ぎたら出ない
        #expect(sparks(motion, now: path.duration + Config.wheelSparkLifetime).isEmpty)
    }

    @Test(arguments: SpinTease.allCases, [2, 8, 24])
    func 焦らしの区間では火花はごくわずか(tease: SpinTease, count: Int) {
        for direction in [1.0, -1.0] {
            let path = SpinPath.teased(tease, from: 30, to: 30 + direction * (360 * 5 + 200), count: count)
            let motion = TimedSpinMotion(path: path, start: 0)
            // 焦らしの区間は数十°/秒で、強さは 0.05 に届かない
            for step in 0...Int(Config.spinTeaseDuration * 1000) {
                #expect(path.intensity(at: Config.spinDuration + Double(step) / 1000) < 0.05)
            }
            // 主の区間で生まれた火花が消えたあと（焦らしの区間で生まれた火花だけ）は、どのフレームでも上限の 1/10 以下
            for step in 0...Int((path.duration - Config.spinDuration - Config.wheelSparkLifetime) * 20) {
                let now = Config.spinDuration + Config.wheelSparkLifetime + Double(step) / 20
                for seed in UInt64(0)..<20 {
                    #expect(sparks(motion, now: now, seed: seed).count <= WheelParticles.sparkCapacity(lowPower: false) / 10)
                }
            }
        }
    }

    @Test(arguments: [2, 8, 24])
    func 焦らしで戻る区間の火花は逆向きに飛ぶ(count: Int) {
        // 時計回りのスピンの、戻りかけの戻る区間（主の区間のあと 0.4 秒）と、行き過ぎの戻る区間（焦らしの区間すべて）
        let probes: [(SpinTease, TimeInterval)] = [
            (.rollBack, Config.spinDuration + Config.spinTeaseDuration * Config.spinTeaseRollBackShare),
            (.overshoot, Config.spinDuration + 0.8),
        ]
        for (tease, now) in probes {
            let path = SpinPath.teased(tease, from: 30, to: 30 + 360 * 5 + 200, count: count)
            let motion = TimedSpinMotion(path: path, start: 0)
            let all = (UInt64(0)..<200).flatMap { sparks(motion, now: now, seed: $0) }
            // 生まれたばかりの粒は針の先にいる。それ以外は左（反時計回りの向き）へ飛んでいる
            #expect(all.allSatisfy { $0.position.x <= Self.origin.x })
            #expect(all.contains { $0.position.x < Self.origin.x })
        }
    }

    // MARK: 指で動かしている間・惰性

    private func dragSparks(
        _ drag: WheelDragMotion?, now: TimeInterval, seed: UInt64 = 42, reduceMotion: Bool = false
    ) -> [WheelParticles.Spark] {
        WheelParticles.sparks(
            drag: drag, now: now, seed: seed, origin: Self.origin, scale: 1, lowPower: false, reduceMotion: reduceMotion
        )
    }

    @Test func 指で速く動かしている間も火花が出る() {
        let drag = WheelDragMotion.testCircular(velocity: velocity(intensity: 1), duration: 1)
        let now = drag.lastTime
        let all = dragSparks(drag, now: now)
        #expect(all.count >= WheelParticles.sparkCapacity(lowPower: false) / 2)
        #expect(all.count <= WheelParticles.sparkCapacity(lowPower: false))
        #expect(all.allSatisfy { $0.position.x >= Self.origin.x })
        // 反時計回りに動かすと左へ
        let counter = WheelDragMotion.testCircular(velocity: -velocity(intensity: 1), duration: 1)
        let left = dragSparks(counter, now: counter.lastTime)
        #expect(!left.isEmpty)
        #expect(left.allSatisfy { $0.position.x <= Self.origin.x })
    }

    @Test func 指の動きの火花の数は動かす速さに比例する() {
        func average(_ intensity: Double) -> Double {
            let drag = WheelDragMotion.testCircular(velocity: velocity(intensity: intensity), duration: 1)
            let counts = (UInt64(0)..<40).map { dragSparks(drag, now: drag.lastTime, seed: $0).count }
            return Double(counts.reduce(0, +)) / Double(counts.count)
        }
        let full = average(1)
        #expect(full > 0)
        #expect(abs(average(0.5) / full - 0.5) < 0.12)
        #expect(average(0) == 0)
    }

    @Test func 後から指が動いても前に生まれた火花は変わらない() {
        let shorter = WheelDragMotion.testCircular(velocity: velocity(intensity: 0.8), duration: 0.5)
        let longer = WheelDragMotion.testCircular(velocity: velocity(intensity: 0.8), duration: 0.8)
        for seed in UInt64(0)..<10 {
            #expect(dragSparks(shorter, now: shorter.lastTime, seed: seed) == dragSparks(longer, now: shorter.lastTime, seed: seed))
        }
    }

    @Test func 指を止めたら新しく生まれず寿命で消える() {
        let drag = WheelDragMotion.testCircular(velocity: velocity(intensity: 1), duration: 1)
        let last = drag.lastTime
        #expect(!dragSparks(drag, now: last + 0.1).isEmpty)
        // 最後に指が動いた時刻より後には生まれないので、寿命が過ぎたら消える
        #expect(dragSparks(drag, now: last + Config.wheelSparkLifetime).isEmpty)
        #expect(Config.wheelSparkLifetime <= Config.dragEffectSettleTime)
        #expect(dragSparks(nil, now: last).isEmpty)
        #expect(dragSparks(drag, now: last, reduceMotion: true).isEmpty)
    }

    @Test func 指を離してスピンに移っても合わせて上限まで() {
        // 指で速く動かして離した直後に、同じ時刻から速いスピンが始まった
        let drag = WheelDragMotion.testCircular(velocity: velocity(intensity: 1), start: 0, duration: 1)
        let spin = TimedSpinMotion(
            motion: SpinMotion(from: 0, to: velocity(intensity: 1) * 10, duration: 10, easing: Self.linear), start: drag.lastTime
        )
        for step in 0..<12 {
            let now = drag.lastTime + Double(step) * 0.05
            let both = WheelParticles.sparks(
                motion: spin, drag: drag, now: now, spinSeed: 1, dragSeed: 2,
                origin: Self.origin, scale: 1, lowPower: false, reduceMotion: false
            )
            let fromDrag = dragSparks(drag, now: now, seed: 2)
            #expect(both.count <= WheelParticles.sparkCapacity(lowPower: false))
            // 指の動きで生まれた粒は消えるまで残す
            #expect(Array(both.prefix(fromDrag.count)) == fromDrag)
        }
    }

    @Test func 惰性でも動きに応じて火花が出る() throws {
        // 惰性は強さ約 0.33 以下なので、出ても少ない
        let coast = try #require(FlickCoast.coast(angularVelocity: 230))
        let motion = TimedSpinMotion(motion: coast.motion(from: 0), start: 0)
        let counts = (UInt64(0)..<40).map { sparks(motion, now: 0.2, seed: $0).count }
        let average = Double(counts.reduce(0, +)) / Double(counts.count)
        #expect(average > 0)
        #expect(average < Double(WheelParticles.sparkCapacity(lowPower: false)) / 3)
        #expect(sparks(motion, now: coast.duration + Config.wheelSparkLifetime).isEmpty)
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

    // MARK: 粒ごとの乱数

    @Test func 仕上げの式はSplitMix64と同じ() {
        // SplitMix64 を種 0 で始めたときの最初の出力（よく知られた値）
        #expect(ParticleRandom.mix(ParticleRandom.increment) == 0xE220_A839_7B1D_CDAF)
        #expect(ParticleRandom.mix(0) == 0)
    }

    @Test func 粒ごとの乱数は既知の値を返す() {
        var first = ParticleRandom(seed: 0, index: 0)
        #expect([first.next(), first.next(), first.next()] == [0xB382_A305_F441_4F5E, 0x631A_9154_FBAB_F717, 0xA80A_BA8C_8664_0906])
        var other = ParticleRandom(seed: 42, index: 3)
        #expect([other.next(), other.next(), other.next()] == [0x57D5_8A8A_5A80_75DE, 0x3DDE_2C09_FC39_C00B, 0x288F_24AD_D176_7A40])
    }

    @Test(arguments: [UInt64(0), 1, 42, .max])
    func 番号が違えば列が違う(seed: UInt64) {
        func values(_ index: Int) -> [UInt64] {
            var random = ParticleRandom(seed: seed, index: index)
            return (0..<4).map { _ in random.next() }
        }
        let sequences = (0..<200).map(values)
        // 同じ種・番号なら同じ列
        #expect(values(7) == sequences[7])
        // どの番号の最初の値も重ならない
        #expect(Set(sequences.map { $0[0] }).count == sequences.count)
        // 隣の番号の列が 1 つずらした列にならない（番号を混ぜずに種と合わせると、種 0 でそうなる）
        for index in 0..<(sequences.count - 1) {
            #expect(Array(sequences[index + 1].prefix(3)) != Array(sequences[index].dropFirst()))
        }
    }

    @Test func 描き直すのは回っている間か紙吹雪が出ている間だけ() {
        #expect(WheelParticles.animates(reduceMotion: false, moving: true, bursting: false))
        #expect(WheelParticles.animates(reduceMotion: false, moving: false, bursting: true))
        #expect(!WheelParticles.animates(reduceMotion: false, moving: false, bursting: false))
        #expect(!WheelParticles.animates(reduceMotion: true, moving: true, bursting: true))
    }

    // MARK: 1 フレーム

    @Test(arguments: [CGFloat(320), 480])
    func 火花は針の先から出る(side: CGFloat) {
        let origin = WheelParticles.sparkOrigin(side: side)
        #expect(abs(origin.x - side / 2) < 1e-9)
        // 針は盤面の大きさに依らず、枠の上端から 6pt はみ出した 26pt の高さ
        #expect(abs(origin.y - 20) < 1e-9)
    }

    @Test(arguments: [false, true])
    func フレームは火花と紙吹雪を同じ関数で引く(lowPower: Bool) {
        let side: CGFloat = 480
        let motion = steady(velocity(intensity: 1))
        // はじけてからの経過は 2 進で割り切れる 0.25 秒にする（5 - 4.8 は 0.2 にならず、比べる側と粒の位置がずれる）
        let burst = WheelParticles.Burst(start: 4.75, seed: 7)
        let frame = WheelParticles.frame(
            motion: motion, drag: nil, burst: burst, now: 5, spinSeed: 42, dragSeed: 1, side: side,
            colorCount: 10, lowPower: lowPower, reduceMotion: false
        )
        let sparks = WheelParticles.sparks(
            motion: motion, drag: nil, now: 5, spinSeed: 42, dragSeed: 1, origin: WheelParticles.sparkOrigin(side: side),
            scale: side / CGFloat(WheelLabel.referenceDiameter), lowPower: lowPower, reduceMotion: false
        )
        let confetti = WheelParticles.confetti(
            elapsed: 5 - burst.start, seed: 7, side: side, colorCount: 10, lowPower: lowPower, reduceMotion: false
        )
        #expect(!frame.sparks.isEmpty)
        #expect(frame.sparks == sparks)
        #expect(frame.confetti == confetti)
        #expect(frame.sparks.count <= WheelParticles.sparkCapacity(lowPower: lowPower))
        #expect(frame.confetti.count <= WheelParticles.confettiCapacity(lowPower: lowPower))
    }

    @Test func はじけていなければ紙吹雪は出さず動きを減らす設定では何も出さない() {
        let motion = steady(velocity(intensity: 1))
        let calm = WheelParticles.frame(
            motion: nil, drag: nil, burst: nil, now: 5, spinSeed: 42, dragSeed: 1, side: 320,
            colorCount: 10, lowPower: false, reduceMotion: false
        )
        #expect(calm == .none)
        #expect(calm.isEmpty)
        let reduced = WheelParticles.frame(
            motion: motion, drag: nil, burst: WheelParticles.Burst(start: 4.8, seed: 7), now: 5, spinSeed: 42, dragSeed: 1,
            side: 320, colorCount: 10, lowPower: false, reduceMotion: true
        )
        #expect(reduced == .none)
        // 消え切ったあと
        let gone = WheelParticles.frame(
            motion: nil, drag: nil, burst: WheelParticles.Burst(start: 0, seed: 7), now: Config.wheelConfettiDuration,
            spinSeed: 42, dragSeed: 1, side: 320, colorCount: 10, lowPower: false, reduceMotion: false
        )
        #expect(gone.isEmpty)
    }
}
