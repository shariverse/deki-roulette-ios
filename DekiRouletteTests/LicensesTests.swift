import Foundation
import Testing
@testable import DekiRoulette

/// 設定の「ライセンス」に並べる一覧と、同梱した全文（Discussion #372 の Q4）。
struct LicensesTests {
    @Test func 一覧に同梱の書体がある() {
        #expect(Licenses.all.contains(Licenses.zenMaruGothic))
        #expect(Set(Licenses.all.map(\.id)).count == Licenses.all.count)
    }

    @Test(arguments: Licenses.all)
    func 各項目の全文がバンドルにあって読める(entry: LicenseEntry) throws {
        let text = try #require(entry.text())
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!entry.name.isEmpty)
        #expect(!entry.copyright.isEmpty)
        #expect(!entry.licenseName.isEmpty)
    }

    @Test func ZenMaruGothicの全文はOFLの原文() throws {
        let entry = Licenses.zenMaruGothic
        let text = try #require(entry.text())
        #expect(entry.name == "Zen Maru Gothic")
        #expect(entry.licenseName == "SIL Open Font License, Version 1.1")
        #expect(text.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(text.contains(entry.copyright))
    }

    @Test func 全文が見つからなければnil() {
        let missing = LicenseEntry(name: "x", copyright: "x", licenseName: "x", resource: "no-such-license", resourceExtension: "txt")
        #expect(missing.text() == nil)
    }

    @Test(arguments: ["ja", "en"])
    func 文言は各言語にある(language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        for key in ["licensesTitle", "licensesDescription"] {
            let text = bundle.localizedString(forKey: key, value: "<missing>", table: "Localizable")
            #expect(text != "<missing>")
            #expect(!text.isEmpty)
        }
    }
}

/// 全文の見せ方（段落の中の固定の改行をつなぐ）。語句は変えない。
struct LicenseTextTests {
    private static func ofl() throws -> String {
        try #require(Licenses.zenMaruGothic.text())
    }

    private static func squeezed(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    @Test func 空白を除けば原文と同じ文字の並び() throws {
        let text = try Self.ofl()
        #expect(Self.squeezed(LicenseText.paragraphs(text).joined()) == Self.squeezed(text))
    }

    @Test func 段落の中の改行をつなぐ() throws {
        let paragraphs = LicenseText.paragraphs(try Self.ofl())
        let preamble = try #require(paragraphs.first { $0.hasPrefix("PREAMBLE") })
        #expect(preamble.hasPrefix("PREAMBLE\nThe goals of the Open Font License (OFL) are to stimulate worldwide development of"))
        #expect(preamble.components(separatedBy: "\n").count == 2)
        let disclaimer = try #require(paragraphs.first { $0.hasPrefix("DISCLAIMER") })
        #expect(disclaimer.contains("WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED"))
        #expect(disclaimer.components(separatedBy: "\n").count == 2)
        let condition = try #require(paragraphs.first { $0.hasPrefix("1)") })
        #expect(!condition.contains("\n"))
    }

    @Test func 区切りの線は段落を分ける() throws {
        let paragraphs = LicenseText.paragraphs(try Self.ofl())
        let index = try #require(paragraphs.firstIndex { $0.hasPrefix("SIL OPEN FONT LICENSE Version 1.1") })
        #expect(index > 0 && index + 1 < paragraphs.count)
        #expect(LicenseText.isRule(paragraphs[index - 1]))
        #expect(LicenseText.isRule(paragraphs[index + 1]))
        #expect(!paragraphs.contains(""))
    }

    @Test func 見出しの判定() {
        #expect(LicenseText.isHeading("PREAMBLE"))
        #expect(LicenseText.isHeading("PERMISSION & CONDITIONS"))
        #expect(!LicenseText.isHeading("The goals of the Open Font License"))
        #expect(!LicenseText.isHeading("THE FONT SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND,"))
        #expect(!LicenseText.isHeading("---"))
        #expect(LicenseText.isRule("-----"))
        #expect(!LicenseText.isRule("--"))
    }
}
