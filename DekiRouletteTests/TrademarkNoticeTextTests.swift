import Foundation
import Testing
@testable import DekiRoulette

/// 設定の「著作権」に置く X・LINE の商標の注記（Discussion #358 の Q5）。
struct TrademarkNoticeTextTests {
    @Test(arguments: ["ja", "en"])
    func 注記は両社の社名と非提携を書く(language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let text = bundle.localizedString(forKey: "trademarkNotice", value: "<missing>", table: "Localizable")
        #expect(text != "<missing>")
        #expect(text.contains("X Corp."))
        #expect(text.contains("LY Corporation"))
        #expect(text.contains("LINE"))
    }

    @Test func 日本語は提携・承認の関係が無いことを書く() throws {
        let path = try #require(Bundle.main.path(forResource: "ja", ofType: "lproj"))
        let text = try #require(Bundle(path: path)).localizedString(forKey: "trademarkNotice", value: nil, table: "Localizable")
        #expect(text.contains("商標"))
        #expect(text.contains("提携・承認の関係にありません"))
    }

    @Test func 英語は提携・承認の関係が無いことを書く() throws {
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let text = try #require(Bundle(path: path)).localizedString(forKey: "trademarkNotice", value: nil, table: "Localizable")
        #expect(text.contains("trademark"))
        #expect(text.contains("not affiliated with or endorsed by"))
    }
}
