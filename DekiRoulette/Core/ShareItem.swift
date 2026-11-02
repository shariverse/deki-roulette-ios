import Foundation

/// 「結果を共有」で共有シートに渡す 1 つの項目。画像と本文を別々の項目にして渡す（本文を画像に添えるだけだと、
/// 「メモ」など添えた本文を読まない共有先に画像しか届かない）。画像の型は呼び出し側が決める（View では `ShareImageFile`）。
/// 入力は結果の画像と共有の本文（`ResultText.share`）だけで、指定の有無や項目リストは受け取らない。
enum ShareItem<Image> {
    /// 結果の画像（PNG）。
    case image(Image)
    /// 共有の本文（ハッシュタグと App Store の URL 入り）。URL は本文の中にだけ置き、別の項目にはしない。
    case text(String)

    /// 共有シートに渡す項目の並び。画像があれば画像・本文の順の 2 つ、無ければ本文だけ。
    static func items(image: Image?, text: String) -> [ShareItem] {
        guard let image else { return [.text(text)] }
        return [.image(image), .text(text)]
    }
}

extension ShareItem: Sendable where Image: Sendable {}
