import Foundation
import Testing

/// 共有シートの「画像を保存」は、利用目的（`NSPhotoLibraryAddUsageDescription`）が無いとアプリが落ちる。
/// アプリは `GENERATE_INFOPLIST_FILE: NO` なので、`project.yml` の `info.properties` から書き出した Info.plist に入っているかをビルドした `.app` で見る。
struct InfoPlistTests {
    private static let photoLibraryAddKey = "NSPhotoLibraryAddUsageDescription"

    @Test func 写真への追加の利用目的がある() throws {
        let data = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let description = try #require(plist[Self.photoLibraryAddKey] as? String)
        #expect(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// 写真の読み取りの権限は求めない（保存だけなので追加の権限で足りる）。
    @Test func 写真の読み取りの権限は求めない() throws {
        let data = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["NSPhotoLibraryUsageDescription"] == nil)
    }

    /// `InfoPlist.xcstrings` の各言語の文言が `.app` に入っている。
    @Test(arguments: ["ja", "en"])
    func 写真への追加の利用目的は各言語にある(language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let missing = "<missing>"
        let description = bundle.localizedString(forKey: Self.photoLibraryAddKey, value: missing, table: "InfoPlist")
        #expect(description != missing)
        #expect(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
