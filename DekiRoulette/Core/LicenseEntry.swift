import Foundation

/// 設定の「ライセンス」に並べる、アプリに同梱したもの 1 件のライセンス。名前・著作権・ライセンスの名前・全文は原文のまま出す（訳さない）。
/// 指定・印とは関わらない。
struct LicenseEntry: Identifiable, Hashable, Sendable {
    /// 同梱したもの（書体・ライブラリ）の名前。
    let name: String
    /// 著作権の行。
    let copyright: String
    /// ライセンスの名前。
    let licenseName: String
    /// 全文のリソース名と拡張子（バンドルに同梱する）。
    let resource: String
    let resourceExtension: String

    var id: String { name }

    /// バンドルから全文を読む。見つからない・読めないときは nil。
    func text(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: resource, withExtension: resourceExtension) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// 同梱したもののライセンスの一覧。ライブラリを足したら 1 件足し、全文のファイルをバンドルに置く。
enum Licenses {
    static let zenMaruGothic = LicenseEntry(
        name: AppFont.familyName,
        copyright: "Copyright 2021 The Zen Maru Gothic Project Authors",
        licenseName: "SIL Open Font License, Version 1.1",
        resource: AppFont.licenseResource,
        resourceExtension: AppFont.licenseExtension
    )

    static let all: [LicenseEntry] = [zenMaruGothic]
}

/// ライセンスの全文の見せ方。原文は 70 桁ほどで改行してあり、そのまま狭い画面で折り返すと行がばらばらに切れるので、
/// 段落（空行で区切る）の中の改行だけをつないで、画面の幅で折り返させる。語句は変えない（並び・綴り・記号は原文のまま）。
/// 区切りの線（`---`）は 1 つの段落として分け、段落の先頭の見出し（`PREAMBLE` のような大文字だけの短い行）は次の行とつながず 1 行のまま残す。
enum LicenseText {
    /// 見出しとみなす行の長さの上限。本文の大文字の行（`DISCLAIMER` の段落）を見出しと取り違えないため。
    static let headingMaxLength = 30

    /// 画面に並べる段落。段落の中では行同士を空白 1 つでつなぎ、先頭の見出しの後だけ改行で区切る。
    static func paragraphs(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var result: [String] = []
        var current: [String] = []
        func flush() {
            guard !current.isEmpty else { return }
            result.append(join(current))
            current = []
        }
        for raw in normalized.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if isRule(line) {
                flush()
                result.append(line)
            } else {
                current.append(line)
            }
        }
        flush()
        return result
    }

    private static func join(_ lines: [String]) -> String {
        var output = ""
        for (index, line) in lines.enumerated() {
            if index > 0 {
                output += index == 1 && isHeading(lines[0]) ? "\n" : " "
            }
            output += line
        }
        return output
    }

    /// 区切りの線（`-` だけの行）。
    static func isRule(_ line: String) -> Bool {
        line.count >= 3 && line.allSatisfy { $0 == "-" }
    }

    /// 見出し（英字の小文字を含まない短い行）。
    static func isHeading(_ line: String) -> Bool {
        line.count <= headingMaxLength
            && line.contains { $0.isLetter }
            && !line.contains { $0.isLowercase }
    }
}
