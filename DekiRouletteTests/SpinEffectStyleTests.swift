import Testing
@testable import DekiRoulette

struct SpinEffectStyleTests {
    @Test func 既定はなし() {
        #expect(SpinEffectStyle.default == .none)
    }

    /// 保存値が変わると、保存済みの設定が読めなくなって既定に戻る。
    @Test func 保存値は変えない() {
        #expect(SpinEffectStyle.allCases.map(\.rawValue) == ["none", "lights", "trails", "confetti", "all"])
    }

    @Test func 読めない保存値は既定として読む() {
        #expect(SpinEffectStyle(rawValue: "fireworks") == nil)
        #expect((SpinEffectStyle(rawValue: "fireworks") ?? .default) == .none)
    }

    @Test func なしは何も付けない() {
        #expect(SpinEffectStyle.none.effects == .none)
    }

    @Test func 電飾は電飾と共通の演出を付ける() {
        #expect(SpinEffectStyle.lights.effects == SpinEffects(
            lights: true, trails: false, particles: false, tease: true, stopEffects: true, sounds: true
        ))
    }

    @Test func 光の尾は光の尾と共通の演出を付ける() {
        #expect(SpinEffectStyle.trails.effects == SpinEffects(
            lights: false, trails: true, particles: false, tease: true, stopEffects: true, sounds: true
        ))
    }

    @Test func 紙吹雪は火花と紙吹雪と共通の演出を付ける() {
        #expect(SpinEffectStyle.confetti.effects == SpinEffects(
            lights: false, trails: false, particles: true, tease: true, stopEffects: true, sounds: true
        ))
    }

    @Test func 全部入りはすべて付ける() {
        #expect(SpinEffectStyle.all.effects == .all)
    }

    @Test func なし以外は共通の演出を付ける() {
        for style in SpinEffectStyle.allCases where style != .none {
            let effects = style.effects
            #expect(effects.tease && effects.stopEffects && effects.sounds, "\(style)")
        }
    }

    @Test func 指の動きはなし以外で記録する() {
        #expect(!SpinEffectStyle.none.effects.tracksDragMotion)
        for style in [SpinEffectStyle.lights, .trails, .confetti, .all] {
            #expect(style.effects.tracksDragMotion, "\(style)")
        }
    }
}
