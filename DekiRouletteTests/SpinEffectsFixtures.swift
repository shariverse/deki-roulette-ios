@testable import DekiRoulette

/// テストで使う演出の組み合わせ。以前の 5 択（なし / 電飾 / 光の尾 / 紙吹雪 / 全部入り）と同じ組み合わせを並べる。
enum SpinEffectsFixtures {
    static let lights = SpinEffects(lights: true, trails: false, particles: false, tease: true, stopEffects: true, sounds: true)
    static let trails = SpinEffects(lights: false, trails: true, particles: false, tease: true, stopEffects: true, sounds: true)
    static let confetti = SpinEffects(lights: false, trails: false, particles: true, tease: true, stopEffects: true, sounds: true)

    /// 焦らし・停止の演出・演出の効果音を付ける組み合わせ。
    static let withCommon: [SpinEffects] = [lights, trails, confetti, .all]

    /// 何も付けない組み合わせも含めたすべて。
    static let combinations: [SpinEffects] = [.none] + withCommon
}
