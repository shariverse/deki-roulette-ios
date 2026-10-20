import Foundation

/// 共有に載せる結果の本文。Web 版には無い iOS 固有の機能で、両画面で共有する。
/// 文言そのものは `L10n` から渡し、ここでは組み立てだけを担う。
/// 入力は結果（ラベル）と文言・URL だけで、指定の有無や項目リストは受け取らない。本文に絵文字は足さない（項目の絵文字も載せない）。
enum ResultText {
    /// ルーレットの結果の文。「ルーレットで「ラーメン」に決まりました！」の形にする。
    /// 文は言語ごとに変わるので、ラベルの入る位置を `%@` にした型を呼び出し側が渡す。
    static func roulette(label: String, template: String) -> String {
        // ラベルは引数として渡すので、ラベルに `%` が含まれていても書式として読まない
        String(format: template, locale: nil, label)
    }

    /// 順番決めの結果。見出しの 1 行の下に「1. A チーム」を改行区切りで並べる。結果が空なら空文字。
    static func order(_ labels: [String], heading: String) -> String {
        guard !labels.isEmpty else { return "" }
        return heading + "\n" + numbered(labels)
    }

    /// 「1. A チーム」を改行区切りで並べる。
    static func numbered(_ labels: [String]) -> String {
        labels.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    /// X に渡す順番決めの本文。共有の本文（`share`）が X の上限（`XPostLength`）に収まればそのまま、
    /// 超えるときは並びの末尾から削って最後の行を「ほか M 件」（`others`）にし、収まる件数まで減らす。
    /// 1 件にしても収まらないとき（長いラベルと URL など）は 1 件のまま渡し、利用者に X で直してもらう。
    static func orderPost(
        _ labels: [String], heading: String, hashtag: String, appStoreURL: URL?, others: (Int) -> String
    ) -> String {
        let full = share(order(labels, heading: heading), hashtag: hashtag, appStoreURL: appStoreURL)
        guard !XPostLength.fits(full), labels.count > 1 else { return full }
        var text = full
        for kept in stride(from: labels.count - 1, through: 1, by: -1) {
            let body = heading + "\n" + numbered(Array(labels.prefix(kept))) + "\n" + others(labels.count - kept)
            text = share(body, hashtag: hashtag, appStoreURL: appStoreURL)
            if XPostLength.fits(text) { break }
        }
        return text
    }

    /// 共有シートに渡す本文。結果の本文の後に空行を挟んでハッシュタグを 1 行足し（アプリ名の代わり）、
    /// App Store の URL があればその次の行に付ける。指定の有無など、結果以外の情報は載せない。
    static func share(_ body: String, hashtag: String, appStoreURL: URL?) -> String {
        var text = "\(body)\n\n\(hashtag)"
        if let appStoreURL {
            text += "\n\(appStoreURL.absoluteString)"
        }
        return text
    }
}
