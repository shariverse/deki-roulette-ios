import Foundation

/// スピン中のうなり（ドラムロール）。音源（`Resources/Sounds/drumroll.wav`。`scripts/make-drumroll-sound.swift` で合成）の 1 打ちを、
/// 回転の速さに合わせた間隔・音量・ピッチで並べる。補間中の角度は observable でないので、回転音（`ClickTrack`）と同じく
/// スピンの開始時に動き（`SpinPath`）から打つ時刻を先に求め、1 本の波形に焼いてから一度に流す。
/// 仕様は `docs/SPEC.md` の §5.5「効果音」。指定（`targetId`）・印・結果のラベルは受け取らない（同じ動きなら同じ音）。
enum SpinHum {
    /// 1 打ち。時刻はスピン開始からの秒、`gain` は 0...1 の音量、`rate` は再生の速さ（1 で音源のまま。大きいほど高く短い）。
    struct Stroke: Hashable, Sendable {
        let time: TimeInterval
        let gain: Double
        let rate: Double
    }

    /// うなりを付けるスピンか。「スピンの演出」が共通の演出を付けるスタイルで、盤面が回る（動きを減らす設定でない）ときだけ。
    /// 惰性・指で動かしている間は抽選のスピンではないので、呼び出し側はそもそもここを通さない（鳴らさない）。
    /// 設定の「効果音」の ON / OFF は再生する側（`RouletteScreen`）が見る。
    static func plays(style: SpinEffectStyle, reducedMotion: Bool) -> Bool {
        style.showsCommonEffects && !reducedMotion
    }

    /// 演出の強さ（0...1）→ 音量（0...1）。`Config.humMinIntensity` 以下では鳴らさず（0）、そこから強さ 1 で 1 まで比例して上げる。
    static func gain(intensity: Double) -> Double {
        guard intensity.isFinite, intensity > Config.humMinIntensity else { return 0 }
        return min((intensity - Config.humMinIntensity) / (1 - Config.humMinIntensity), 1)
    }

    /// 演出の強さ（0...1）→ 次の打ちまでの間隔（秒）。強さ 0 で `Config.humSlowInterval`、1 で `Config.humFastInterval` で、間は比例。
    static func interval(intensity: Double) -> TimeInterval {
        let clamped = intensity.isFinite ? min(max(intensity, 0), 1) : 0
        return Config.humSlowInterval + (Config.humFastInterval - Config.humSlowInterval) * clamped
    }

    /// 演出の強さ（0...1）→ 再生の速さ（ピッチ）。強さ 0 で `Config.humMinRate`、1 で `Config.humMaxRate` で、間は比例。
    static func rate(intensity: Double) -> Double {
        let clamped = intensity.isFinite ? min(max(intensity, 0), 1) : 0
        return Config.humMinRate + (Config.humMaxRate - Config.humMinRate) * clamped
    }

    /// 動き `path` で打つ時刻・音量・ピッチを、開始から時刻順に返す。各時刻の強さ（`path.intensity(at:)`）から次の打ちまでの間隔を決めて進め、
    /// 音量が 0 の時刻（遅すぎる）は打たない。焦らしの区間は速さが小さいので打たない。ドラムロールらしく、1 打ちおきに `Config.humAccent` で弱める。
    static func strokes(along path: SpinPath) -> [Stroke] {
        var strokes: [Stroke] = []
        var time: TimeInterval = 0
        let duration = path.duration
        while time < duration {
            let intensity = path.intensity(at: time)
            let gain = gain(intensity: intensity)
            if gain > 0 {
                let accent = strokes.count.isMultiple(of: 2) ? 1 : Config.humAccent
                strokes.append(Stroke(time: time, gain: gain * accent, rate: rate(intensity: intensity)))
            }
            time += interval(intensity: intensity)
        }
        return strokes
    }

    /// `stroke`（1 打ちの波形）を各打ちの時刻に、その音量と再生の速さ（線形補間で伸び縮み）で足し合わせた 1 本の波形を返す。
    /// `skipping` 秒より前は切り落とす（準備を待って遅れた分。打ちの途中から始まることもある）。重なった部分は加算し、-1...1 に収める。
    /// 打ちが無い・すべて切り落とされたときは空。
    static func render(
        stroke: [Float],
        sampleRate: Double,
        strokes: [Stroke],
        skipping: TimeInterval = 0
    ) -> [Float] {
        guard stroke.count > 1, !strokes.isEmpty, sampleRate > 0 else { return [] }
        let skip = Int(max(0, skipping) * sampleRate)
        let placed: [(offset: Int, length: Int, stroke: Stroke)] = strokes.compactMap { item in
            guard item.rate > 0, item.gain > 0 else { return nil }
            let offset = Int(max(0, item.time) * sampleRate) - skip
            let length = Int(Double(stroke.count - 1) / item.rate)
            guard offset + length > 0 else { return nil }
            return (offset, length, item)
        }
        guard let end = placed.map({ $0.offset + $0.length }).max(), end > 0 else { return [] }

        var track = [Float](repeating: 0, count: end)
        for (offset, length, item) in placed {
            let gain = Float(item.gain)
            for j in max(0, -offset)..<length {
                let source = Double(j) * item.rate
                let index = Int(source)
                let fraction = Float(source - Double(index))
                let sample = stroke[index] * (1 - fraction) + stroke[min(index + 1, stroke.count - 1)] * fraction
                track[offset + j] += sample * gain
            }
        }
        for i in track.indices {
            track[i] = min(max(track[i], -1), 1)
        }
        return track
    }
}
