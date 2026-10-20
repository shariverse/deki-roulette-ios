import Foundation

/// 結果の本文を X・LINE の投稿画面に渡す Web の URL。アプリが入っていればアプリが、無ければブラウザが開く。
/// 投稿は利用者が各アプリで確定する（API による投稿はしない）。入力は共有の本文だけで、指定や項目リストは受け取らない。
enum ShareIntent {
    /// X の投稿画面。`text` に本文を入れる。
    static func xPost(text: String) -> URL {
        url(base: "https://x.com/intent/post?text=", text: text)
    }

    /// LINE の送信先を選ぶ画面。`text` に本文を入れる（UTF-8 の百分率符号化が必要）。
    static func lineShare(text: String) -> URL {
        url(base: "https://line.me/R/share?text=", text: text)
    }

    /// クエリの値として安全に渡すため、RFC 3986 の非予約文字（英数字と `-._~`）以外をすべて UTF-8 の百分率符号化にする。
    /// `URLComponents` の `queryItems` は `+` `&` などを思った通りに符号化しないことがあるので使わない。
    static func percentEncoded(_ text: String) -> String {
        var result = ""
        for byte in text.utf8 {
            if isUnreserved(byte) {
                result.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                result += String(format: "%%%02X", byte)
            }
        }
        return result
    }

    private static func url(base: String, text: String) -> URL {
        // 符号化した値は ASCII の英数字と `%` `-._~` だけなので、URL として必ず読める
        URL(string: base + percentEncoded(text))!
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            true
        case UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
            true
        default:
            false
        }
    }
}
