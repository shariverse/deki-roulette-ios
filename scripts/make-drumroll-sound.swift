// スピン中のうなり（ドラムロール）の 1 打ち (WAV, 16bit / 44.1kHz / モノラル。click.wav と同じ形式) を合成する。
// アプリはこの 1 打ちを、回転の速さに合わせた間隔・音量・ピッチで並べて 1 本の波形に焼く（`SpinHum`）。
// 速いときは打つ間隔が詰まって低い胴鳴りがつながり「ゴロゴロ」といううなりになり、遅くなるとまばらな「トン、トン」になる。
// 1 打ちは、スネアの響き線に当たる短いノイズ（一次のローパスで角を落とす）+ 音程が少し下がる胴の鳴り + 低い芯で作る。
// ノイズは固定の種から作るので、同じスクリプトからは毎回同じバイト列ができる。
// 使い方: swift scripts/make-drumroll-sound.swift <出力先.wav>
import Foundation

let sampleRate = 44100.0
let duration = 0.12
/// 書き出す波形の最大振幅。打ちが重なっても割れないよう、端末側の音量（`Config.humGain`）で絞る余地を残す。
let peak = 0.8

/// 響き線のノイズ。減衰の速さ（秒）・音量・ローパスの強さ（0...1。小さいほど丸い）。
let noiseDecay = 0.022
let noiseGain = 0.55
let noiseSmoothing = 0.35

/// 胴の鳴り。打った瞬間の周波数から `bodyDrop` の割合まで下がる。
let bodyFrequency = 210.0
let bodyDrop = 0.82
let bodyDecay = 0.035
let bodyGain = 0.8

/// 低い芯。速く打ったときにつながって「うなり」になる。
let coreFrequency = 95.0
let coreDecay = 0.05
let coreGain = 0.6

/// 頭とお尻を丸めてプチッというノイズを防ぐ。
let attack = 0.0015
let release = 0.02

// 毎回同じ音を出すため、乱数は固定の種から作る
var seed: UInt64 = 0xD1B5_4A32_D192_ED03
func noise() -> Double {
    seed ^= seed << 13
    seed ^= seed >> 7
    seed ^= seed << 17
    return Double(Int64(bitPattern: seed)) / Double(Int64.max)
}

let frameCount = Int(duration * sampleRate)
var samples = [Double](repeating: 0, count: frameCount)
var filtered = 0.0
var bodyPhase = 0.0
for i in 0..<frameCount {
    let t = Double(i) / sampleRate
    filtered += (noise() - filtered) * noiseSmoothing
    var value = filtered * noiseGain * exp(-t / noiseDecay)

    // 胴は音程が下がるので、位相を周波数の積分で進める
    let frequency = bodyFrequency * (bodyDrop + (1 - bodyDrop) * exp(-t / 0.01))
    bodyPhase += 2 * .pi * frequency / sampleRate
    value += sin(bodyPhase) * bodyGain * exp(-t / bodyDecay)
    value += sin(2 * .pi * coreFrequency * t) * coreGain * exp(-t / coreDecay)

    if t < attack { value *= t / attack }
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
    FileHandle.standardError.write(Data("使い方: swift scripts/make-drumroll-sound.swift <出力先.wav>\n".utf8))
    exit(1)
}
let path = arguments[1]
try wav(pcm, sampleRate: sampleRate).write(to: URL(fileURLWithPath: path))
print("\(path) に \(pcm.count) サンプル (\(String(format: "%.2f", Double(pcm.count) / sampleRate)) 秒) を書き出した")
