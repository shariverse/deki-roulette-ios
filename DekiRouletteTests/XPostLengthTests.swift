import Foundation
import Testing
@testable import DekiRoulette

struct XPostLengthTests {
    @Test func 英数字と記号は1字() {
        #expect(XPostLength.weightedLength("Ramen!") == 6)
        #expect(XPostLength.weightedLength("#DekiRoulette") == 13)
        #expect(XPostLength.weightedLength("a\n\nb") == 4)
        // U+2010〜201F（引用符・ダッシュ）も 1 字
        #expect(XPostLength.weightedLength("“A”—") == 4)
    }

    @Test func 日本語は2字() {
        #expect(XPostLength.weightedLength("寿司") == 4)
        #expect(XPostLength.weightedLength("「A」") == 5)
        #expect(XPostLength.weightedLength("#デキレーレット") == 15)
    }

    @Test func 絵文字は1つで2字() {
        #expect(XPostLength.weightedLength("🍣") == 2)
        #expect(XPostLength.weightedLength("👨‍👩‍👧") == 2)
        #expect(XPostLength.weightedLength("❤️") == 2)
        #expect(XPostLength.weightedLength("👍🏽") == 2)
    }

    @Test func URLは長さに依らず23字() {
        #expect(XPostLength.weightedLength("https://apps.apple.com/jp/app/very-long-name/id0000000000") == 23)
        #expect(XPostLength.weightedLength("#DekiRoulette\nhttps://apps.apple.com/app/id0000000000") == 13 + 1 + 23)
    }

    @Test func NFCに正規化してから数える() {
        // 「が」を「か」＋濁点の 2 つのコードポイントで書いても 1 文字（2 字）
        #expect(XPostLength.weightedLength("か\u{3099}") == 2)
    }

    @Test func 上限は280() {
        #expect(XPostLength.fits(String(repeating: "a", count: 280)))
        #expect(!XPostLength.fits(String(repeating: "a", count: 281)))
        #expect(XPostLength.fits(String(repeating: "あ", count: 140)))
        #expect(!XPostLength.fits(String(repeating: "あ", count: 141)))
    }
}
