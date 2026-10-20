import AVFAudio
import Foundation
import Testing
@testable import DekiRoulette

@MainActor
struct SpinHumTests {
    private func makeModel(_ labels: [String] = ["A", "B", "C", "D"]) -> RouletteModel {
        RouletteModel(items: ItemLabel.makeItems(labels))
    }

    /// 焦らしを入れたスピンの動き（4.5 秒の主の区間 + 2 秒の焦らし）。
    private func teasedPath(_ tease: SpinTease, count: Int = 8, releaseVelocity: Double? = nil) -> SpinPath {
        var rng = SeededGenerator(seed: 5)
        let to = RouletteMath.nextRotation(current: 0, targetIndex: 2, count: count, direction: .clockwise, using: &rng)
        return SpinPath.teased(tease, from: 0, to: to, count: count, releaseVelocity: releaseVelocity)
    }

    // MARK: 鳴らす条件

    @Test func なしでは付けない() {
        #expect(!SpinHum.plays(effects: .none, reducedMotion: false))
        #expect(!SpinHum.plays(effects: .none, reducedMotion: true))
    }

    @Test func 演出があれば付ける() {
        for effects in SpinEffectsFixtures.withCommon {
            #expect(SpinHum.plays(effects: effects, reducedMotion: false))
        }
    }

    /// うなりは演出の効果音（`sounds`）のフラグだけで決まり、ほかの演出のフラグには依らない。
    @Test func 演出の効果音のフラグだけで付けるか決まる() {
        var soundsOnly = SpinEffects.none
        soundsOnly.sounds = true
        var allButSounds = SpinEffects.all
        allButSounds.sounds = false
        #expect(SpinHum.plays(effects: soundsOnly, reducedMotion: false))
        #expect(!SpinHum.plays(effects: allButSounds, reducedMotion: false))
    }

    @Test func 動きを減らす設定では付けない() {
        for effects in SpinEffectsFixtures.combinations {
            #expect(!SpinHum.plays(effects: effects, reducedMotion: true))
        }
    }

    // MARK: 速さの写像

    @Test func 音量は強さが下限以下で0になり強さに比例して上がる() {
        #expect(SpinHum.gain(intensity: 0) == 0)
        #expect(SpinHum.gain(intensity: Config.humMinIntensity) == 0)
        #expect(SpinHum.gain(intensity: .nan) == 0)
        #expect(abs(SpinHum.gain(intensity: 1) - 1) < 1e-9)
        #expect(abs(SpinHum.gain(intensity: 2) - 1) < 1e-9)
        var previous = 0.0
        for step in 1...20 {
            let gain = SpinHum.gain(intensity: Double(step) / 20)
            #expect(gain >= previous)
            previous = gain
        }
    }

    @Test func 速いほど間隔が詰まりピッチが上がる() {
        #expect(abs(SpinHum.interval(intensity: 1) - Config.humFastInterval) < 1e-9)
        #expect(abs(SpinHum.interval(intensity: 0) - Config.humSlowInterval) < 1e-9)
        #expect(abs(SpinHum.interval(intensity: -1) - Config.humSlowInterval) < 1e-9)
        #expect(SpinHum.interval(intensity: 0.8) < SpinHum.interval(intensity: 0.3))
        #expect(abs(SpinHum.rate(intensity: 1) - Config.humMaxRate) < 1e-9)
        #expect(abs(SpinHum.rate(intensity: 0) - Config.humMinRate) < 1e-9)
        #expect(SpinHum.rate(intensity: 0.8) > SpinHum.rate(intensity: 0.3))
        // 間隔は常に正（打つ時刻が進まなくならない）
        #expect(Config.humFastInterval > 0)
    }

    // MARK: 打つ時刻

    @Test(arguments: SpinTease.allCases)
    func 打ちは時刻順で動きの長さに収まり音量は0から1(tease: SpinTease) {
        let path = teasedPath(tease)
        let strokes = SpinHum.strokes(along: path)
        #expect(!strokes.isEmpty)
        #expect(strokes.first?.time == 0)
        for (earlier, later) in zip(strokes, strokes.dropFirst()) {
            #expect(later.time > earlier.time)
        }
        for stroke in strokes {
            #expect(stroke.time < path.duration)
            #expect(stroke.gain > 0 && stroke.gain <= 1)
            #expect(stroke.rate >= Config.humMinRate && stroke.rate <= Config.humMaxRate)
        }
    }

    @Test(arguments: SpinTease.allCases)
    func 焦らしの区間では打たず止まる前に消える(tease: SpinTease) throws {
        let path = teasedPath(tease)
        let teaseStart = try #require(path.startTimes.dropFirst().first)
        let strokes = SpinHum.strokes(along: path)
        let last = try #require(strokes.last)
        #expect(last.time < teaseStart)
        // 焦らしの区間はどの時刻でも打つ強さに届かない
        for step in 0...120 {
            let time = teaseStart + (path.duration - teaseStart) * Double(step) / 120
            #expect(SpinHum.gain(intensity: path.intensity(at: time)) == 0)
        }
    }

    @Test func 速い序盤は大きく詰まって打ち遅くなるにつれて小さくまばらになる() throws {
        let path = teasedPath(.hesitate)
        let strokes = SpinHum.strokes(along: path)
        #expect(strokes.count >= 6)
        let first = try #require(strokes.first)
        let last = try #require(strokes.last)
        // 先頭は強さ 1（アクセントの無い打ち）で、最後の打ちは弱い
        #expect(abs(first.gain - 1) < 1e-9)
        #expect(last.gain < 0.5)
        #expect(last.rate < first.rate)
        let firstGap = strokes[1].time - strokes[0].time
        let lastGap = strokes[strokes.count - 1].time - strokes[strokes.count - 2].time
        #expect(lastGap > firstGap)
    }

    @Test func 一打ちおきに弱める() {
        let path = SpinPath(SpinMotion(from: 0, to: 36_000, duration: 1, easing: CubicBezierCurve(0, 0, 1, 1)))
        let strokes = SpinHum.strokes(along: path)
        #expect(strokes.count >= 4)
        for (index, stroke) in strokes.enumerated() {
            let expected = index.isMultiple(of: 2) ? 1 : Config.humAccent
            #expect(abs(stroke.gain - expected) < 1e-9)
        }
    }

    @Test func 回らない動きでは打たない() {
        #expect(SpinHum.strokes(along: .idle).isEmpty)
    }

    // MARK: 波形

    @Test func 打ちが無ければ空の波形() {
        #expect(SpinHum.render(stroke: [0.5, 0.5], sampleRate: 44_100, strokes: []).isEmpty)
        #expect(SpinHum.render(stroke: [], sampleRate: 44_100, strokes: [.init(time: 0, gain: 1, rate: 1)]).isEmpty)
    }

    @Test func 打つ位置に音量とピッチを掛けて足し合わせる() {
        let stroke: [Float] = [0, 0.5, 0.5, 0.5, 0.5]
        let track = SpinHum.render(
            stroke: stroke, sampleRate: 10,
            strokes: [.init(time: 0, gain: 1, rate: 1), .init(time: 1, gain: 0.5, rate: 2)]
        )
        // 2 打ち目は 10 サンプル目から、速さ 2 で長さが半分（4 → 2）
        #expect(track.count == 12)
        #expect(track[0] == 0)
        #expect(abs(track[1] - 0.5) < 1e-6)
        #expect(track[10] == 0)
        #expect(abs(track[11] - 0.25) < 1e-6)
    }

    @Test func 待った分は頭を切り落とし重なりは割れない() {
        let stroke: [Float] = [0.9, 0.9, 0.9, 0.9, 0.9]
        let strokes: [SpinHum.Stroke] = [.init(time: 0, gain: 1, rate: 1), .init(time: 0.1, gain: 1, rate: 1)]
        let full = SpinHum.render(stroke: stroke, sampleRate: 10, strokes: strokes)
        let skipped = SpinHum.render(stroke: stroke, sampleRate: 10, strokes: strokes, skipping: 0.2)
        #expect(full.count == 5)
        #expect(full.allSatisfy { $0 <= 1 })
        #expect(skipped.count == 3)
        #expect(SpinHum.render(stroke: stroke, sampleRate: 10, strokes: strokes, skipping: 10).isEmpty)
    }

    // MARK: モデル

    @Test(arguments: SpinEffectsFixtures.withCommon)
    func 演出ありのスピンでうなりの打ちを用意する(effects: SpinEffects) throws {
        let model = makeModel()
        model.randomSource = AnyRandomNumberGenerator(SeededGenerator(seed: 9))
        _ = try #require(model.beginSpin(reducedMotion: false, effects: effects))
        #expect(!model.humStrokes.isEmpty)
        #expect(model.humStrokes == SpinHum.strokes(along: model.rotationPath))
    }

    @Test func なしのスピンではうなりを付けない() throws {
        let model = makeModel()
        _ = try #require(model.beginSpin(reducedMotion: false, effects: .none))
        #expect(model.humStrokes.isEmpty)
        // 回転音は今のまま
        #expect(!model.clickTimes.isEmpty)
    }

    @Test func 動きを減らす設定のスピンではうなりを付けない() throws {
        let model = makeModel()
        _ = try #require(model.beginSpin(reducedMotion: true, effects: .all))
        #expect(model.humStrokes.isEmpty)
    }

    @Test func 惰性ではうなりを付けず前のスピンの打ちも捨てる() throws {
        let model = makeModel()
        _ = try #require(model.beginSpin(reducedMotion: false, effects: .all))
        #expect(!model.humStrokes.isEmpty)
        model.finishSpin()
        _ = try #require(model.beginCoast(angularVelocity: 300, reducedMotion: false))
        #expect(model.humStrokes.isEmpty)
    }

    /// 同じ乱数の列なら、指定の有無に依らず同じうなりになる（指定した項目が指定なしでも止まる項目なら、動きもうなりも同じ）。
    @Test func 指定があってもなくても同じうなり() throws {
        for seed: UInt64 in [1, 7, 42] {
            let free = makeModel()
            free.randomSource = AnyRandomNumberGenerator(SeededGenerator(seed: seed))
            _ = try #require(free.beginSpin(reducedMotion: false, effects: .all))
            free.finishSpin()
            let index = try #require(free.outcome?.index)

            let aimed = makeModel()
            aimed.toggleTarget(id: aimed.items[index].id)
            aimed.randomSource = AnyRandomNumberGenerator(SeededGenerator(seed: seed))
            _ = try #require(aimed.beginSpin(reducedMotion: false, effects: .all))

            #expect(aimed.rotationPath == free.rotationPath)
            #expect(aimed.humStrokes == free.humStrokes)
            #expect(!aimed.humStrokes.isEmpty)
        }
    }

    // MARK: 音源

    /// 音源は click.wav と同じ形式で、短く・クリップしない（`scripts/make-drumroll-sound.swift` の出力）。
    @Test func 音源は短くクリップしない() throws {
        let humURL = try #require(Bundle.main.url(forResource: "drumroll", withExtension: "wav"))
        let clickURL = try #require(Bundle.main.url(forResource: "click", withExtension: "wav"))
        let hum = try AVAudioFile(forReading: humURL)
        let click = try AVAudioFile(forReading: clickURL)

        #expect(hum.fileFormat.sampleRate == click.fileFormat.sampleRate)
        #expect(hum.fileFormat.channelCount == 1)
        #expect(hum.fileFormat.commonFormat == click.fileFormat.commonFormat)
        #expect(Double(hum.length) / hum.fileFormat.sampleRate < 0.2)

        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: hum.processingFormat, frameCapacity: AVAudioFrameCount(hum.length)
        ))
        try hum.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?.pointee)
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.1)
        #expect(peak < 1)
        // 頭と尻は 0 付近（プチッというノイズを出さない）
        #expect(abs(samples[0]) < 0.01)
        #expect(abs(samples[samples.count - 1]) < 0.01)
    }
}
