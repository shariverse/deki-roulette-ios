import SwiftUI
import Testing
import UIKit
@testable import DekiRoulette

/// iOS 17〜18 のナビゲーションバー（`RootView.init` の `UINavigationBarAppearance`）に当てる両画面の題名の文字の属性。
/// iOS 26 以上は `PageFrame` が toolbar の置き場所の `Text` で同じトークン（`pageLargeTitle` / `pageInlineTitle`）を使う。
struct NavigationTitleAttributesTests {
    private static let standard = UITraitCollection(preferredContentSizeCategory: .large)

    @Test func 大きいタイトルは同梱の書体のBlackで字間を詰める() throws {
        let attributes = Theme.Typography.navigationLargeTitleAttributes(compatibleWith: Self.standard)
        let font = try #require(attributes[.font] as? UIFont)
        #expect(font.fontName == AppFont.Face.black.postScriptName)
        // 既定の大きさではヘッダにあった題名と同じ largeTitle の大きさ
        #expect(abs(font.pointSize - Theme.Typography.defaultSize(for: .largeTitle)) < 0.01)
        let kern = try #require(attributes[.kern] as? CGFloat)
        #expect(abs(kern - Theme.Typography.pageTitleTracking) < 1e-9)
        #expect(abs(kern - -1) < 1e-9)
    }

    @Test func 縮んだ題名はシートの題名と同じheadlineの太さ() throws {
        let attributes = Theme.Typography.navigationInlineTitleAttributes(compatibleWith: Self.standard)
        let font = try #require(attributes[.font] as? UIFont)
        // headline の既定の太さ（semibold）は Bold のフェイス
        #expect(font.fontName == AppFont.Face.bold.postScriptName)
        #expect(abs(font.pointSize - Theme.Typography.defaultSize(for: .headline)) < 0.01)
        #expect(attributes[.kern] == nil)
    }

    @Test func 文字の色はivoryで外観に追従する() throws {
        for attributes in [
            Theme.Typography.navigationLargeTitleAttributes(compatibleWith: Self.standard),
            Theme.Typography.navigationInlineTitleAttributes(compatibleWith: Self.standard),
        ] {
            let color = try #require(attributes[.foregroundColor] as? UIColor)
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                #expect(color.resolvedColor(with: traits) == UIColor(Theme.ivory).resolvedColor(with: traits))
            }
        }
    }

    @Test func 大きい文字の設定では拡大する() throws {
        let large = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        let standardFont = try #require(
            Theme.Typography.navigationLargeTitleAttributes(compatibleWith: Self.standard)[.font] as? UIFont
        )
        let largeFont = try #require(
            Theme.Typography.navigationLargeTitleAttributes(compatibleWith: large)[.font] as? UIFont
        )
        #expect(largeFont.pointSize > standardFont.pointSize)
        #expect(largeFont.fontName == AppFont.Face.black.postScriptName)
    }
}
