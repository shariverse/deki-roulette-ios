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
/// タッチと読み上げは取らない（スクロール・タブ切り替えはスピン中も受け、暗くした所は今の `.disabled` のまま読み上げる）。
struct SpinScrim: View {
    /// ページの中身の大きさ（幕と同じ座標の原点が中身の左上）。
    let contentSize: CGSize
    /// 盤面の枠に抜く穴。盤面を伝えていないときは nil で、穴を抜かない。
    let hole: SpinSpotlight.Hole?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 穴の外側（ぼかしの外端より外）を 1 回の塗りで覆う
            Path { path in
                path.addRect(SpinSpotlight.scrimRect(contentSize: contentSize))
                if let hole {
                    path.addEllipse(in: circleRect(center: hole.center, radius: hole.outerRadius))
                }
            }
            .fill(Theme.spinScrim, style: FillStyle(eoFill: true))

            // 穴の縁のぼかし。半径 `radius` で透明、ぼかしの外端で幕と同じ濃さになり、外の塗りと継ぎ目なくつながる
            if let hole, hole.outerRadius > 0 {
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: Theme.spinScrim.opacity(0), location: hole.radius / hole.outerRadius),
                                .init(color: Theme.spinScrim, location: 1),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: hole.outerRadius
                        )
                    )
                    .frame(width: hole.outerRadius * 2, height: hole.outerRadius * 2)
                    .position(hole.center)
            }
        }
        .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func circleRect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
