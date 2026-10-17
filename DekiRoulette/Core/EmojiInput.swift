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
    /// 既定で絵文字として表示される文字（`isEmojiPresentation`）か、異体字セレクタ（U+FE0F）・肌色・ZWJ・キーキャップで
    /// 絵文字の表示にした並びだけを通す。
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        if first.properties.isEmojiPresentation { return true }
        return scalars.dropFirst().contains { scalar in
            scalar == emojiVariationSelector
                || scalar == zeroWidthJoiner
                || scalar == combiningEnclosingKeycap
                || scalar.properties.isEmojiModifier
        }
    }

    private static let emojiVariationSelector: Unicode.Scalar = "\u{FE0F}"
    private static let zeroWidthJoiner: Unicode.Scalar = "\u{200D}"
    private static let combiningEnclosingKeycap: Unicode.Scalar = "\u{20E3}"
}
