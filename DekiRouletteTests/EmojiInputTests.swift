import Testing
@testable import DekiRoulette

struct EmojiInputTests {
    @Test(arguments: [
        "🍣",
        "😀",
        "👍🏽", // 肌色
        "👨‍👩‍👧‍👦", // ZWJ 結合
        "🧑🏻‍💻", // 肌色と ZWJ
        "🇯🇵", // 国旗
        "🏳️‍🌈", // 異体字セレクタと ZWJ
        "❤️", // 異体字セレクタ付き
        "☺️",
        "1️⃣", // キーキャップ
        "#️⃣",
    ])
    func 絵文字は1文字として通る(input: String) {
        #expect(EmojiInput.normalize(input) == Character(input))
    }

    @Test(arguments: [
        "1", "9", "#", "*", // isEmoji だけ真になる文字
        "©", "™", "❤", // 異体字セレクタなしの文字表示
        "あ", "漢", "A", "a", "!",
    ])
    func 絵文字でない文字は弾く(input: String) {
        #expect(EmojiInput.normalize(input) == nil)
    }

    @Test(arguments: ["", " ", "\n", "  \t "])
    func 空はnil(input: String) {
        #expect(EmojiInput.normalize(input) == nil)
    }

    @Test
    func 二文字以上は先頭の1文字だけ残す() {
        #expect(EmojiInput.normalize("🍣🍕") == "🍣")
        #expect(EmojiInput.normalize("👨‍👩‍👧‍👦🍣") == "👨‍👩‍👧‍👦")
        #expect(EmojiInput.normalize("🇯🇵🇺🇸") == "🇯🇵")
        #expect(EmojiInput.normalize("🍣すし") == "🍣")
    }

    @Test
    func 前後の空白は落とす() {
        #expect(EmojiInput.normalize("  🍣 ") == "🍣")
        #expect(EmojiInput.normalize("\n🍣\n") == "🍣")
    }

    @Test
    func 先頭が絵文字でなければ弾く() {
        #expect(EmojiInput.normalize("あ🍣") == nil)
        #expect(EmojiInput.normalize("1🍣") == nil)
    }
}
