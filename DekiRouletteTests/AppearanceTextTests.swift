import Foundation
import Testing
@testable import DekiRoulette

/// 設定の「外観」の文言（Discussion #385）。
struct AppearanceTextTests {
    static let keys = ["appearanceTitle", "appearanceModeSystem", "appearanceModeLight", "appearanceModeDark", "appearanceNote"]

    @Test(arguments: ["ja", "en"])
    func 文言は日本語と英語の両方にある(language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        for key in Self.keys {
            let text = bundle.localizedString(forKey: key, value: "<missing>", table: "Localizable")
            #expect(text != "<missing>", "\(key)")
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key)")
        }
    }

    @Test func 選択肢の名前は互いに違う() {
        let names = AppearanceMode.allCases.map(L10n.appearanceModeName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == AppearanceMode.allCases.count)
    }
}
