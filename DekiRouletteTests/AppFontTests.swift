import Foundation
import SwiftUI
import Testing
import UIKit
@testable import DekiRoulette

/// 同梱の書体（Zen Maru Gothic）が `.app` に入って登録され、トークンがそのフェイスを返す。
/// 登録はビルドした `.app` の Info.plist（`project.yml` の `UIAppFonts`）で見る（`InfoPlistTests` と同じ読み方）。
struct AppFontTests {
    private static func infoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Info.plist"))
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func UIAppFontsに同梱した3つのファイルがある() throws {
        let fonts = try #require(try Self.infoPlist()["UIAppFonts"] as? [String])
        #expect(Set(fonts) == Set(AppFont.Face.allCases.map(\.fileName)))
        #expect(fonts.count == AppFont.Face.allCases.count)
    }

    @Test(arguments: AppFont.Face.allCases)
    func フォントのファイルがバンドルにある(face: AppFont.Face) throws {
        let fonts = try #require(try Self.infoPlist()["UIAppFonts"] as? [String])
        let fileName = try #require(fonts.first { $0 == face.fileName })
        let url = Bundle.main.bundleURL.appendingPathComponent(fileName)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: AppFont.Face.allCases)
    func PostScript名で読める(face: AppFont.Face) throws {
        let font = try #require(UIFont(name: face.postScriptName, size: 17))
        #expect(font.fontName == face.postScriptName)
        #expect(font.familyName == AppFont.familyName)
    }

    @Test(arguments: [
        (Font.Weight.ultraLight, AppFont.Face.regular),
        (.thin, .regular),
        (.light, .regular),
        (.regular, .regular),
        (.medium, .bold),
        (.semibold, .bold),
        (.bold, .bold),
        (.heavy, .black),
        (.black, .black),
    ])
    func 太さからフェイスを選ぶ(weight: Font.Weight, face: AppFont.Face) {
        #expect(AppFont.face(for: weight) == face)
    }

    @Test func 見出しのスタイルだけ既定の太さがsemibold() {
        #expect(AppFont.defaultWeight(for: .headline) == .semibold)
        #expect(AppFont.face(for: AppFont.defaultWeight(for: .headline)) == .bold)
        for style in [Font.TextStyle.largeTitle, .title, .title2, .title3, .body, .callout, .subheadline, .footnote, .caption, .caption2] {
            #expect(AppFont.defaultWeight(for: style) == .regular)
        }
    }

    @Test(arguments: [
        (Font.TextStyle.largeTitle, UIFont.TextStyle.largeTitle),
        (.title, .title1),
        (.title2, .title2),
        (.title3, .title3),
        (.headline, .headline),
        (.body, .body),
        (.callout, .callout),
        (.subheadline, .subheadline),
        (.footnote, .footnote),
        (.caption, .caption1),
        (.caption2, .caption2),
    ])
    func テキストスタイルの既定の大きさは標準の文字サイズの値(style: Font.TextStyle, uiStyle: UIFont.TextStyle) {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let expected = UIFont.preferredFont(forTextStyle: uiStyle, compatibleWith: traits).pointSize
        #expect(Theme.Typography.uiTextStyle(style) == uiStyle)
        #expect(abs(Theme.Typography.defaultSize(for: style) - expected) < 1e-9)
    }

    #if os(visionOS)
    /// visionOS だけのスタイルも既定の大きさを引けるよう、UIKit のスタイルに写す。
    @Test func visionOSだけのスタイルも写す() {
        #expect(Theme.Typography.uiTextStyle(.extraLargeTitle) == .extraLargeTitle)
        #expect(Theme.Typography.uiTextStyle(.extraLargeTitle2) == .extraLargeTitle2)
    }
    #endif

    @Test(arguments: [
        (Font.Weight.regular, AppFont.Face.regular),
        (.bold, .bold),
        (.black, .black),
    ])
    func UIFontのトークンは同梱のフェイスを返す(weight: Font.Weight, face: AppFont.Face) {
        let font = Theme.Typography.uiFont(size: 20, weight: weight)
        #expect(font.fontName == face.postScriptName)
        #expect(abs(font.pointSize - 20) < 1e-9)
    }

    @Test func ライセンス文がバンドルにある() throws {
        let url = try #require(Bundle.main.url(forResource: AppFont.licenseResource, withExtension: AppFont.licenseExtension))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(text.contains("Copyright 2021 The Zen Maru Gothic Project Authors"))
    }
}
