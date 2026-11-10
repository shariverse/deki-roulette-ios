import Foundation
import Testing
@testable import DekiRoulette

struct AppVersionTests {
    private static let template = "%1$@ (%2$@)"
    private static let both = "バージョン %1$@、ビルド %2$@"
    private static let versionOnly = "バージョン %@"
    private static let buildOnly = "ビルド %@"

    private func label(_ version: AppVersion) -> String {
        version.accessibilityLabel(both: Self.both, versionOnly: Self.versionOnly, buildOnly: Self.buildOnly)
    }

    @Test func 両方の値があればバージョンの後に括弧でビルドを付ける() throws {
        let version = try #require(AppVersion(infoDictionary: [
            "CFBundleShortVersionString": "1.1.0",
            "CFBundleVersion": "24",
        ]))
        #expect(version.display(template: Self.template) == "1.1.0 (24)")
        #expect(label(version) == "バージョン 1.1.0、ビルド 24")
    }

    @Test func バージョンだけならその値だけ() throws {
        let version = try #require(AppVersion(infoDictionary: ["CFBundleShortVersionString": "1.1.0"]))
        #expect(version.display(template: Self.template) == "1.1.0")
        #expect(label(version) == "バージョン 1.1.0")
    }

    @Test func ビルドだけならその値だけ() throws {
        let version = try #require(AppVersion(infoDictionary: ["CFBundleVersion": "24"]))
        #expect(version.display(template: Self.template) == "24")
        #expect(label(version) == "ビルド 24")
    }

    @Test func 両方無ければ行を出さない() {
        #expect(AppVersion(infoDictionary: [:]) == nil)
        #expect(AppVersion(infoDictionary: nil) == nil)
    }

    @Test func 空の値と文字列でない値は無いものとして扱う() {
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": "", "CFBundleVersion": "  "]) == nil)
        #expect(AppVersion(infoDictionary: ["CFBundleShortVersionString": 1, "CFBundleVersion": 24]) == nil)
        let version = AppVersion(infoDictionary: ["CFBundleShortVersionString": "", "CFBundleVersion": "24"])
        #expect(version?.display(template: Self.template) == "24")
    }

    @Test func 値は加工せずに出す() throws {
        // 手元のビルドの CURRENT_PROJECT_VERSION（1）も、そのまま出す
        let version = try #require(AppVersion(version: "1.1.0", build: "1"))
        #expect(version.display(template: Self.template) == "1.1.0 (1)")
    }

    @Test func 値の記号は書式として読まない() throws {
        let version = try #require(AppVersion(version: "1%@", build: "2%"))
        #expect(version.display(template: Self.template) == "1%@ (2%)")
    }

    @Test func アプリのInfoplistから読める() throws {
        // 値を書き込んだ定数ではなく、ビルドした Info.plist から両方読めることを確かめる
        let version = try #require(AppVersion(infoDictionary: Bundle.main.infoDictionary))
        #expect(version.version != nil)
        #expect(version.build != nil)
    }
}
