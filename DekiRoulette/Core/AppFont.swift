import SwiftUI

/// 同梱の書体（Zen Maru Gothic。SIL Open Font License 1.1）。
///
/// フォントのファイルは Google Fonts の配布（`google/fonts` の `ofl/zenmarugothic`）を改変せずに置いている
/// （`Resources/Fonts`。サブセット化・名前の変更をしない）。登録は `project.yml` の `UIAppFonts` で、ファイル名は `Face.fileName` と合わせる。
/// 太さは `.weight(_:)` / `.bold()` で出さず（合成の太字やフェイスの取り違えになる）、`face(for:)` で選んだフェイスの PostScript 名で出す。
/// View からは `Theme.Typography` 経由で使う。
enum AppFont {
    /// 書体の名前（ライセンスの表示などに使う。訳さない）。
    static let familyName = "Zen Maru Gothic"
    /// 同梱したライセンス文（`OFL.txt` のまま）のリソース名と拡張子。
    static let licenseResource = "ZenMaruGothic-OFL"
    static let licenseExtension = "txt"

    /// 同梱したフェイス。Light・Medium は使っていないので同梱しない。
    enum Face: CaseIterable, Sendable {
        case regular
        case bold
        case black

        /// `UIFont(name:size:)` / `Font.custom` に渡す名前。
        var postScriptName: String {
            switch self {
            case .regular: "ZenMaruGothic-Regular"
            case .bold: "ZenMaruGothic-Bold"
            case .black: "ZenMaruGothic-Black"
            }
        }

        /// `.app` の直下に置かれるファイル名（`UIAppFonts` の値）。
        var fileName: String { postScriptName + ".ttf" }
    }

    /// 太さから使うフェイスを選ぶ。regular 以下 → Regular、medium・semibold・bold → Bold、heavy・black → Black。
    static func face(for weight: Font.Weight) -> Face {
        switch weight {
        case .medium, .semibold, .bold: .bold
        case .heavy, .black: .black
        default: .regular
        }
    }

    /// テキストスタイルの既定の太さ。システムの書体でも `.headline` だけは semibold で、`.font(.headline)` の見た目の太さを保つ。
    static func defaultWeight(for style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }
}
