import Foundation
import Testing
import UIKit
@testable import DekiRoulette

struct AppIconChoiceTests {
    @Test func 先頭は既定のアイコンで代替の名前を持たない() {
        #expect(AppIconChoice.allCases.first == .standard)
        #expect(AppIconChoice.standard.alternateIconName == nil)
    }

    /// 名前が変わると、利用者が選んだアイコン（`alternateIconName` に名前で残る）が読めなくなる。
    @Test func 名前は変えない() {
        #expect(AppIconChoice.allCases.map(\.rawValue) == ["AppIcon", "AppIcon-Neon", "AppIcon-Pastel", "AppIcon-Spinner", "AppIcon-Target"])
    }

    @Test(arguments: AppIconChoice.allCases)
    func 今のアイコンの名前から選択を戻せる(choice: AppIconChoice) {
        #expect(AppIconChoice(alternateIconName: choice.alternateIconName) == choice)
    }

    @Test func 名前が無いときは既定のアイコン() {
        #expect(AppIconChoice(alternateIconName: nil) == .standard)
    }

    /// 既定のアイコンの名前は代替アイコンとしては登録していない。消した代替アイコンの名前なども、どれも選ばれていない扱いにする。
    @Test func 一覧に無い名前はどれも選ばない() {
        #expect(AppIconChoice(alternateIconName: "AppIcon") == nil)
        #expect(AppIconChoice(alternateIconName: "AppIcon-Casino") == nil)
        #expect(AppIconChoice(alternateIconName: "") == nil)
    }

    /// `project.yml`（`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`）とスクリプトの名前の食い違いを、ビルドした Info.plist で見つける。
    /// `Bundle.object(forInfoDictionaryKey:)` は端末に合わない `~ipad` のキーを返さないので、`.app` の Info.plist をそのまま読む。
    /// visionOS には代替アイコンが無く、Info.plist の形も違う（`CFBundlePrimaryIcon` が名前の文字列）ので、別のテストで見る。
    #if !os(visionOS)
    @Test(arguments: ["CFBundleIcons", "CFBundleIcons~ipad"])
    func 代替アイコンの名前はInfoPlistと同じ(key: String) throws {
        let data = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let icons = try #require(plist[key] as? [String: Any])
        let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
        #expect(Set(alternates.keys) == Set(AppIconChoice.allCases.compactMap(\.alternateIconName)))
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == AppIconChoice.standard.rawValue)
    }
    #else
    /// visionOS のアイコンは `Assets.xcassets/AppIcon.solidimagestack`（`.icon` は visionOS に適用されない）。
    /// スタックが無いと `CFBundleIcons` ごと消えてアイコン無しのアプリになるので、名前が入っているかを見る。
    @Test func アイコンの名前はInfoPlistにある() throws {
        let data = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let icons = try #require(plist["CFBundleIcons"] as? [String: Any])
        #expect(icons["CFBundlePrimaryIcon"] as? String == AppIconChoice.standard.rawValue)
    }
    #endif

    /// スクリプトが書き出した `.icon`（`DekiRoulette/Resources`）と候補の一覧の食い違いを見つける。
    /// スクリプトの `alternateIcons` にだけ足して `project.yml` や一覧に足し忘れた場合は、Info.plist のテストでは見つからない。
    @Test func 書き出したアイコンはすべて候補にある() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DekiRoulette/Resources")
        let names = try FileManager.default.contentsOfDirectory(atPath: resources.path)
            .filter { $0.hasSuffix(".icon") }
            .map { ($0 as NSString).deletingPathExtension }
        #expect(Set(names) == Set(AppIconChoice.allCases.map(\.rawValue)))
    }

    @Test(arguments: AppIconChoice.allCases)
    func 見本の画像がある(choice: AppIconChoice) {
        #expect(UIImage(named: choice.previewImageName) != nil)
    }
}
