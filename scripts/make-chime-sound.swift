// スピンが止まって結果が出た瞬間に鳴らす決まり音 (WAV, 16bit / 44.1kHz / モノラル。click.wav と同じ形式) を合成する。
// 小さなファンファーレとして、ド・ミ・ソ（C6・E6・G6）を上がるアルペジオで重ね、最後の音を少し長く響かせる。
// 1 音は減衰する正弦波 + 2・3 倍音（倍音ほど早く消える）で、柔らかいベルの音色にする。
// 乱数は使わないので、同じスクリプトからは毎回同じバイト列ができる。
// 使い方: swift scripts/make-chime-sound.swift <出力先.wav>
import Foundation

let sampleRate = 44100.0
let duration = 0.9
/// 書き出す波形の最大振幅。クリップせず、端末側の音量（`Config.chimeGain`）で絞る余地を残す。
let peak = 0.8

/// 鳴らし始め（秒）・基音の周波数・減衰の速さ（秒）・音量。
let notes: [(start: Double, frequency: Double, decay: Double, gain: Double)] = [
    (0.00, 1046.50, 0.16, 0.80),  // C6
    (0.09, 1318.51, 0.16, 0.80),  // E6
    (0.18, 1567.98, 0.28, 1.00),  // G6（最後の音は長めに響かせる）
]

/// 基音に対する倍音の倍率・音量・減衰の速さの比（1 より小さいほど早く消える）。
let partials: [(ratio: Double, gain: Double, decayRatio: Double)] = [
    (1, 1.00, 1.0),
    (2, 0.30, 0.55),
    (3, 0.10, 0.35),
]

/// 各音の立ち上がり（プチッというノイズを防ぐ）と、全体のお尻の丸め。
let attack = 0.004
let release = 0.06

let frameCount = Int(duration * sampleRate)
var samples = [Double](repeating: 0, count: frameCount)
for i in 0..<frameCount {
    let t = Double(i) / sampleRate
    var value = 0.0
    for note in notes where t >= note.start {
        let local = t - note.start
        var tone = 0.0
        for partial in partials {
            tone += sin(2 * .pi * note.frequency * partial.ratio * local) * partial.gain
                * exp(-local / (note.decay * partial.decayRatio))
        }
        if local < attack { tone *= local / attack }
        value += tone * note.gain
    }
    let remaining = duration - t
    if remaining < release { value *= remaining / release }
    samples[i] = value
}

let maxAmplitude = samples.map(abs).max() ?? 1
let scale = maxAmplitude > 0 ? peak / maxAmplitude : 0
let pcm = samples.map { Int16(max(-1, min(1, $0 * scale)) * 32767) }

/// RIFF (WAVE) のヘッダ + リトルエンディアンの 16bit PCM。`make-click-sound.swift` と同じ。
func wav(_ pcm: [Int16], sampleRate: Double) -> Data {
    var data = Data()
    func ascii(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
    func u32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

    let bytes = UInt32(pcm.count * 2)
    ascii("RIFF"); u32(36 + bytes); ascii("WAVE")
    ascii("fmt "); u32(16); u16(1); u16(1)
    u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 2); u16(2); u16(16)
    ascii("data"); u32(bytes)
    for sample in pcm { u16(UInt16(bitPattern: sample)) }
    return data
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("使い方: swift scripts/make-chime-sound.swift <出力先.wav>\n".utf8))
    exit(1)
}
let path = arguments[1]
try wav(pcm, sampleRate: sampleRate).write(to: URL(fileURLWithPath: path))
print("\(path) に \(pcm.count) サンプル (\(String(format: "%.2f", Double(pcm.count) / sampleRate)) 秒) を書き出した")
