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
        "🧑🏻‍🤝‍🧑🏼", // 肌色の違う 2 人の ZWJ 結合
        "🏴󠁧󠁢󠁥󠁮󠁧󠁿", // タグ付きの旗
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

    @Test(arguments: [
        "1\u{1F3FD}", // 肌色を受けない文字に肌色
        "#\u{1F3FD}",
        "©\u{1F3FD}",
        "1\u{200D}", // 後ろに絵文字が続かない ZWJ
        "™\u{200D}",
        "1\u{FE0F}", // キーキャップの無い数字
        "#\u{FE0F}",
        "\u{1F1EF}", // 国旗の片割れ
        "🍣\u{FE0E}", // 文字表示の異体字セレクタ
        "☺\u{FE0E}",
        "\u{1F3FD}", // 肌色の修飾子だけ
    ])
    func 絵文字に見えない並びは弾く(input: String) {
        #expect(EmojiInput.normalize(input) == nil)
    }

    @Test
    func 数字のあとにZWJと絵文字が続いても弾く() {
        // 先頭の書記素は「1 と ZWJ」で、絵文字は 2 文字目になる
        #expect(EmojiInput.normalize("1\u{200D}🍣") == nil)
    }

    // MARK: 入力欄の確定

    @Test
    func 確定した絵文字を見た目にする() {
        #expect(EmojiInput.commit("🍣", current: .auto) == .set(.emoji("🍣"), text: "🍣"))
        #expect(EmojiInput.commit(" 🍣 ", current: .color(.blue)) == .set(.emoji("🍣"), text: "🍣"))
        #expect(EmojiInput.commit("👨‍👩‍👧‍👦", current: .auto) == .set(.emoji("👨‍👩‍👧‍👦"), text: "👨‍👩‍👧‍👦"))
    }

    @Test
    func 二文字以上は先頭の1文字にして欄も詰める() {
        #expect(EmojiInput.commit("🍣🍕", current: .auto) == .set(.emoji("🍣"), text: "🍣"))
        #expect(EmojiInput.commit("🍣すし", current: .color(.red)) == .set(.emoji("🍣"), text: "🍣"))
    }

    @Test
    func 今の絵文字の後ろに足した絵文字に差し替える() {
        #expect(EmojiInput.commit("🍣🍕", current: .emoji("🍣")) == .set(.emoji("🍕"), text: "🍕"))
        #expect(EmojiInput.commit("🍣🍕🍔", current: .emoji("🍣")) == .set(.emoji("🍕"), text: "🍕"))
        // 足した分が絵文字でなければ、先頭（今の絵文字）のまま
        #expect(EmojiInput.commit("🍣あ", current: .emoji("🍣")) == .keep(text: "🍣"))
    }

    @Test
    func 今と同じ絵文字は変えない() {
        #expect(EmojiInput.commit("🍣", current: .emoji("🍣")) == .keep(text: "🍣"))
    }

    @Test
    func 絵文字でない入力は受け付けず欄を戻す() {
        #expect(EmojiInput.commit("すし", current: .auto) == .rejected(text: ""))
        #expect(EmojiInput.commit("1", current: .color(.blue)) == .rejected(text: ""))
        #expect(EmojiInput.commit("あ🍣", current: .emoji("🍕")) == .rejected(text: "🍕"))
    }

    @Test
    func 空にすると絵文字の項目は自動に戻り他はそのまま() {
        #expect(EmojiInput.commit("", current: .emoji("🍣")) == .set(.auto, text: ""))
        #expect(EmojiInput.commit("  ", current: .emoji("🍣")) == .set(.auto, text: ""))
        #expect(EmojiInput.commit("", current: .auto) == .keep(text: ""))
        #expect(EmojiInput.commit("", current: .color(.pink)) == .keep(text: ""))
    }
}
