import Foundation

/// 共有に載せる結果の本文。Web 版には無い iOS 固有の機能で、両画面で共有する。
/// 文言そのものは `L10n` から渡し、ここでは組み立てだけを担う。
enum ResultText {
    /// ルーレットの結果 1 行。「結果: ラーメン」の形にする。
    /// 見出し語は言語ごとに変わるので呼び出し側が渡す。区切りは日英とも半角の「: 」で固定。
    static func roulette(label: String, heading: String) -> String {
        "\(heading): \(label)"
    }

    /// 順番決めの結果。「1. A チーム」を改行区切りで並べる。
    static func order(_ labels: [String]) -> String {
        labels.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    /// 共有シートに渡す本文。結果の本文の後に空行を挟んでアプリ名を 1 行足す。
    /// 指定の有無など、結果以外の情報は載せない。
    static func share(_ body: String, appName: String) -> String {
        "\(body)\n\n\(appName)"
    }
}
