import SwiftUI

/// スピン中に明るく残す盤面の枠を、`PageFrame` の幕に伝える。盤面を出す画面だけが `spinSpotlightTarget()` で付ける。
struct SpinSpotlightAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// この View の枠を、スピン中の幕で明るく残す盤面として伝える。
    func spinSpotlightTarget() -> some View {
        anchorPreference(key: SpinSpotlightAnchorKey.self, value: .bounds) { $0 }
    }
}

/// ページの中身に重ねる幕。中身より四方へ広く塗り（`SpinSpotlight.scrimRect`）、盤面の位置だけ円く抜いて縁をぼかす。
/// タッチと読み上げは取らない（スクロール・タブ切り替えはスピン中も受け、暗くした所の読み上げは今のまま）。
struct SpinScrim: View {
    /// ページの中身の大きさ（幕と同じ座標の原点が中身の左上）。
    let contentSize: CGSize
    /// 盤面の枠に抜く穴。盤面を伝えていないときは nil で、穴を抜かない。
    let hole: SpinSpotlight.Hole?

    var body: some View {
        let rect = SpinSpotlight.scrimRect(contentSize: contentSize)
        // 四角 1 枚を、穴の中心からの放射状のグラデーションで塗る。半径 `radius` まで透明、ぼかしの外端で幕の濃さになり、
        // その外は最後の色が延びるので、塗りを 2 枚に分けたときのような継ぎ目（端のアンチエイリアスが重なる細い輪）が出ない
        Rectangle()
            .fill(fill(in: rect))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func fill(in rect: CGRect) -> AnyShapeStyle {
        guard let hole, hole.outerRadius > 0 else { return AnyShapeStyle(Theme.spinScrim) }
        let center = SpinSpotlight.unitCenter(of: hole, in: rect)
        return AnyShapeStyle(
            RadialGradient(
                stops: [
                    .init(color: Theme.spinScrim.opacity(0), location: hole.radius / hole.outerRadius),
                    .init(color: Theme.spinScrim, location: 1),
                ],
                center: UnitPoint(x: center.x, y: center.y),
                startRadius: 0,
                endRadius: hole.outerRadius
            )
        )
    }
}
