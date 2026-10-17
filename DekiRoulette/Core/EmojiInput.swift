import Foundation

/// 絵文字の入力欄の値を、見た目に使う絵文字 1 文字に正規化する。
enum EmojiInput {
    /// 前後の空白を落とした先頭の 1 書記素が絵文字ならそれを返す。空・絵文字でないときは nil。
    /// 2 文字以上の入力は先頭の 1 文字だけ残す。
    static func normalize(_ raw: String) -> Character? {
        guard let first = raw.trimmingCharacters(in: .whitespacesAndNewlines).first, isEmoji(first) else { return nil }
        return first
    }

    /// 絵文字として表示される 1 書記素か。
    ///
    /// `Unicode.Scalar.Properties.isEmoji` は数字・`#`・`*` などでも真になるので、それだけでは判定しない。
    /// 既定で絵文字として表示される文字（`isEmojiPresentation`）か、異体字セレクタ（U+FE0F）・肌色・ZWJ で
    /// 絵文字の表示にした並びだけを通す。ただし次は弾く:
    /// - 文字表示の異体字セレクタ（U+FE0E）を含む並び
    /// - 地域指示子が 2 つ揃っていない国旗の片割れ
    /// - 数字・`#`・`*` で始まり、キーキャップ（U+20E3）で終わらない並び
    /// - 後ろに絵文字が続かない ZWJ、肌色を受けない文字に付いた肌色
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = Array(character.unicodeScalars)
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        if scalars.contains(textVariationSelector) { return false }
        if isRegionalIndicator(first) {
            return scalars.count == 2 && isRegionalIndicator(scalars[1])
        }
        if first.isASCII {
            return scalars.last == combiningEnclosingKeycap
        }
        for (offset, scalar) in scalars.enumerated() where scalar == zeroWidthJoiner {
            guard offset + 1 < scalars.count else { return false }
            let next = scalars[offset + 1]
            guard next.properties.isEmoji, !next.isASCII else { return false }
        }
        if !first.properties.isEmojiModifierBase, scalars.dropFirst().contains(where: \.properties.isEmojiModifier) {
            return false
        }
        if first.properties.isEmojiPresentation { return true }
        return scalars.dropFirst().contains { scalar in
            scalar == emojiVariationSelector
                || scalar == zeroWidthJoiner
                || scalar.properties.isEmojiModifier
        }
    }

    private static func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
        (0x1F1E6...0x1F1FF).contains(scalar.value)
    }

    private static let emojiVariationSelector: Unicode.Scalar = "\u{FE0F}"
    private static let textVariationSelector: Unicode.Scalar = "\u{FE0E}"
    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"
    private static let combiningEnclosingKeycap: Unicode.Scalar = "\u{20E3}"
}
