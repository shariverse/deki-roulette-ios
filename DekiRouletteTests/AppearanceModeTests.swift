import SwiftUI
import Testing
import UIKit
@testable import DekiRoulette

struct AppearanceModeTests {
    /// 既定が端末の外観に従うので、設定していない利用者の見た目は変わらない。
    @Test func 既定は端末の外観に従う() {
        #expect(AppearanceMode.default == .system)
    }

    /// 保存値が変わると、保存済みの設定が読めなくなって既定に戻る。
    @Test func 保存値は変えない() {
        #expect(AppearanceMode.allCases.map(\.rawValue) == ["system", "light", "dark"])
    }

    @Test func 保存した値はそのまま読める() {
        for mode in AppearanceMode.allCases {
            #expect(AppearanceMode(storedValue: mode.rawValue) == mode)
        }
    }

    @Test(arguments: [nil, "", "Dark", "LIGHT", "sepia", " dark"] as [String?])
    func 未設定と読めない値は端末の外観に従う(stored: String?) {
        #expect(AppearanceMode(storedValue: stored) == .system)
    }

    @Test func SwiftUIに渡す外観() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test func UIKitに渡す外観() {
        #expect(AppearanceMode.system.userInterfaceStyle == .unspecified)
        #expect(AppearanceMode.light.userInterfaceStyle == .light)
        #expect(AppearanceMode.dark.userInterfaceStyle == .dark)
    }

    /// `@AppStorage` は RawRepresentable の値を `rawValue` の文字列で保存し、読めない文字列は既定値として読む。
    /// アプリの根と設定画面は同じキー・同じ既定値で持つので、この読み方が `init(storedValue:)` と一致することを確かめる。
    @MainActor
    @Test(arguments: [nil, "system", "light", "dark", "", "sepia"] as [String?])
    func AppStorageの読み方と一致する(stored: String?) throws {
        let suite = "AppearanceModeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        if let stored { defaults.set(stored, forKey: Config.appearanceModeKey) }
        let storage = AppStorage(wrappedValue: AppearanceMode.default, Config.appearanceModeKey, store: defaults)
        #expect(storage.wrappedValue == AppearanceMode(storedValue: stored))
    }
}
