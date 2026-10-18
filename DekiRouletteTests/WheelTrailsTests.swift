import Foundation
import Testing
@testable import DekiRoulette

struct WheelTrailsTests {
    /// 等速の曲線（制御点が対角線上にあるので進み具合 = 時刻の割合）。
    private static let linear = CubicBezierCurve(0.33, 0.33, 0.67, 0.67)

    /// 角速度 `velocity`（度/秒、負なら反時計回り）で 10 秒間等速に回る動き。時刻 0 に始める。
    private func steady(_ velocity: Double, from: Double = 100) -> TimedSpinMotion {
        TimedSpinMotion(motion: SpinMotion(from: from, to: from + velocity * 10, duration: 10, easing: Self.linear), start: 0)
    }

    /// 強さ `intensity` になる角速度（度/秒）。
    private func velocity(intensity: Double) -> Double {
        Config.effectFullIntensityVelocity * intensity
    }

    private func frame(
        _ motion: TimedSpinMotion?, now: TimeInterval = 5, sliceCount: Int = 6, lowPower: Bool = false, reduceMotion: Bool = false
    ) -> WheelTrails.Frame {
        WheelTrails.frame(motion: motion, now: now, sliceCount: sliceCount, lowPower: lowPower, reduceMotion: reduceMotion)
    }

    // MARK: 濃さ

    @Test func 閾値未満では出さない() {
        #expect(WheelTrails.strength(intensity: 0) == 0)
        #expect(WheelTrails.strength(intensity: Config.wheelTrailThreshold - 0.01) == 0)
        #expect(WheelTrails.strength(intensity: Config.wheelTrailThreshold) == 0)
        #expect(frame(steady(velocity(intensity: 0.3))).isEmpty)
        #expect(frame(steady(velocity(intensity: Config.wheelTrailThreshold - 0.01))).isEmpty)
    }

    @Test func 閾値から1まで比例して濃くする() {
        let threshold = Config.wheelTrailThreshold
        #expect(abs(WheelTrails.strength(intensity: 1) - 1) < 1e-9)
        #expect(abs(WheelTrails.strength(intensity: (threshold + 1) / 2) - 0.5) < 1e-9)
        // 閾値のすぐ上ではほとんど 0（減速して閾値を割るときに急に消えない）
        #expect(WheelTrails.strength(intensity: threshold + 0.001) < 0.01)
        #expect(WheelTrails.strength(intensity: .nan) == 0)
    }

    @Test func 残像と光の尾は強さに比例して濃く長くなる() throws {
        let weak = frame(steady(velocity(intensity: 0.5)))
        let strong = frame(steady(velocity(intensity: 1)))
        let weakStrength = WheelTrails.strength(intensity: 0.5)
        #expect(weak.ghosts.count == strong.ghosts.count)
        for (w, s) in zip(weak.ghosts, strong.ghosts) {
            #expect(abs(w.opacity - s.opacity * weakStrength) < 1e-9)
        }
        let weakTrail = try #require(weak.trail)
        let strongTrail = try #require(strong.trail)
        #expect(abs(strongTrail.opacity - WheelTrails.trailPeakOpacity) < 1e-9)
        #expect(abs(weakTrail.opacity - WheelTrails.trailPeakOpacity * weakStrength) < 1e-9)
        #expect(abs(strongTrail.length - Config.wheelTrailMaxLength) < 1e-9)
        #expect(abs(weakTrail.length - Config.wheelTrailMaxLength * weakStrength) < 1e-9)
    }

    @Test func 速くても強さは1で止める() throws {
        let fastest = frame(steady(velocity(intensity: 4)))
        let trail = try #require(fastest.trail)
        #expect(abs(trail.length - Config.wheelTrailMaxLength) < 1e-9)
        #expect(fastest.ghosts.allSatisfy { $0.opacity <= WheelTrails.ghostPeakOpacity })
    }

    // MARK: 残像

    @Test func 残像は3枚で後ろほど薄い() {
        let ghosts = frame(steady(velocity(intensity: 1))).ghosts
        #expect(ghosts.count == Config.wheelTrailMaxGhostCount)
        #expect(ghosts.count == 3)
        for (front, back) in zip(ghosts, ghosts.dropFirst()) {
            #expect(front.opacity > back.opacity)
        }
    }

    @Test func 残像は遅れた時刻の角度に置く() {
        // 遅い（上限に掛からない）回転では、ずらしはそのまま角速度 × 遅れ
        let motion = steady(velocity(intensity: 0.45))
        let ghosts = frame(motion, sliceCount: 2).ghosts
        for (index, ghost) in ghosts.enumerated() {
            let lag = WheelTrails.lag(index: index, count: ghosts.count)
            #expect(abs(ghost.angle - motion.angle(now: 5 - lag)) < 1e-6)
        }
        #expect(abs(WheelTrails.lag(index: 2, count: 3) - Config.wheelTrailGhostWindow) < 1e-12)
    }

    @Test func 時計回りでは残像を反時計回りにずらし光の尾を後ろへ伸ばす() throws {
        let motion = steady(velocity(intensity: 1))
        let result = frame(motion)
        let angle = motion.angle(now: 5)
        #expect(result.ghosts.allSatisfy { $0.angle < angle })
        let trail = try #require(result.trail)
        #expect(trail.direction == .clockwise)
        #expect(trail.range.upperBound == 0)
        #expect(trail.range.lowerBound < 0)
    }

    @Test func 反時計回りでは残像も光の尾も逆へ() throws {
        let motion = steady(-velocity(intensity: 1))
        let result = frame(motion)
        let angle = motion.angle(now: 5)
        #expect(result.ghosts.count == 3)
        #expect(result.ghosts.allSatisfy { $0.angle > angle })
        let trail = try #require(result.trail)
        #expect(trail.direction == .counterclockwise)
        #expect(trail.range.lowerBound == 0)
        #expect(trail.range.upperBound > 0)
    }

    @Test func 最高速でも残像は隣のスライスを越えてずれない() {
        for sliceCount in [2, 6, 12, 24] {
            let motion = steady(3000)
            let ghosts = frame(motion, sliceCount: sliceCount).ghosts
            let angle = motion.angle(now: 5)
            let limit = WheelTrails.maxGhostOffset(sliceCount: sliceCount)
            #expect(limit <= Config.wheelTrailMaxGhostOffset)
            #expect(limit < 360 / Double(sliceCount))
            let offsets = ghosts.map { angle - $0.angle }
            #expect(abs(offsets.last! - limit) < 1e-6)
            // 縮めても等間隔のまま
            #expect(abs(offsets[0] * 3 - offsets[2]) < 1e-6)
            #expect(abs(offsets[1] * 3 - offsets[2] * 2) < 1e-6)
        }
    }

    @Test func ずらしの上限はずれの符号を保つ() {
        let clamped = WheelTrails.clampedOffsets([-10, -20, -40], limit: 8)
        #expect(abs(clamped[2] + 8) < 1e-9)
        #expect(abs(clamped[0] + 2) < 1e-9)
        let unchanged = WheelTrails.clampedOffsets([1, 2, 3], limit: 8)
        #expect(unchanged == [1, 2, 3])
        #expect(WheelTrails.clampedOffsets([.nan, 4], limit: 8) == [0, 4])
    }

    @Test func 焦らしで角速度が一時的に負になっても向きは角速度の符号から取る() throws {
        // 時計回りのスピンの途中で戻る動き（累積角は from より大きいまま、角速度だけが負）
        let back = TimedSpinMotion(motion: SpinMotion(from: 2000, to: 1000, duration: 1, easing: Self.linear), start: 0)
        let result = frame(back, now: 0.5)
        let trail = try #require(result.trail)
        #expect(trail.direction == .counterclockwise)
        #expect(result.ghosts.allSatisfy { $0.angle > back.angle(now: 0.5) })
        #expect(result.ghosts.allSatisfy { $0.angle.isFinite && $0.opacity.isFinite })
    }

    @Test(arguments: SpinTease.allCases, [2, 8, 24])
    func 焦らしの区間は閾値に届かないので描かない(tease: SpinTease, count: Int) {
        for direction in [1.0, -1.0] {
            let path = SpinPath.teased(tease, from: 30, to: 30 + direction * (360 * 5 + 200), count: count)
            let spin = TimedSpinMotion(path: path, start: 0)
            // 回り始めは描き、焦らしの区間（主の区間のあと）は描かない
            #expect(!frame(spin, now: 0.2, sliceCount: count).isEmpty)
            for step in 0...Int(Config.spinTeaseDuration * 100) {
                let now = Config.spinDuration + Double(step) / 100
                #expect(frame(spin, now: now, sliceCount: count).isEmpty)
            }
        }
    }

    // MARK: 出さないとき

    @Test func 低電力モードでは残像を1枚に減らす() {
        #expect(WheelTrails.ghostCount(lowPower: true) == 1)
        #expect(WheelTrails.ghostCount(lowPower: false) == 3)
        let result = frame(steady(velocity(intensity: 1)), lowPower: true)
        #expect(result.ghosts.count == 1)
        #expect(result.trail != nil)
    }

    @Test func 動きを減らす設定では出さない() {
        #expect(frame(steady(velocity(intensity: 1)), reduceMotion: true).isEmpty)
        #expect(!WheelTrails.animates(reduceMotion: true, moving: true))
    }

    @Test func 盤面が自分で回っていないときは出さない() {
        // 止まったあと（motion が nil）
        #expect(frame(nil).isEmpty)
        // 止まり切ったあと・始まる前
        #expect(frame(steady(velocity(intensity: 1)), now: 10).isEmpty)
        #expect(frame(steady(velocity(intensity: 1)), now: 11).isEmpty)
        #expect(frame(steady(velocity(intensity: 1)), now: -1).isEmpty)
        #expect(!WheelTrails.animates(reduceMotion: false, moving: false))
        #expect(WheelTrails.animates(reduceMotion: false, moving: true))
    }

    @Test func 減速するスピンでは止まる前に消える() {
        let spin = TimedSpinMotion(
            motion: SpinMotion(from: 0, to: 360 * 6 + 90, duration: Config.spinDuration, easing: Config.spinEasing), start: 0
        )
        #expect(!frame(spin, now: 0.2).isEmpty)
        #expect(frame(spin, now: Config.spinDuration - 0.01).isEmpty)
        // 濃さは減速につれて単調に下がる
        var previous = Double.infinity
        for step in 1..<45 {
            let opacity = frame(spin, now: Double(step) / 10).trail?.opacity ?? 0
            #expect(opacity <= previous + 1e-9)
            previous = opacity
        }
    }

    // MARK: 指で動かしている間・惰性

    private func dragFrame(
        _ drag: WheelDragMotion, now: TimeInterval, rotation: Double = 40, reduceMotion: Bool = false
    ) -> WheelTrails.Frame {
        WheelTrails.frame(
            effect: .drag(drag), now: now, rotation: rotation, dragRotation: drag.angle(now: now),
            sliceCount: 6, lowPower: false, reduceMotion: reduceMotion
        )
    }

    @Test func 指で速く動かしている間は動かす速さで描く() throws {
        let drag = WheelDragMotion.testCircular(velocity: velocity(intensity: 1), duration: 0.5)
        let now = drag.lastTime
        let result = dragFrame(drag, now: now)
        let trail = try #require(result.trail)
        #expect(trail.direction == .clockwise)
        #expect(abs(trail.opacity - WheelTrails.trailPeakOpacity) < 0.02)
        // 残像は盤面に見えている角度（rotation + dragRotation）から、指の動きの遅れた角度の差だけ後ろへずらす
        let displayed = 40 + drag.angle(now: now)
        let lags = (0..<3).map { drag.angle(now: now) - drag.angle(now: now - WheelTrails.lag(index: $0, count: 3)) }
        let offsets = WheelTrails.clampedOffsets(lags, limit: WheelTrails.maxGhostOffset(sliceCount: 6))
        #expect(result.ghosts.count == 3)
        for (ghost, offset) in zip(result.ghosts, offsets) {
            #expect(offset > 0)
            #expect(abs(ghost.angle - (displayed - offset)) < 1e-9)
        }
    }

    @Test func 指のイベントの間のフレームでは残像は伸び縮みしない() {
        // 盤面に見えている角度（`dragRotation`）は指が動いたときにしか変わらない
        let drag = WheelDragMotion.testCircular(velocity: velocity(intensity: 0.8), duration: 0.5)
        let shown = drag.angle(now: drag.lastTime)
        let at = { (now: TimeInterval) in
            WheelTrails.frame(
                effect: .drag(drag), now: now, rotation: 40, dragRotation: shown,
                sliceCount: 2, lowPower: false, reduceMotion: false
            )
        }
        let onEvent = at(drag.lastTime)
        #expect(onEvent.ghosts.count == 3)
        // 次の指のイベント（120Hz）までの間のフレーム
        for fraction in [0.25, 0.5, 0.9] {
            let between = at(drag.lastTime + fraction / 120)
            #expect(between.ghosts.count == 3)
            for (ghost, reference) in zip(between.ghosts, onEvent.ghosts) {
                #expect(abs(ghost.angle - reference.angle) < 1e-9, "\(fraction)")
            }
        }
    }

    @Test func 点と点の間の時刻では点の間を補った角度からずらす() {
        let drag = WheelDragMotion.testCircular(velocity: velocity(intensity: 0.8), duration: 0.5)
        // 最後の点より前の、点と点の間の時刻
        let now = drag.lastTime - 0.1 + 0.5 / 120
        let result = dragFrame(drag, now: now)
        let lags = (0..<3).map { drag.angle(now: now) - drag.angle(now: now - WheelTrails.lag(index: $0, count: 3)) }
        let offsets = WheelTrails.clampedOffsets(lags, limit: WheelTrails.maxGhostOffset(sliceCount: 6))
        #expect(result.ghosts.count == 3)
        for (ghost, offset) in zip(result.ghosts, offsets) {
            #expect(abs(ghost.angle - (40 + drag.angle(now: now) - offset)) < 1e-9)
        }
        // 前の点の時刻の角度とは違う（点の間を補っている）
        #expect(abs(drag.angle(now: now) - drag.angle(now: drag.lastTime - 0.1)) > 1)
    }

    @Test func 指で反時計回りに動かすと逆へ描く() throws {
        let drag = WheelDragMotion.testCircular(velocity: -velocity(intensity: 1), duration: 0.5)
        let result = dragFrame(drag, now: drag.lastTime)
        #expect(try #require(result.trail).direction == .counterclockwise)
        #expect(result.ghosts.allSatisfy { $0.angle > 40 + drag.angle(now: drag.lastTime) })
    }

    @Test func 指でゆっくり動かしている間と止めたあとは描かない() {
        // 閾値（強さ 0.35）に届かない速さ
        let slow = WheelDragMotion.testCircular(velocity: velocity(intensity: 0.3), duration: 0.5)
        #expect(dragFrame(slow, now: slow.lastTime).isEmpty)
        // 速く動かしてから止めた: 窓と平滑の分だけ遅れて消える
        let fast = WheelDragMotion.testCircular(velocity: velocity(intensity: 1), duration: 0.5)
        #expect(dragFrame(fast, now: fast.lastTime + Config.flickSampleWindow + 0.1).isEmpty)
        #expect(dragFrame(fast, now: fast.lastTime + Config.dragEffectSettleTime).isEmpty)
        #expect(dragFrame(fast, now: fast.lastTime, reduceMotion: true).isEmpty)
    }

    @Test(arguments: [100.0, 200, 239, -239])
    func 惰性は閾値に届かないので描かない(releaseVelocity: Double) throws {
        // 惰性は離した角速度が 240°/秒未満（強さ約 0.33 未満）のときだけ付き、そこから減速する
        let coast = try #require(FlickCoast.coast(angularVelocity: releaseVelocity))
        let motion = TimedSpinMotion(motion: coast.motion(from: 50), start: 0)
        #expect(motion.intensity(now: 0) > 0)
        #expect(motion.intensity(now: 0) < Config.wheelTrailThreshold)
        for step in 0...100 {
            #expect(frame(motion, now: coast.duration * Double(step) / 100).isEmpty)
        }
    }

    @Test func 入力は動きとスライスの数だけで決まる() {
        // 項目のラベル・指定・印を受け取る口は無く、同じ動きなら毎回同じものを描く
        let motion = steady(velocity(intensity: 0.8))
        #expect(frame(motion) == frame(motion))
        #expect(WheelTrails.frame(motion: motion, now: 5, dragRotation: 30, sliceCount: 6, lowPower: false, reduceMotion: false)
            .ghosts.map(\.angle).elementsEqual(frame(motion).ghosts.map { $0.angle + 30 }) { abs($0 - $1) < 1e-9 })
    }
}
