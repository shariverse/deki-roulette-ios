import CoreGraphics
import Testing
@testable import DekiRoulette

/// 両画面のナビゲーションバーの縮んだ題名を出すか（iOS 26 以上の `PageFrame`）。
/// 値は iPhone 17 Pro（iOS 26.5）で測ったもの: 展開時はバーの下端 187pt・`contentOffset.y` −187、縮み切るとバーの下端 116pt、大きいタイトルの高さ 50pt。
struct LargeTitleCollapseTests {
    private static let width: CGFloat = 402
    private static let titleHeight: CGFloat = 50

    private func recorded(_ insets: [CGFloat], width: CGFloat = Self.width) -> LargeTitleCollapse {
        var collapse = LargeTitleCollapse()
        for inset in insets {
            collapse.record(insetTop: inset, containerWidth: width)
        }
        return collapse
    }

    @Test func 展開したままなら出さない() {
        let collapse = recorded([187])
        #expect(!collapse.showsInlineTitle(offsetY: -187, insetTop: 187, largeTitleHeight: Self.titleHeight))
    }

    @Test func 縮み切った位置で止まったら出す() {
        // 縮み切った直後は offset + inset が 0 で展開時と同じなので、バーの下端が縮んだ量で見る
        let collapse = recorded([187, 150, 116])
        #expect(collapse.showsInlineTitle(offsetY: -116, insetTop: 116, largeTitleHeight: Self.titleHeight))
    }

    @Test func 縮み切った先までスクロールしたら出す() {
        let collapse = recorded([187, 116])
        #expect(collapse.showsInlineTitle(offsetY: 246, insetTop: 116, largeTitleHeight: Self.titleHeight))
    }

    @Test func 縮む途中は大きいタイトルの高さぶん縮むまで出さない() {
        let collapse = recorded([187, 160])
        // 27pt 縮んだだけ。大きいタイトルはまだ見えている
        #expect(!collapse.showsInlineTitle(offsetY: -160, insetTop: 160, largeTitleHeight: Self.titleHeight))
        let further = recorded([187, 137])
        #expect(further.showsInlineTitle(offsetY: -137, insetTop: 137, largeTitleHeight: Self.titleHeight))
    }

    @Test func 端数の揺れでは出さない() {
        let collapse = recorded([187])
        #expect(!collapse.showsInlineTitle(offsetY: -186.7, insetTop: 187, largeTitleHeight: Self.titleHeight))
    }

    @Test func 上端を引っ張っても出さない() {
        // 先頭で下へ引っ張ると offset が展開時より小さくなる
        let collapse = recorded([187])
        #expect(!collapse.showsInlineTitle(offsetY: -240, insetTop: 187, largeTitleHeight: Self.titleHeight))
    }

    @Test func 大きいタイトルの高さを測る前は縮み切った直後でも出さない() {
        let collapse = recorded([187, 116])
        #expect(!collapse.showsInlineTitle(offsetY: -116, insetTop: 116, largeTitleHeight: 0))
        // その先までスクロールしていれば出す
        #expect(collapse.showsInlineTitle(offsetY: 10, insetTop: 116, largeTitleHeight: 0))
    }

    @Test func 幅が変わったら展開時のバーの下端を測り直す() {
        var collapse = recorded([187, 116])
        // 回転などで幅が変わった。縮んだ状態から測り直すので、縮み切った直後の判定には前の幅の値を使わない
        collapse.record(insetTop: 100, containerWidth: 874)
        #expect(collapse.expandedInsetTop == 100)
        #expect(!collapse.showsInlineTitle(offsetY: -100, insetTop: 100, largeTitleHeight: Self.titleHeight))
    }

    @Test func 文字の大きさが変わったら測り直す() {
        var collapse = recorded([187, 116])
        collapse.reset()
        #expect(collapse.expandedInsetTop == nil)
        collapse.record(insetTop: 210, containerWidth: Self.width)
        #expect(collapse.expandedInsetTop == 210)
    }
}
