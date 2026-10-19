import Foundation
import Testing
@testable import DekiRoulette

struct WheelStopEffectsTests {
    // MARK: フラッシュ

    @Test func フラッシュは停止の瞬間にいちばん明るく明るさを抑える() {
        #expect(abs(WheelStopEffects.flashOpacity(at: 0) - WheelStopEffects.flashPeakOpacity) < 1e-12)
        #expect(WheelStopEffects.flashPeakOpacity <= 0.25)
        for t in stride(from: -1.0, through: 2, by: 0.01) {
            let opacity = WheelStopEffects.flashOpacity(at: t)
            #expect(opacity >= 0 && opacity <= WheelStopEffects.flashPeakOpacity)
        }
    }

    @Test func フラッシュは1回だけで消える() {
        // 停止の前と消えたあとは 0
        #expect(WheelStopEffects.flashOpacity(at: -0.01) == 0)
        #expect(WheelStopEffects.flashOpacity(at: Config.stopFlashDuration) == 0)
        #expect(WheelStopEffects.flashOpacity(at: 5) == 0)
        // 光っている間は単調に暗くなる（明滅しない）
        var previous = WheelStopEffects.flashOpacity(at: 0)
        for t in stride(from: 0.005, to: Config.stopFlashDuration, by: 0.005) {
            let opacity = WheelStopEffects.flashOpacity(at: t)
            #expect(opacity <= previous)
            previous = opacity
        }
        // 消える直前は 0 に近い（急に消えない）
        #expect(WheelStopEffects.flashOpacity(at: Config.stopFlashDuration - 1e-6) < 1e-6)
        #expect(abs(Config.stopFlashDuration - 0.25) < 1e-12)
    }

    @Test func フラッシュは演出がなし_動きを減らす設定_結果が無いときは出さない() {
        #expect(WheelStopEffects.flashes(enabled: true, reduceMotion: false, elapsed: 0))
        #expect(!WheelStopEffects.flashes(enabled: false, reduceMotion: false, elapsed: 0))
        #expect(!WheelStopEffects.flashes(enabled: true, reduceMotion: true, elapsed: 0))
        #expect(!WheelStopEffects.flashes(enabled: true, reduceMotion: false, elapsed: nil))
        #expect(!WheelStopEffects.flashes(enabled: true, reduceMotion: false, elapsed: Config.stopFlashDuration))
    }

    /// フラッシュ・電飾の点滅と脈動・光彩の余韻の明るさの山を合わせても、どの 1 秒の窓にも 3 回未満（光過敏への配慮）。
    @Test func フラッシュと電飾と余韻を合わせても1秒に3回未満() {
        let dt = 0.001
        let times = Array(stride(from: 0.0, through: 8, by: dt))
        func peaks(_ level: (Double) -> Double) -> [Double] {
            let samples = times.map(level)
            var found: [Double] = samples[0] > samples[1] ? [0] : []
            for i in 1..<(samples.count - 1) where samples[i] > samples[i - 1] && samples[i] >= samples[i + 1] {
                found.append(times[i])
            }
            return found
        }
        let flash = peaks { WheelStopEffects.flashOpacity(at: $0) }
        let lights = peaks { WheelLights.stopped(at: $0) }
        let glow = peaks { WheelStopEffects.afterglowLevel(at: $0) }
        #expect(flash == [0])
        // 同じ時刻（1 フレーム以内）に重なる山は 1 回の明滅に数える
        var merged: [Double] = []
        for peak in (flash + lights + glow).sorted() where merged.last.map({ peak - $0 > 0.02 }) ?? true {
            merged.append(peak)
        }
        for peak in merged {
            #expect(merged.filter { $0 >= peak && $0 < peak + 1 }.count < 3)
        }
        // フラッシュは電飾の点滅の 1 回目と重なる
        #expect(lights.first.map { abs($0 - flash[0]) < 0.02 } == true)
    }

    // MARK: 余韻

    @Test func 余韻は周期2_4秒で脈打つ() {
        let period = Config.wheelLightAfterglowPeriod
        #expect(abs(period - 2.4) < 1e-12)
        for t in [1.0, 1.7, 3.3, 5.0] {
            #expect(abs(WheelStopEffects.afterglowLevel(at: t) - WheelStopEffects.afterglowLevel(at: t + period)) < 1e-9)
        }
        for t in stride(from: 0.0, through: 10, by: 0.05) {
            let level = WheelStopEffects.afterglowLevel(at: t)
            #expect(level >= WheelStopEffects.afterglowLowLevel - 1e-12 && level <= 1 + 1e-12)
        }
    }

    @Test func 余韻は電飾の脈動と同じ位相() {
        // 電飾の点滅のあとは、電飾の明るさと光彩の倍率が同じ時刻に上がり下がりする
        let lightsRange = WheelLights.afterglowHighLevel - WheelLights.blinkLowLevel
        for t in stride(from: WheelLights.blinkDuration, through: 8, by: 0.1) {
            let lights = (WheelLights.stopped(at: t) - WheelLights.blinkLowLevel) / lightsRange
            #expect(abs(lights - WheelStopEffects.afterglowWave(at: t)) < 1e-9)
        }
        // 電飾の点滅が終わるときにいちばん弱く、その半周期後にいちばん強い
        let low = WheelLights.blinkDuration
        #expect(abs(WheelStopEffects.afterglowLevel(at: low) - WheelStopEffects.afterglowLowLevel) < 1e-9)
        #expect(abs(WheelStopEffects.afterglowLevel(at: low + Config.wheelLightAfterglowPeriod / 2) - 1) < 1e-9)
    }

    @Test func 余韻は演出がなし_動きを減らす設定_結果が無いときは光彩を変えない() {
        #expect(WheelStopEffects.pulses(enabled: true, reduceMotion: false, showingResult: true))
        #expect(!WheelStopEffects.pulses(enabled: false, reduceMotion: false, showingResult: true))
        #expect(!WheelStopEffects.pulses(enabled: true, reduceMotion: true, showingResult: true))
        // 次のスピン・結果が消えた・指で動かして強調を解いたとき
        #expect(!WheelStopEffects.pulses(enabled: true, reduceMotion: false, showingResult: false))

        let low = WheelLights.blinkDuration
        #expect(WheelStopEffects.glowLevel(enabled: false, reduceMotion: false, stoppedElapsed: low) == 1)
        #expect(WheelStopEffects.glowLevel(enabled: true, reduceMotion: true, stoppedElapsed: low) == 1)
        #expect(WheelStopEffects.glowLevel(enabled: true, reduceMotion: false, stoppedElapsed: nil) == 1)
        #expect(abs(WheelStopEffects.glowLevel(enabled: true, reduceMotion: false, stoppedElapsed: low) - WheelStopEffects.afterglowLowLevel) < 1e-9)
    }

    @Test func 余韻を低頻度で描いても1回の変化は小さい() {
        // 倍率の変化の速さの最大 × 光彩の不透明度 × 描き直しの間隔
        let maxRate = (1 - WheelStopEffects.afterglowLowLevel) * .pi / Config.wheelLightAfterglowPeriod
        #expect(maxRate * Theme.stopGlowOpacity * Config.effectPulseFrameInterval < 0.04)
    }

    // MARK: 毎フレームの値

    @Test func フレームは停止からの経過でフラッシュと余韻を引く() {
        let frame = WheelStopEffects.frame(enabled: true, reduceMotion: false, flashStart: 10, afterglowStart: 10, now: 10.1)
        #expect(abs(frame.flashOpacity - WheelStopEffects.flashOpacity(at: 0.1)) < 1e-9)
        #expect(abs(frame.glowLevel - WheelStopEffects.afterglowLevel(at: 0.1)) < 1e-9)
        // フラッシュが消えたあとは余韻だけ
        let later = WheelStopEffects.frame(enabled: true, reduceMotion: false, flashStart: 10, afterglowStart: 10, now: 12)
        #expect(later.flashOpacity == 0)
        #expect(abs(later.glowLevel - WheelStopEffects.afterglowLevel(at: 2)) < 1e-9)
        // 強調を解いた（余韻の基準が無い）ときは光彩は今のまま。フラッシュは最後まで消す
        let released = WheelStopEffects.frame(enabled: true, reduceMotion: false, flashStart: 10, afterglowStart: nil, now: 10.1)
        #expect(released.glowLevel == 1)
        #expect(released.flashOpacity > 0)
    }

    @Test func なしと動きを減らす設定では何も足さない() {
        #expect(WheelStopEffects.frame(enabled: false, reduceMotion: false, flashStart: 10, afterglowStart: 10, now: 10) == .none)
        #expect(WheelStopEffects.frame(enabled: true, reduceMotion: true, flashStart: 10, afterglowStart: 10, now: 10) == .none)
        #expect(WheelStopEffects.Frame.none.flashOpacity == 0)
        #expect(WheelStopEffects.Frame.none.glowLevel == 1)
    }

    @Test func フラッシュの間は毎フレーム余韻だけなら間隔を落とす() {
        #expect(WheelStopEffects.frameInterval(flashing: true) == nil)
        #expect(WheelStopEffects.frameInterval(flashing: false) == Config.effectPulseFrameInterval)
    }

    // MARK: 停止の時刻

    @Test func 結果が出た時刻を停止の時刻にし消えたら捨てる() {
        var stop = WheelStopMoment()
        stop.resultChanged(showingResult: true, now: 10)
        #expect(stop.start == 10)
        #expect(stop.witnessed)
        stop.resultChanged(showingResult: false, now: 12)
        #expect(stop.start == nil)
        #expect(!stop.witnessed)
    }

    @Test func 結果を出したまま画面に出たら点滅を飛ばし見ていない停止にする() {
        var stop = WheelStopMoment()
        stop.appear(showingResult: true, now: 10)
        #expect(abs((stop.start ?? 0) - (10 - WheelLights.blinkDuration)) < 1e-9)
        #expect(!stop.witnessed)
        // すでに時刻を持っていれば変えない（画面に戻った）
        var seen = WheelStopMoment()
        seen.resultChanged(showingResult: true, now: 10)
        seen.appear(showingResult: true, now: 30)
        #expect(seen.start == 10)
        #expect(seen.witnessed)
        // 結果が無ければ何もしない
        var empty = WheelStopMoment()
        empty.appear(showingResult: false, now: 10)
        #expect(empty.start == nil)
    }

    private func stopped(at time: TimeInterval = 10) -> WheelStopMoment {
        var stop = WheelStopMoment()
        stop.resultChanged(showingResult: true, now: time)
        return stop
    }

    @Test func すべてONでは停止の時刻をすべての演出に渡す() {
        let cues = stopped().cues(effects: .all, reduceMotion: false, highlightedIndex: 2, displacedByDrag: false)
        #expect(cues == WheelStopCues(
            highlight: 2, lightsStoppedAt: 10, afterglowStart: 10, flashStart: 10, confettiStart: 10
        ))
    }

    @Test func 指で強調を解いたら電飾と余韻は止めフラッシュと紙吹雪は止めない() {
        let cues = stopped().cues(effects: .all, reduceMotion: false, highlightedIndex: 2, displacedByDrag: true)
        #expect(cues == WheelStopCues(
            highlight: nil, lightsStoppedAt: nil, afterglowStart: nil, flashStart: 10, confettiStart: 10
        ))
    }

    @Test func スタイルに含まない演出には時刻を渡さない() {
        let none = stopped().cues(effects: .none, reduceMotion: false, highlightedIndex: 2, displacedByDrag: false)
        #expect(none == WheelStopCues(highlight: 2))
        let lights = stopped().cues(effects: SpinEffectsFixtures.lights, reduceMotion: false, highlightedIndex: 2, displacedByDrag: false)
        #expect(lights == WheelStopCues(highlight: 2, lightsStoppedAt: 10, afterglowStart: 10, flashStart: 10))
        let trails = stopped().cues(effects: SpinEffectsFixtures.trails, reduceMotion: false, highlightedIndex: 2, displacedByDrag: false)
        #expect(trails == WheelStopCues(highlight: 2, afterglowStart: 10, flashStart: 10))
        let confetti = stopped().cues(effects: SpinEffectsFixtures.confetti, reduceMotion: false, highlightedIndex: 2, displacedByDrag: false)
        #expect(confetti == WheelStopCues(highlight: 2, afterglowStart: 10, flashStart: 10, confettiStart: 10))
    }

    /// 演出ごとの ON / OFF は、そのフラグが受け持つ演出の時刻だけを変える。
    @Test func 演出ごとのフラグはその演出の時刻だけを渡す() {
        func cues(_ effects: SpinEffects) -> WheelStopCues {
            stopped().cues(effects: effects, reduceMotion: false, highlightedIndex: 2, displacedByDrag: false)
        }
        var lights = SpinEffects.none
        lights.lights = true
        #expect(cues(lights) == WheelStopCues(highlight: 2, lightsStoppedAt: 10))
        var particles = SpinEffects.none
        particles.particles = true
        #expect(cues(particles) == WheelStopCues(highlight: 2, confettiStart: 10))
        var stopEffects = SpinEffects.none
        stopEffects.stopEffects = true
        #expect(cues(stopEffects) == WheelStopCues(highlight: 2, afterglowStart: 10, flashStart: 10))
        // 光の尾・焦らし・演出の効果音は停止の時刻を使わない
        let others = SpinEffects(lights: false, trails: true, particles: false, tease: true, stopEffects: false, sounds: true)
        #expect(cues(others) == WheelStopCues(highlight: 2))
    }

    @Test func 動きを減らす設定ではフラッシュ_紙吹雪_余韻を渡さない() {
        let cues = stopped().cues(effects: .all, reduceMotion: true, highlightedIndex: 2, displacedByDrag: false)
        // 電飾は点けたまま動かさない（`WheelLights` が動きを減らす設定の明るさにする）ので、時刻はそのまま渡す
        #expect(cues == WheelStopCues(highlight: 2, lightsStoppedAt: 10))
    }

    @Test func 見ていない停止ではフラッシュと紙吹雪を出さず脈動から始める() {
        var stop = WheelStopMoment()
        stop.appear(showingResult: true, now: 10)
        let cues = stop.cues(effects: .all, reduceMotion: false, highlightedIndex: 2, displacedByDrag: false)
        #expect(cues.flashStart == nil)
        #expect(cues.confettiStart == nil)
        #expect(cues.lightsStoppedAt == stop.start)
        #expect(cues.afterglowStart == stop.start)
    }

    @Test func 結果が無ければ何も渡さない() {
        let cues = WheelStopMoment().cues(effects: .all, reduceMotion: false, highlightedIndex: nil, displacedByDrag: false)
        #expect(cues == WheelStopCues())
        // 結果が消えた直後（添字が nil になった更新）
        var stop = stopped()
        stop.resultChanged(showingResult: false, now: 11)
        #expect(stop.cues(effects: .all, reduceMotion: false, highlightedIndex: nil, displacedByDrag: false) == WheelStopCues())
    }
}
