import Testing
@testable import DekiRoulette

struct SpinEffectsTests {
    @Test func noneはすべてOFF() {
        let effects = SpinEffects.none
        #expect(![effects.lights, effects.trails, effects.particles, effects.tease, effects.stopEffects, effects.sounds].contains(true))
    }

    @Test func allはすべてON() {
        let effects = SpinEffects.all
        #expect(![effects.lights, effects.trails, effects.particles, effects.tease, effects.stopEffects, effects.sounds].contains(false))
    }

    /// 速さに連動する演出（電飾・光の尾と残像・火花）のどれか 1 つでも出すときだけ、指の動きを記録する。
    @Test func 指の動きは速さに連動する演出を出すときだけ記録する() {
        #expect(!SpinEffects.none.tracksDragMotion)
        #expect(SpinEffects.all.tracksDragMotion)
        for keyPath in [\SpinEffects.lights, \.trails, \.particles] {
            var effects = SpinEffects.none
            effects[keyPath: keyPath] = true
            #expect(effects.tracksDragMotion)
        }
        // 焦らし・停止の演出・演出の効果音だけでは記録しない
        #expect(!SpinEffects(lights: false, trails: false, particles: false, tease: true, stopEffects: true, sounds: true).tracksDragMotion)
    }
}
