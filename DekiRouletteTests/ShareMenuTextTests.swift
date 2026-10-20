import Testing
@testable import DekiRoulette

/// 「結果を共有」のメニューの項目名（Discussion #351）。
struct ShareMenuTextTests {
    /// 「X」1 文字だけの名前は閉じるボタン（✕）と間違えて押されたので、行き先と動作が分かる名前にする。
    @Test func destinationNamesSayWhereAndWhat() {
        #expect(L10n.shareToX.contains("X"))
        #expect(L10n.shareToX != "X")
        #expect(L10n.shareToLINE.contains("LINE"))
        #expect(L10n.shareToLINE != "LINE")
    }

    /// 画像を描き終える前の項目名は、画像付きの項目名と別にする（本文だけを渡すので「画像付き」と言わない）。
    @Test func shareSheetItemNameDependsOnImage() {
        #expect(!L10n.shareWithImage.isEmpty)
        #expect(!L10n.shareTextOnly.isEmpty)
        #expect(L10n.shareWithImage != L10n.shareTextOnly)
    }
}
