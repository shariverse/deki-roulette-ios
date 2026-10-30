import CoreGraphics
import Foundation

/// 両画面（`PageFrame`）のナビゲーションバーの大きいタイトルが縮み切ったか（iOS 26 以上）。
/// iOS 26 の縮んだ題名は toolbar の `.title` / `.subtitle` の置き場所の `Text` で同梱の書体にするが、置き場所の `Text` は
/// 大きいタイトルが出ている間も消えないので、縮み切ったときだけ見せる。
///
/// 判定はスクロールの幾何（`contentOffset.y` と `contentInsets.top`）だけで行う。大きいタイトルが縮む間はバーの下端（`contentInsets.top`）が
/// スクロールした分だけ上がり、縮み切ると最小になって、その先は `contentOffset.y + contentInsets.top` が正になる。
/// 途中で指を離すと UIKit が展開か縮み切りに戻すので、止まった状態はその 2 つになる。縮み切った直後は和が 0 で展開時と区別できないので、
/// 展開時のバーの下端（見た中で最大の `contentInsets.top`）から大きいタイトルの高さ以上縮んだかでも見る。
struct LargeTitleCollapse: Equatable {
    /// 展開時のバーの下端。画面の幅が変わったら（回転・iPad の分割）測り直す。
    private(set) var expandedInsetTop: CGFloat?
    private var containerWidth: CGFloat?

    /// スクロールの幾何を 1 回記録する。
    mutating func record(insetTop: CGFloat, containerWidth width: CGFloat) {
        if containerWidth != width {
            containerWidth = width
            expandedInsetTop = nil
        }
        expandedInsetTop = max(expandedInsetTop ?? insetTop, insetTop)
    }

    /// 文字の大きさが変わったら測り直す（展開時のバーの高さが変わる）。
    mutating func reset() {
        expandedInsetTop = nil
        containerWidth = nil
    }

    /// 縮んだ題名を見せるか。`largeTitleHeight` は大きいタイトルの `Text` の高さ（まだ測れていなければ 0）。
    func showsInlineTitle(offsetY: CGFloat, insetTop: CGFloat, largeTitleHeight: CGFloat) -> Bool {
        // 縮み切った先までスクロールした。端数の揺れで展開時に出さないよう 0.5pt の遊びを取る
        if offsetY + insetTop > 0.5 { return true }
        guard let expandedInsetTop, largeTitleHeight > 0 else { return false }
        return expandedInsetTop - insetTop >= largeTitleHeight
    }
}
