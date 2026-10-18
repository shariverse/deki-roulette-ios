import CoreGraphics
import Foundation
import Testing
@testable import DekiRoulette

struct WheelLightsTests {
    private let count = Config.wheelLightCount

    /// 光の並びのいちばん明るい電球の添字（同じ明るさなら小さい方）。
    private func brightest(angle: Double) -> Int {
        let levels = (0..<count).map { WheelLights.bulb(index: $0, count: count, scene: .running(angle: angle, intensity: 1)).brightness }
        return levels.indices.max { levels[$0] < levels[$1] || (levels[$0] == levels[$1] && $0 > $1) }!
    }

    private func levels(_ scene: WheelLights.Scene) -> [Double] {
        (0..<count).map { WheelLights.bulb(index: $0, count: count, scene: scene).brightness }
    }

    // MARK: 並べ方

    @Test func 電球は24個を12時から等間隔に並べる() {
        #expect(count == 24)
        #expect(WheelLights.angle(index: 0, count: count) == 0)
        #expect(abs(WheelLights.angle(index: 6, count: count) - 90) < 1e-9)
        #expect(abs(WheelLights.angle(index: 23, count: count) - 345) < 1e-9)
    }

    @Test func 止まっているときは3個おきに明るい() {
        let lit = levels(.running(angle: 0, intensity: 0))
        for index in 0..<count {
            let expected = index % WheelLights.litStride == 0 ? WheelLights.litLevel : WheelLights.baseLevel
            #expect(abs(lit[index] - expected) < 1e-9)
        }
    }

    // MARK: 流れ

    @Test func 光の並びは時計回りの回転で時計回りに流れる() {
        // 盤面が電球 1 個ぶんの角度 ÷ 係数だけ回ると、並びは電球 1 個ぶん時計回り（添字の大きい方）へ進む
        let step = 360 / Double(count) / Config.wheelLightFlowFactor
        #expect(brightest(angle: 0) == 0)
        #expect(brightest(angle: step) == 1)
        #expect(brightest(angle: step * 2) == 2)
    }

    @Test func 光の並びは反時計回りの回転で反時計回りに流れる() {
        let step = 360 / Double(count) / Config.wheelLightFlowFactor
        // 添字 0 の 1 個前（反時計回り）は添字 23 で、並びは 3 個おきなので添字 2 も同じ明るさになる
        let lit = levels(.running(angle: -step, intensity: 1))
        #expect(abs(lit[count - 1] - WheelLights.litPeakLevel) < 1e-9)
        #expect(abs(lit[2] - WheelLights.litPeakLevel) < 1e-9)
        #expect(abs(lit[0] - WheelLights.baseLevel) < 1e-9)
    }

    @Test func 並びの位置は盤面の角度に比例する() {
        let a = WheelLights.phase(angle: 100, count: count)
        let b = WheelLights.phase(angle: 300, count: count)
        #expect(abs(b - a * 3) < 1e-9)
        #expect(WheelLights.phase(angle: 0, count: count) == 0)
    }

    @Test func 角度0と1周で同じ並び() {
        for turns in [1.0, 2, 7, -3] {
            for angle in [0.0, 13, 200] {
                let once = levels(.running(angle: angle, intensity: 0.5))
                let again = levels(.running(angle: angle + 360 * turns, intensity: 0.5))
                for index in 0..<count {
                    #expect(abs(once[index] - again[index]) < 1e-9)
                }
            }
        }
    }

    // MARK: 流れの速さの上限

    /// 盤面の角度の列を 1 フレームずつ流したときの、各フレームの並びの位置（電球の個数）。
    private func flowPhases(_ angles: [Double], frame: TimeInterval) -> [Double] {
        var flow = WheelLights.Flow()
        return angles.enumerated().map { index, angle in
            WheelLights.phase(angle: flow.advance(to: angle, at: Double(index) * frame, count: count), count: count)
        }
    }

    @Test func 流れの上限は1フレームに電球0_5個() {
        #expect(abs(WheelLights.maxFlowAngle(elapsed: Config.effectReferenceFrameInterval, count: count) - 30) < 1e-9)
        #expect(abs(WheelLights.maxFlowAngle(elapsed: Config.effectReferenceFrameInterval / 2, count: count) - 15) < 1e-9)
        // 間が空いても 1 回には 1 フレーム分まで。時間が戻ったら進めない
        #expect(abs(WheelLights.maxFlowAngle(elapsed: 3, count: count) - 30) < 1e-9)
        #expect(WheelLights.maxFlowAngle(elapsed: -1, count: count) == 0)
    }

    @Test func 上限より遅ければ盤面の角度と同じだけ流す() {
        var flow = WheelLights.Flow()
        #expect(flow.advance(to: 37, at: 0, count: count) == 37)
        // 60Hz で 1 フレームに 10 度（600°/秒）。並びは 1 フレームに約 0.17 個
        for frame in 1...120 {
            let board = 37 + Double(frame) * 10
            #expect(abs(flow.advance(to: board, at: Double(frame) / 60, count: count) - board) < 1e-9)
        }
    }

    @Test(arguments: [1.0 / 60, 1.0 / 120, 1.0 / 90])
    func 速いスピンでも並びは1フレームに0_5個までしか進まない(frame: TimeInterval) {
        // 8 周・初速の大きいスピン（回り始めは 2,000°/秒を超える）
        for direction in [1.0, -1.0] {
            let motion = SpinMotion(from: 0, to: direction * (360 * 8 + 100), duration: Config.spinDuration, easing: Config.spinEasing)
            let frames = Int((Config.spinDuration / frame).rounded(.up)) + 30
            let angles = (0...frames).map { motion.angle(at: Double($0) * frame) }
            let phases = flowPhases(angles, frame: frame)
            let steps = zip(phases, phases.dropFirst()).map { $1 - $0 }
            #expect(steps.allSatisfy { abs($0) <= Config.wheelLightMaxFlowPerFrame + 1e-9 })
            // 回り始めは上限で流れ、向きは回転と同じ
            #expect(abs(steps[0] - direction * Config.wheelLightMaxFlowPerFrame * frame / Config.effectReferenceFrameInterval) < 1e-9)
            // 盤面が止まれば並びも止まる
            #expect(steps.suffix(10).allSatisfy { $0 == 0 })
        }
    }

    @Test func 同じフレームに2回描き直しても上限に収まる() {
        var flow = WheelLights.Flow()
        _ = flow.advance(to: 0, at: 0, count: count)
        let first = flow.advance(to: 200, at: 1.0 / 60, count: count)
        let second = flow.advance(to: 400, at: 1.0 / 60, count: count)
        #expect(abs(first - 30) < 1e-9)
        #expect(abs(second - 30) < 1e-9)
    }

    @Test func 遅れてよい上限は電球1個分() {
        // 電球 1 個は盤面で 15 度 ÷ 0.25 = 60 度
        #expect(abs(WheelLights.maxFlowLag(count: count) - 60) < 1e-9)
        #expect(WheelLights.maxFlowLag(count: 0) == 0)
    }

    /// 指で動かしている間は、角度が変わる描き直し（指の動き）が `TimelineView` の描き直しの直後に来て経過時間が短く、
    /// 角度の変わらない `TimelineView` の描き直しの経過時間が長い。持ち越した遅れで追いつき、上限より遅い動きは捨てない。
    @Test func 指の動きと描き直しの時刻がずれても上限より遅ければ盤面と同じだけ流す() {
        var flow = WheelLights.Flow()
        _ = flow.advance(to: 0, at: 0, count: count)
        var board = 0.0
        for frame in 1...60 {
            let tick = Double(frame) / 60
            // 指の動き（1 フレームに 20 度 = 1,200°/秒。上限の 1,800°/秒より遅い）は描き直しの 0.5ms 後
            board += 20
            let touched = flow.advance(to: board, at: tick - 1.0 / 60 + 0.0005, count: count)
            #expect(touched <= board + 1e-9)
            // 次の `TimelineView` の描き直しで追いつく
            #expect(abs(flow.advance(to: board, at: tick, count: count) - board) < 1e-9)
        }
    }

    @Test func 遅れは上限まで持ち越し超える分は捨てる() {
        for direction in [1.0, -1.0] {
            var flow = WheelLights.Flow()
            _ = flow.advance(to: 0, at: 0, count: count)
            // 1 フレームに盤面が 1,000 度進んで止まる。1 フレーム目は上限の 30 度、残りは遅れの上限 60 度まで持ち越して追いつく
            #expect(abs(flow.advance(to: direction * 1000, at: 1.0 / 60, count: count) - direction * 30) < 1e-9)
            var angles: [Double] = []
            for frame in 2...10 {
                angles.append(flow.advance(to: direction * 1000, at: Double(frame) / 60, count: count))
            }
            #expect(abs(angles[0] - direction * 60) < 1e-9)
            #expect(abs(angles[1] - direction * 90) < 1e-9)
            // 追いついたら止まる（捨てた分は取り戻さない）
            #expect(angles.dropFirst(2).allSatisfy { abs($0 - direction * 90) < 1e-9 })
            // そのあと盤面が上限より遅く動けば、同じだけ進む
            let next = flow.advance(to: direction * 1010, at: 11.0 / 60, count: count)
            #expect(abs(next - direction * 100) < 1e-9)
        }
    }

    @Test func 盤面が逆へ動いたら持ち越した遅れは捨てる() {
        for direction in [1.0, -1.0] {
            var flow = WheelLights.Flow()
            _ = flow.advance(to: 0, at: 0, count: count)
            // 1 フレームに 1,000 度進めて遅れ（上限 60 度）を溜める
            _ = flow.advance(to: direction * 1000, at: 1.0 / 60, count: count)
            #expect(abs(flow.lag - direction * 60) < 1e-9)
            // 次のフレームで盤面が逆へ 10 度戻る。前の向きへ流し続けず、戻った分だけ戻る
            let back = flow.advance(to: direction * 990, at: 2.0 / 60, count: count)
            #expect(abs(back - direction * 20) < 1e-9)
            #expect(flow.lag == 0)
        }
    }

    @Test func 盤面が止まっている間は遅れを持ち越したまま追いつく() {
        var flow = WheelLights.Flow()
        _ = flow.advance(to: 0, at: 0, count: count)
        _ = flow.advance(to: 1000, at: 1.0 / 60, count: count)
        // 角度の変化が 0 のときは捨てない
        #expect(abs(flow.advance(to: 1000, at: 2.0 / 60, count: count) - 60) < 1e-9)
    }

    @Test func 速いスピンのあとは減速して遅れを取り戻し盤面と同じだけ進む() {
        let motion = SpinMotion(from: 0, to: 360 * 8 + 100, duration: Config.spinDuration, easing: Config.spinEasing)
        var flow = WheelLights.Flow()
        var differences: [Double] = []
        let frames = Int(Config.spinDuration * 60)
        for frame in 0...frames {
            let board = motion.angle(at: Double(frame) / 60)
            differences.append(board - flow.advance(to: board, at: Double(frame) / 60, count: count))
        }
        // 止まる前に遅れ（捨てた分）は一定になり、盤面と同じだけ進む
        let tail = differences.suffix(30)
        #expect(tail.allSatisfy { abs($0 - tail.first!) < 1e-9 })
    }

    @Test func 電球の環はスライスの円の外8ptで縁の中に収まる() {
        let side: CGFloat = 320
        let slice = CGFloat(WheelGeometry.sliceRadius(diameter: Double(side)))
        #expect(abs(Theme.LightRing.ringRadius(diameter: side) - (slice + 8)) < 1e-9)
        // にじみが最も強くても盤面の枠を越えない（直径に比例）
        for diameter: CGFloat in [200, 320, 480] {
            let outer = Theme.LightRing.ringRadius(diameter: diameter) + Theme.LightRing.bulbRadius(diameter: diameter)
                + Theme.LightRing.haloWidth(diameter: diameter)
            #expect(outer <= diameter / 2 + 1e-9)
            #expect(abs(Theme.LightRing.bulbRadius(diameter: diameter) - 2.2 * diameter / 320) < 1e-9)
        }
    }

    @Test func 並びは滑らかに隣へ移る() {
        // 電球の半分ぶん進んだところでは、隣り合う 2 個が半分ずつ点く
        let half = 360 / Double(count) / Config.wheelLightFlowFactor / 2
        #expect(abs(WheelLights.chase(index: 0, phase: WheelLights.phase(angle: half, count: count)) - 0.5) < 1e-9)
        #expect(abs(WheelLights.chase(index: 1, phase: WheelLights.phase(angle: half, count: count)) - 0.5) < 1e-9)
    }

    @Test func 強さで明るさとにじみを上げる() {
        let weak = WheelLights.bulb(index: 0, count: count, scene: .running(angle: 0, intensity: 0))
        let strong = WheelLights.bulb(index: 0, count: count, scene: .running(angle: 0, intensity: 1))
        #expect(strong.brightness > weak.brightness)
        #expect(strong.glow > weak.glow)
        #expect(weak.glow == 0)
        // 並びの間の電球はにじませない
        #expect(WheelLights.bulb(index: 1, count: count, scene: .running(angle: 0, intensity: 1)).glow == 0)
    }

    @Test func 明るさは0から1に収まる() {
        for angle in stride(from: -400.0, through: 400, by: 7) {
            for intensity in [0.0, 0.3, 1] {
                for bulb in (0..<count).map({ WheelLights.bulb(index: $0, count: count, scene: .running(angle: angle, intensity: intensity)) }) {
                    #expect(bulb.brightness >= 0 && bulb.brightness <= 1)
                    #expect(bulb.glow >= 0 && bulb.glow <= 1)
                }
            }
        }
    }

    // MARK: 停止の点滅と脈動

    @Test func 停止の点滅は2回で1秒に3回未満() {
        // 明るさの山（極大）の時刻を細かく拾う
        let dt = 0.001
        let samples = stride(from: 0.0, through: 6, by: dt).map { WheelLights.stopped(at: $0) }
        // 停止の瞬間（0 秒）が 1 回目の山
        var peaks: [Double] = samples[0] > samples[1] ? [0] : []
        for i in 1..<(samples.count - 1) where samples[i] > samples[i - 1] && samples[i] >= samples[i + 1] {
            peaks.append(Double(i) * dt)
        }
        let blinkPeaks = peaks.filter { $0 < WheelLights.blinkDuration }
        #expect(blinkPeaks.count == Config.wheelLightBlinkCount)
        // どの 1 秒の窓にも山は 3 つ未満
        for peak in peaks {
            #expect(peaks.filter { $0 >= peak && $0 < peak + 1 }.count < 3)
        }
        // 点滅の明るいときも抑える
        #expect(samples.allSatisfy { $0 <= WheelLights.blinkHighLevel + 1e-9 })
    }

    @Test func 点滅は停止の瞬間の明るいところから始まる() {
        // 停止の瞬間のフラッシュと 1 回目の明るいところを重ね、合わせて 1 回の明滅にする
        #expect(abs(WheelLights.stopped(at: 0) - WheelLights.blinkHighLevel) < 1e-9)
        #expect(abs(WheelLights.stopped(at: Config.wheelLightBlinkPeriod) - WheelLights.blinkHighLevel) < 1e-9)
        #expect(abs(WheelLights.stopped(at: Config.wheelLightBlinkPeriod / 2) - WheelLights.blinkLowLevel) < 1e-9)
        // 点滅は 0.6 秒 × 1.5 で、暗いところで終える
        #expect(abs(WheelLights.blinkDuration - 0.9) < 1e-9)
        #expect(abs(WheelLights.stopped(at: WheelLights.blinkDuration - 1e-9) - WheelLights.blinkLowLevel) < 1e-6)
    }

    @Test func 点滅のあとに脈動へつながる() {
        let end = WheelLights.blinkDuration
        #expect(WheelLights.stopBlink(at: end - 0.01) != nil)
        #expect(WheelLights.stopBlink(at: end) == nil)
        // 切り替わりで明るさが飛ばない
        #expect(abs(WheelLights.stopped(at: end - 1e-6) - WheelLights.stopped(at: end + 1e-6)) < 1e-4)
        // 脈動は周期どおりに繰り返す
        let period = Config.wheelLightAfterglowPeriod
        for t in [0.3, 1.1, 2.0] {
            #expect(abs(WheelLights.afterglow(at: t) - WheelLights.afterglow(at: t + period)) < 1e-9)
        }
        #expect(abs(WheelLights.afterglow(at: period / 2) - WheelLights.afterglowHighLevel) < 1e-9)
        #expect(abs(WheelLights.afterglow(at: 0) - WheelLights.blinkLowLevel) < 1e-9)
    }

    @Test func 結果表示中は全灯が同じ明るさ() {
        for elapsed in [0.0, 0.3, 0.9, 1.5, 4] {
            let lit = levels(.stopped(elapsed: elapsed))
            #expect(lit.allSatisfy { abs($0 - lit[0]) < 1e-12 })
        }
    }

    // MARK: 場面

    @Test func 動きを減らす設定では一定() {
        #expect(WheelLights.scene(reduceMotion: true, angle: 123, intensity: 1, stoppedElapsed: nil) == .still)
        #expect(WheelLights.scene(reduceMotion: true, angle: 0, intensity: 0, stoppedElapsed: 0.3) == .still)
        let lit = levels(.still)
        #expect(lit.allSatisfy { abs($0 - WheelLights.stillLevel) < 1e-12 })
        #expect((0..<count).allSatisfy { WheelLights.bulb(index: $0, count: count, scene: .still).glow == 0 })
        #expect(!WheelLights.animates(reduceMotion: true, moving: true, showingResult: true))
    }

    @Test func 場面は結果の有無と動きから決める() {
        #expect(WheelLights.scene(reduceMotion: false, angle: 10, intensity: 0.4, stoppedElapsed: nil) == .running(angle: 10, intensity: 0.4))
        #expect(WheelLights.scene(reduceMotion: false, angle: 10, intensity: 2, stoppedElapsed: nil) == .running(angle: 10, intensity: 1))
        #expect(WheelLights.scene(reduceMotion: false, angle: 10, intensity: 0.4, stoppedElapsed: 0.5) == .stopped(elapsed: 0.5))
    }

    @Test func 脈動だけになったら描き直しの間隔を落とす() {
        // 回っている間と点滅の間は毎フレーム
        #expect(WheelLights.frameInterval(moving: true, stoppedElapsed: nil) == nil)
        #expect(WheelLights.frameInterval(moving: false, stoppedElapsed: nil) == nil)
        #expect(WheelLights.frameInterval(moving: false, stoppedElapsed: 0) == nil)
        #expect(WheelLights.frameInterval(moving: false, stoppedElapsed: WheelLights.blinkDuration - 0.01) == nil)
        // 点滅が終わったら低頻度
        #expect(WheelLights.frameInterval(moving: false, stoppedElapsed: WheelLights.blinkDuration) == Config.effectPulseFrameInterval)
        #expect(WheelLights.frameInterval(moving: false, stoppedElapsed: 10) == Config.effectPulseFrameInterval)
        // 低頻度でも 1 回の変化は小さい（脈動の明るさの変化の速さの最大 × 間隔）
        let maxRate = (WheelLights.afterglowHighLevel - WheelLights.blinkLowLevel) * .pi / Config.wheelLightAfterglowPeriod
        #expect(maxRate * Config.effectPulseFrameInterval < 0.04)
    }

    @Test func 待機中は描き直さない() {
        #expect(!WheelLights.animates(reduceMotion: false, moving: false, showingResult: false))
        #expect(WheelLights.animates(reduceMotion: false, moving: true, showingResult: false))
        #expect(WheelLights.animates(reduceMotion: false, moving: false, showingResult: true))
    }
}
