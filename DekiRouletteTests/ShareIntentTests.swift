import Foundation
import Testing
@testable import DekiRoulette

struct ShareIntentTests {
    /// 符号化した値を戻すと元の本文になる（`removingPercentEncoding` は `+` を空白にしない）。
    private func decodedText(_ url: URL, prefix: String) throws -> String {
        let string = url.absoluteString
        #expect(string.hasPrefix(prefix))
        return try #require(String(string.dropFirst(prefix.count)).removingPercentEncoding)
    }

    @Test func Xの投稿画面のURLに本文を入れる() throws {
        let url = ShareIntent.xPost(text: "ルーレットで「ラーメン」に決まりました！\n\n#デキレーレット")
        #expect(url.scheme == "https")
        #expect(url.host() == "x.com")
        #expect(url.path() == "/intent/post")
        #expect(try decodedText(url, prefix: "https://x.com/intent/post?text=") == "ルーレットで「ラーメン」に決まりました！\n\n#デキレーレット")
    }

    @Test(arguments: [
        "ルーレットで「ラーメン」に決まりました！\n\n#デキレーレット\nhttps://apps.apple.com/app/id6814132611",
        "順番が決まりました！\n1. A & B\n2. C+D\n3. 50% off #1\nほか 3 件\n\n#デキレーレット",
        "🍣 寿司 🍜 ラーメン 👨‍👩‍👧",
        "a=b&message=injected#frag",
    ])
    func XアプリのURLのmessageに本文を入れる(text: String) throws {
        let url = ShareIntent.xAppPost(text: text)
        #expect(url.scheme == "twitter")
        #expect(url.host() == "post")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        // `&` `#` を含む本文でも、クエリは message の 1 つだけで、フラグメントは付かない
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.name == "message")
        #expect(components.fragment == nil)
        #expect(try decodedText(url, prefix: "twitter://post?message=") == text)
    }

    @Test func XはアプリのURLを先にWebのURLを後に開く() {
        let text = "順番が決まりました！\n1. A\n2. B\n\n#デキレーレット"
        let candidates = ShareIntent.xPostCandidates(text: text)
        #expect(candidates == [ShareIntent.xAppPost(text: text), ShareIntent.xPost(text: text)])
        #expect(candidates.map(\.scheme) == ["twitter", "https"])
        // Web の URL は今までと同じ
        #expect(candidates.last?.absoluteString == "https://x.com/intent/post?text=" + ShareIntent.percentEncoded(text))
    }

    @Test func LINEの送信画面のURLに本文を入れる() throws {
        let url = ShareIntent.lineShare(text: "The wheel picked “Ramen”!\n\n#DekiRoulette")
        #expect(url.host() == "line.me")
        #expect(url.path() == "/R/share")
        #expect(try decodedText(url, prefix: "https://line.me/R/share?text=") == "The wheel picked “Ramen”!\n\n#DekiRoulette")
    }

    @Test func 区切りの記号と空白と改行は百分率符号化する() {
        #expect(ShareIntent.percentEncoded("a&b=c?d#e+f g\nh/i%") == "a%26b%3Dc%3Fd%23e%2Bf%20g%0Ah%2Fi%25")
    }

    @Test func 非予約文字はそのまま残す() {
        #expect(ShareIntent.percentEncoded("AZaz09-._~") == "AZaz09-._~")
    }

    @Test func 日本語と絵文字はUTF8で符号化する() {
        #expect(ShareIntent.percentEncoded("寿司") == "%E5%AF%BF%E5%8F%B8")
        #expect(ShareIntent.percentEncoded("🍣") == "%F0%9F%8D%A3")
        // ZWJ でつないだ絵文字もバイトごとに符号化する
        #expect(ShareIntent.percentEncoded("👨‍👩") == "%F0%9F%91%A8%E2%80%8D%F0%9F%91%A9")
    }

    @Test(arguments: [
        "1. A & B チーム\n2. C+D\n3. 50% off?\n\n#デキレーレット",
        "a=b&text=injected#frag",
        "🍣 寿司 🍜 ラーメン 👨‍👩‍👧",
        "",
    ])
    func どんな本文でも1つのクエリの値として渡る(text: String) throws {
        for (url, prefix) in [
            (ShareIntent.xPost(text: text), "https://x.com/intent/post?text="),
            (ShareIntent.lineShare(text: text), "https://line.me/R/share?text="),
        ] {
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            // `&` `#` を含む本文でも、クエリは text の 1 つだけで、フラグメントは付かない
            #expect(components.queryItems?.count == 1)
            #expect(components.queryItems?.first?.name == "text")
            #expect(components.fragment == nil)
            #expect(try decodedText(url, prefix: prefix) == text)
        }
    }
}
