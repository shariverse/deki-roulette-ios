import Foundation

/// X の投稿の文字数（twitter-text v3 の重み付きの長さ）。日本語などの全角は 2、英数字・記号の多くは 1 と数え、上限は 280。
/// NFC に正規化してからコードポイントごとに数え、絵文字は 1 つ（結合したシーケンスも）で 2、URL は長さに依らず 23 と数える。
enum XPostLength {
    /// 投稿の上限（重み付きの長さ）。
    static let limit = 280
    /// URL 1 つの長さ（t.co に短縮した長さ）。
    static let urlLength = 23

    /// 重み 1 で数えるコードポイントの範囲。これ以外は 2。
    private static let lightRanges: [ClosedRange<UInt32>] = [
        0x0000...0x10FF, 0x2000...0x200D, 0x2010...0x201F, 0x2032...0x2037,
    ]

    /// 本文の重み付きの長さ。
    static func weightedLength(_ text: String) -> Int {
        let normalized = text.precomposedStringWithCanonicalMapping
        var total = 0
        var token = ""
        for character in normalized {
            if character.isWhitespace {
                total += tokenLength(token) + weight(of: character)
                token = ""
            } else {
                token.append(character)
            }
        }
        return total + tokenLength(token)
    }

    /// 上限に収まるか。
    static func fits(_ text: String) -> Bool {
        weightedLength(text) <= limit
    }

    /// 空白で区切った 1 語の長さ。`http://` / `https://` で始まる語は URL として 23 と数える。
    private static func tokenLength(_ token: String) -> Int {
        if token.hasPrefix("https://") || token.hasPrefix("http://") { return urlLength }
        return token.reduce(0) { $0 + weight(of: $1) }
    }

    private static func weight(of character: Character) -> Int {
        if isEmoji(character) { return 2 }
        return character.unicodeScalars.reduce(0) { sum, scalar in
            sum + (lightRanges.contains { $0.contains(scalar.value) } ? 1 : 2)
        }
    }

    /// 絵文字として表示される文字か（既定で絵文字のもの、異体字セレクタ U+FE0F 付き、ZWJ でつないだもの）。
    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation
            || scalars.contains { $0.value == 0xFE0F || $0.value == 0x200D }
    }
}
