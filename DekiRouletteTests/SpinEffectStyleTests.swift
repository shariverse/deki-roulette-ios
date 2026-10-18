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
        let style = SpinEffectStyle.none
        #expect(!style.showsLights)
        #expect(!style.showsTrails)
        #expect(!style.showsParticles)
        #expect(!style.showsCommonEffects)
    }

    @Test func 電飾は電飾と共通の演出だけ() {
        let style = SpinEffectStyle.lights
        #expect(style.showsLights)
        #expect(!style.showsTrails)
        #expect(!style.showsParticles)
        #expect(style.showsCommonEffects)
    }

    @Test func 光の尾は光の尾と共通の演出だけ() {
        let style = SpinEffectStyle.trails
        #expect(!style.showsLights)
        #expect(style.showsTrails)
        #expect(!style.showsParticles)
        #expect(style.showsCommonEffects)
    }

    @Test func 紙吹雪は粒子と共通の演出だけ() {
        let style = SpinEffectStyle.confetti
        #expect(!style.showsLights)
        #expect(!style.showsTrails)
        #expect(style.showsParticles)
        #expect(style.showsCommonEffects)
    }

    @Test func 全部入りは3系統すべてと共通の演出() {
        let style = SpinEffectStyle.all
        #expect(style.showsLights)
        #expect(style.showsTrails)
        #expect(style.showsParticles)
        #expect(style.showsCommonEffects)
    }

    @Test func なし以外はどれも共通の演出を付ける() {
        for style in SpinEffectStyle.allCases where style != .none {
            #expect(style.showsCommonEffects)
        }
    }
}
