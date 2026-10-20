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

    @Test func 公開前はApp_StoreのURLを持たない() {
        // 推測した URL を入れない。公開したらこのテストごと直す
        #expect(Config.appStoreURL == nil)
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
        let banned = ["当たり", "必ず", "仕込み", "指定", "イカサマ", "win", "rig", "always", "target"]
        for key in keys {
            let text = bundle.localizedString(forKey: key, value: "<missing>", table: "Localizable")
            #expect(text != "<missing>")
            for word in banned {
                #expect(!text.lowercased().contains(word), "\(key) に \(word) が入っている")
            }
            #expect(!text.unicodeScalars.contains { $0.properties.isEmojiPresentation }, "\(key) に絵文字が入っている")
        }
        // ルーレットの文にはラベルの入る場所が 1 つだけある
        let roulette = bundle.localizedString(forKey: "shareRouletteResult", value: nil, table: "Localizable")
        #expect(roulette.components(separatedBy: "%@").count == 2)
        // ハッシュタグは 1 語
        let hashtag = bundle.localizedString(forKey: "shareHashtag", value: nil, table: "Localizable")
        #expect(hashtag.hasPrefix("#"))
        #expect(!hashtag.contains(" "))
    }
}
