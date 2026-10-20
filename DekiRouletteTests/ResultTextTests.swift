import Testing
@testable import DekiRoulette

struct ResultTextTests {
    @Test func ルーレットの結果は見出しとラベルを半角コロンでつなぐ() {
        #expect(ResultText.roulette(label: "ラーメン", heading: "結果") == "結果: ラーメン")
        #expect(ResultText.roulette(label: "Ramen", heading: "Result") == "Result: Ramen")
    }

    @Test func 順番決めの結果は1始まりの番号付きで改行区切り() {
        let text = ResultText.order(["A チーム", "C チーム", "B チーム"])
        #expect(text == "1. A チーム\n2. C チーム\n3. B チーム")
    }

    @Test func 順番決めの結果が空なら空文字() {
        #expect(ResultText.order([]).isEmpty)
    }

    @Test func 共有本文は本文の後に空行を挟んでアプリ名を足す() {
        let body = ResultText.order(["A", "B"])
        #expect(ResultText.share(body, appName: "デキレーレット") == "1. A\n2. B\n\nデキレーレット")
        #expect(ResultText.share("Result: Ramen", appName: "DekiRoulette") == "Result: Ramen\n\nDekiRoulette")
    }

    @Test func 共有本文は結果の本文で始まりアプリ名で終わる() {
        let body = ResultText.roulette(label: "寿司", heading: "結果")
        let shared = ResultText.share(body, appName: "デキレーレット")
        #expect(shared.hasPrefix(body))
        #expect(shared.hasSuffix("デキレーレット"))
        // 結果以外の情報（指定の有無など）を混ぜていないこと
        #expect(shared.components(separatedBy: "\n").count == 3)
    }
}
