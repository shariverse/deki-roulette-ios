import Foundation
import Testing
@testable import DekiRoulette

struct ResultTextTests {
    private static let appStoreURL = URL(string: "https://apps.apple.com/app/id0000000000")!

    @Test func ルーレットの結果は文の型にラベルを入れる() {
        #expect(ResultText.roulette(label: "ラーメン", template: "ルーレットで「%@」に決まりました！") == "ルーレットで「ラーメン」に決まりました！")
        #expect(ResultText.roulette(label: "Ramen", template: "The wheel picked “%@”!") == "The wheel picked “Ramen”!")
    }

    @Test func ラベルの記号は書式として読まない() {
        // ラベルに % や %@ が含まれていても、そのまま本文に入る
        #expect(ResultText.roulette(label: "100%@ 本気", template: "「%@」") == "「100%@ 本気」")
        #expect(ResultText.roulette(label: "50%", template: "「%@」") == "「50%」")
    }

    @Test func 順番決めの結果は見出しの下に1始まりの番号付きで改行区切り() {
        let text = ResultText.order(["A チーム", "C チーム", "B チーム"], heading: "順番が決まりました！")
        #expect(text == "順番が決まりました！\n1. A チーム\n2. C チーム\n3. B チーム")
    }

    @Test func 順番決めの結果が空なら空文字() {
        #expect(ResultText.order([], heading: "順番が決まりました！").isEmpty)
    }

    @Test func 共有本文は本文の後に空行を挟んでハッシュタグを足す() {
        let body = ResultText.order(["A", "B"], heading: "順番が決まりました！")
        #expect(ResultText.share(body, hashtag: "#デキレーレット", appStoreURL: nil) == "順番が決まりました！\n1. A\n2. B\n\n#デキレーレット")
        #expect(
            ResultText.share("The wheel picked “Ramen”!", hashtag: "#DekiRoulette", appStoreURL: nil)
                == "The wheel picked “Ramen”!\n\n#DekiRoulette"
        )
    }

    @Test func App_StoreのURLがあればハッシュタグの次の行に付く() {
        let shared = ResultText.share("ルーレットで「寿司」に決まりました！", hashtag: "#デキレーレット", appStoreURL: Self.appStoreURL)
        #expect(shared == "ルーレットで「寿司」に決まりました！\n\n#デキレーレット\nhttps://apps.apple.com/app/id0000000000")
    }

    @Test func App_StoreのURLが無ければリンクは付かない() {
        let shared = ResultText.share("ルーレットで「寿司」に決まりました！", hashtag: "#デキレーレット", appStoreURL: nil)
        #expect(!shared.contains("http"))
        #expect(shared.hasSuffix("#デキレーレット"))
    }

    @Test func App_StoreのURLは国を含まない製品ページ() throws {
        let url = try #require(Config.appStoreURL)
        #expect(url.scheme == "https")
        #expect(url.host() == "apps.apple.com")
        #expect(url.lastPathComponent == "id6814132611")
        // 国のパス（/us/・/jp/ など）を付けず、利用者の国の Store で開かせる
        #expect(url.pathComponents == ["/", "app", "id6814132611"])
        #expect(url.query() == nil)
    }

    @Test(arguments: [("ja", "あ"), ("en", "W")])
    func ルーレットの本文はApp_StoreのURL入りでもXの上限に収まる(language: String, letter: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let template = bundle.localizedString(forKey: "shareRouletteResult", value: nil, table: "Localizable")
        let hashtag = bundle.localizedString(forKey: "shareHashtag", value: nil, table: "Localizable")
        // ラベルの上限の長さ
        let label = String(repeating: letter, count: Config.maxLabelLength)
        let shared = ResultText.share(
            ResultText.roulette(label: label, template: template), hashtag: hashtag, appStoreURL: Config.appStoreURL
        )
        #expect(XPostLength.fits(shared))
        #expect(shared.hasSuffix("\(hashtag)\n\(try #require(Config.appStoreURL).absoluteString)"))
    }

    @Test func 順番決めの本文はApp_StoreのURL入りでもXの上限に収める() throws {
        let url = try #require(Config.appStoreURL)
        // 上限の件数・上限の長さの日本語のラベル
        let labels = (1...Config.maxItems).map { String(repeating: "う", count: Config.maxLabelLength - 1) + String($0 % 10) }
        let post = ResultText.orderPost(
            labels, heading: "順番が決まりました！", hashtag: "#デキレーレット", appStoreURL: url, others: Self.others
        )
        #expect(XPostLength.fits(post))
        #expect(post.contains("ほか "))
        #expect(post.hasSuffix("#デキレーレット\n\(url.absoluteString)"))
    }

    @Test func ルーレットの共有本文は結果の文とハッシュタグの3行だけ() {
        let body = ResultText.roulette(label: "寿司", template: L10n.shareRouletteResult)
        let shared = ResultText.share(body, hashtag: L10n.shareHashtag, appStoreURL: nil)
        #expect(shared.hasPrefix(body))
        #expect(shared.hasSuffix(L10n.shareHashtag))
        // 結果以外の情報（指定の有無など）を混ぜていないこと
        #expect(shared.components(separatedBy: "\n") == [body, "", L10n.shareHashtag])
        #expect(body.contains("寿司"))
    }

    @Test func 順番決めの共有本文は見出しと並びとハッシュタグだけ() {
        let body = ResultText.order(["A", "B", "C"], heading: L10n.shareOrderHeading)
        let lines = ResultText.share(body, hashtag: L10n.shareHashtag, appStoreURL: nil).components(separatedBy: "\n")
        #expect(lines == [L10n.shareOrderHeading, "1. A", "2. B", "3. C", "", L10n.shareHashtag])
    }

    @Test(arguments: ["ja", "en"])
    func 共有の文言にステルスで禁じた語と絵文字を入れない(language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let keys = ["shareRouletteResult", "shareOrderHeading", "shareHashtag"]
        let bannedJapanese = ["当たり", "必ず", "仕込み", "指定", "イカサマ"]
        // 英語は単語で比べる（部分一致だと original・window のような無害な語にも当たる）
        let bannedEnglish: Set<String> = ["win", "winner", "rig", "rigged", "always", "target", "fixed"]
        for key in keys {
            let text = bundle.localizedString(forKey: key, value: "<missing>", table: "Localizable")
            #expect(text != "<missing>")
            for word in bannedJapanese {
                #expect(!text.contains(word), "\(key) に \(word) が入っている")
            }
            let words = text.lowercased().split { !$0.isLetter }.map(String.init)
            #expect(bannedEnglish.isDisjoint(with: words), "\(key) に禁じた語が入っている")
            // 既定で絵文字のもの・U+FE0F で絵文字になるもの・ZWJ でつないだものを絵文字とみなす
            let hasEmoji = text.contains { character in
                let scalars = character.unicodeScalars
                guard let first = scalars.first, first.properties.isEmoji else { return false }
                return first.properties.isEmojiPresentation || scalars.contains { $0.value == 0xFE0F || $0.value == 0x200D }
            }
            #expect(!hasEmoji, "\(key) に絵文字が入っている")
        }
        // ルーレットの文にはラベルの入る場所が 1 つだけある
        let roulette = bundle.localizedString(forKey: "shareRouletteResult", value: nil, table: "Localizable")
        #expect(roulette.components(separatedBy: "%@").count == 2)
        // ハッシュタグは 1 語
        let hashtag = bundle.localizedString(forKey: "shareHashtag", value: nil, table: "Localizable")
        #expect(hashtag.hasPrefix("#"))
        #expect(!hashtag.contains(" "))
    }

    // MARK: X に渡す順番決めの本文

    private static func others(_ count: Int) -> String { "ほか \(count) 件" }

    @Test func Xの上限に収まる順番決めはそのまま渡す() {
        let labels = ["A チーム", "B チーム", "C チーム", "D チーム"]
        let post = ResultText.orderPost(labels, heading: "順番が決まりました！", hashtag: "#デキレーレット", appStoreURL: nil, others: Self.others)
        let full = ResultText.share(ResultText.order(labels, heading: "順番が決まりました！"), hashtag: "#デキレーレット", appStoreURL: nil)
        #expect(post == full)
    }

    @Test func Xの上限を超える順番決めは上位から入るだけ載せてほかM件にする() {
        // 20 文字の日本語のラベルが 24 件。全部では 280 を大きく超える
        let labels = (1...24).map { String(repeating: "あ", count: 19) + String($0 % 10) }
        let full = ResultText.share(ResultText.order(labels, heading: "順番が決まりました！"), hashtag: "#デキレーレット", appStoreURL: nil)
        #expect(!XPostLength.fits(full))

        let post = ResultText.orderPost(labels, heading: "順番が決まりました！", hashtag: "#デキレーレット", appStoreURL: nil, others: Self.others)
        #expect(XPostLength.fits(post))
        let lines = post.components(separatedBy: "\n")
        #expect(lines.first == "順番が決まりました！")
        #expect(lines.suffix(2) == ["", "#デキレーレット"])
        // 見出しの次から上位が順に並び、最後に残りの件数
        let ranked = lines.dropFirst().dropLast(3)
        #expect(!ranked.isEmpty)
        for (offset, line) in ranked.enumerated() {
            #expect(line == "\(offset + 1). \(labels[offset])")
        }
        #expect(lines[lines.count - 3] == "ほか \(labels.count - ranked.count) 件")
        // 載せられる件数をすべて載せている（1 件増やすと超える）
        let oneMore = ResultText.share(
            "順番が決まりました！\n" + ResultText.numbered(Array(labels.prefix(ranked.count + 1))) + "\n" + Self.others(labels.count - ranked.count - 1),
            hashtag: "#デキレーレット", appStoreURL: nil
        )
        #expect(!XPostLength.fits(oneMore))
    }

    @Test func App_StoreのURLも数に入れて収める() {
        let url = URL(string: "https://apps.apple.com/app/id0000000000")!
        let labels = (1...24).map { String(repeating: "い", count: 19) + String($0 % 10) }
        let post = ResultText.orderPost(labels, heading: "順番が決まりました！", hashtag: "#デキレーレット", appStoreURL: url, others: Self.others)
        #expect(XPostLength.fits(post))
        #expect(post.hasSuffix("#デキレーレット\nhttps://apps.apple.com/app/id0000000000"))
    }

    @Test func 日本語と英語の初期項目の上限の件数でも収まる() {
        // 項目の上限（24 件）・ラベルの上限（20 文字）の英数字なら 1 字ずつなので全部載ることもある
        let labels = (1...Config.maxItems).map { "Team \($0)" }
        let post = ResultText.orderPost(labels, heading: "The order is set!", hashtag: "#DekiRoulette", appStoreURL: nil, others: { "+\($0) more" })
        #expect(XPostLength.fits(post))
    }
}
