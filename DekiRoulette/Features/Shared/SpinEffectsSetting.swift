import SwiftUI

/// 設定の「スピンの演出」（全体の ON / OFF と演出ごとのトグル）を `UserDefaults` から読み書きする。
/// 設定画面（`RouletteAdvancedSettingsView`）とルーレットの画面（`RouletteScreen`）が同じキー・同じ既定値で持つ。
struct SpinEffectsSetting: DynamicProperty {
    @AppStorage(Config.spinEffectsEnabledKey) var enabled = true
    @AppStorage(Config.spinEffectKey(.lights)) private var lights = SpinEffects.default.lights
    @AppStorage(Config.spinEffectKey(.trails)) private var trails = SpinEffects.default.trails
    @AppStorage(Config.spinEffectKey(.particles)) private var particles = SpinEffects.default.particles
    @AppStorage(Config.spinEffectKey(.tease)) private var tease = SpinEffects.default.tease
    @AppStorage(Config.spinEffectKey(.stopEffects)) private var stopEffects = SpinEffects.default.stopEffects
    @AppStorage(Config.spinEffectKey(.sounds)) private var sounds = SpinEffects.default.sounds

    /// 個別のトグルで選んでいるもの（全体の ON / OFF は踏まえない）。
    var selected: SpinEffects {
        SpinEffects(
            lights: lights, trails: trails, particles: particles, tease: tease, stopEffects: stopEffects, sounds: sounds
        )
    }

    /// 付ける演出。全体が OFF なら何も付けない。
    var effects: SpinEffects {
        SpinEffects.effective(enabled: enabled, selected: selected)
    }

    var enabledBinding: Binding<Bool> { $enabled }

    func binding(for item: SpinEffectItem) -> Binding<Bool> {
        switch item {
        case .lights: $lights
        case .trails: $trails
        case .particles: $particles
        case .tease: $tease
        case .stopEffects: $stopEffects
        case .sounds: $sounds
        }
    }
}
