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

    @Test func 既定はすべてON() {
        #expect(SpinEffects.default == .all)
    }

    /// 全体が OFF なら、個別の選択に依らず何も付けない（今の「なし」と同じ）。ON なら個別の選択のまま。
    @Test func 全体がOFFなら何も付けない() {
        var partial = SpinEffects.all
        partial.trails = false
        partial.sounds = false
        for selected in [SpinEffects.all, .none, partial] {
            #expect(SpinEffects.effective(enabled: false, selected: selected) == .none)
            #expect(SpinEffects.effective(enabled: true, selected: selected) == selected)
        }
    }

    /// 個別のトグルは 6 つのフラグを 1 つずつ受け持ち、重ならない。
    @Test func 個別のトグルはフラグを1つずつ受け持つ() {
        #expect(SpinEffectItem.allCases.count == 6)
        for item in SpinEffectItem.allCases {
            var effects = SpinEffects.none
            effects[keyPath: item.keyPath] = true
            let others = SpinEffectItem.allCases.filter { $0 != item }
            #expect(others.allSatisfy { !effects[keyPath: $0.keyPath] }, "\(item)")
        }
        var all = SpinEffects.none
        for item in SpinEffectItem.allCases { all[keyPath: item.keyPath] = true }
        #expect(all == .all)
    }

    /// 保存のキーは重ならず、以前の 5 択の保存値（`spinEffectStyle`）は読まない。
    /// キーを変えると保存済みの選択が読めなくなる（既定の ON に戻る）ので、値も固定する。
    @Test func 保存のキーは重ならず以前の5択を読まない() {
        let keys = [Config.spinEffectsEnabledKey] + SpinEffectItem.allCases.map(Config.spinEffectKey)
        #expect(keys == [
            "spinEffects.enabled", "spinEffects.lights", "spinEffects.trails", "spinEffects.particles",
            "spinEffects.tease", "spinEffects.stopEffects", "spinEffects.sounds",
        ])
        #expect(Set(keys).count == keys.count)
        #expect(!keys.contains("spinEffectStyle"))
    }
}
