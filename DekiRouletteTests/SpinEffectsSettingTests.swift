import Foundation
import Testing
@testable import DekiRoulette

/// 設定の「スピンの演出」の読み書き（`SpinEffectsSetting`）。`UserDefaults.standard` のキーを書き換えるので、1 つずつ流して後で消す。
@MainActor
@Suite(.serialized)
struct SpinEffectsSettingTests {
    private let keys = [Config.spinEffectsEnabledKey] + SpinEffectItem.allCases.map(Config.spinEffectKey)

    private func clear() {
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    @Test func 未設定ならすべてON() {
        clear()
        defer { clear() }
        let setting = SpinEffectsSetting()
        #expect(setting.enabled)
        #expect(setting.selected == .all)
        #expect(setting.effects == .all)
    }

    /// 個別のトグルは、そのキーとそのフラグだけを書き換える（キーと `binding(for:)` の取り違えに気づくため）。
    @Test func 個別のトグルはそのキーとフラグだけを書く() {
        defer { clear() }
        for item in SpinEffectItem.allCases {
            clear()
            SpinEffectsSetting().binding(for: item).wrappedValue = false
            #expect(UserDefaults.standard.object(forKey: Config.spinEffectKey(item)) as? Bool == false, "\(item)")
            let others = keys.filter { $0 != Config.spinEffectKey(item) }
            #expect(others.allSatisfy { UserDefaults.standard.object(forKey: $0) == nil }, "\(item)")
            var expected = SpinEffects.all
            expected[keyPath: item.keyPath] = false
            #expect(SpinEffectsSetting().selected == expected, "\(item)")
        }
    }

    @Test func 全体をOFFにすると何も付けないが個別の選択は残す() {
        clear()
        defer { clear() }
        SpinEffectsSetting().binding(for: .trails).wrappedValue = false
        SpinEffectsSetting().enabledBinding.wrappedValue = false
        var selected = SpinEffects.all
        selected.trails = false
        let setting = SpinEffectsSetting()
        #expect(!setting.enabled)
        #expect(setting.effects == .none)
        #expect(setting.selected == selected)
        // 全体を ON に戻すと、残した選択で付ける
        SpinEffectsSetting().enabledBinding.wrappedValue = true
        #expect(SpinEffectsSetting().effects == selected)
    }
}
