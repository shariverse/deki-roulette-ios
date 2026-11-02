import Foundation
import Testing
@testable import DekiRoulette

/// 「結果を共有」で共有シートに渡す項目の並びを確かめる。
struct ShareItemTests {
    private let text = ResultText.share(
        "ルーレットで「ラーメン」に決まりました！",
        hashtag: "#デキレーレット",
        appStoreURL: URL(string: "https://apps.apple.com/app/id6814132611")
    )

    @Test func 画像があれば画像と本文を別々の項目にする() {
        let items = ShareItem.items(image: "画像", text: text)
        #expect(items.count == 2)
        guard case .image(let image) = items.first else {
            Issue.record("先頭が画像でない")
            return
        }
        #expect(image == "画像")
        guard case .text(let shared) = items.last else {
            Issue.record("末尾が本文でない")
            return
        }
        // 本文は共有の本文そのまま（App Store の URL も本文の中）
        #expect(shared == text)
        #expect(shared.hasSuffix("\nhttps://apps.apple.com/app/id6814132611"))
    }

    @Test func 画像が無ければ本文だけにする() {
        let items = ShareItem<String>.items(image: nil, text: text)
        #expect(items.count == 1)
        guard case .text(let shared) = items.first else {
            Issue.record("本文でない")
            return
        }
        #expect(shared == text)
    }

    @Test func URLを本文とは別の項目にしない() {
        let items = ShareItem.items(image: "画像", text: text)
        // 画像と本文の 2 つだけで、URL の項目は足さない（X・LINE で URL が二重にならないように）
        let texts = items.compactMap { item -> String? in
            if case .text(let value) = item { return value }
            return nil
        }
        #expect(texts == [text])
    }
}
