import SwiftUI

/// スピン中に明るく残す盤面の枠（画面の座標）。`PageFrame` が 1 つ持ち、environment で中身に配る。
/// 盤面を出す画面だけが `spinSpotlightTarget()` で書き、読むのは幕（`SpinScrimLayer`）だけなので、スクロールで枠が変わっても描き直すのは幕だけになる。
@MainActor @Observable
final class SpinSpotlightTracker {
    /// 盤面の枠（`.global`）。盤面を伝えていなければ nil。
    var frame: CGRect?
}

private struct SpinSpotlightTrackerKey: EnvironmentKey {
    static let defaultValue: SpinSpotlightTracker? = nil
}

extension EnvironmentValues {
    /// スピン中の幕に盤面の枠を伝える先。`PageFrame` の中だけにある。
    var spinSpotlightTracker: SpinSpotlightTracker? {
        get { self[SpinSpotlightTrackerKey.self] }
        set { self[SpinSpotlightTrackerKey.self] = newValue }
    }
}

extension View {
    /// この View の枠を、スピン中の幕で明るく残す盤面として伝える。
    func spinSpotlightTarget() -> some View {
        modifier(SpinSpotlightTarget())
    }
}

private struct SpinSpotlightTarget: ViewModifier {
    @Environment(\.spinSpotlightTracker) private var tracker

    func body(content: Content) -> some View {
        content
            // 画面を離れても枠は捨てない（タブを往復しても位置が変わらなければ書き直されないため）。幕はスピン中しか見えないので、古い枠が残っても害は無い
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                if tracker?.frame != frame { tracker?.frame = frame }
            }
    }
}

/// ページ全体（ナビゲーションバー・安全領域を含む）に重ねる幕。`NavigationStack` の外に 1 枚だけ重ね、
/// 盤面の位置だけ円く抜いて縁をぼかす。盤面を伝えていなければ出さない。
/// タッチと読み上げは取らない（スクロール・タブ切り替えはスピン中も受け、暗くした所の読み上げは今のまま）。
struct SpinScrimLayer: View {
    let tracker: SpinSpotlightTracker
    /// 幕を掛けるか（ルーレットのスピン中）。
    let spotlight: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let frame = tracker.frame {
                SpinScrim(
                    size: proxy.size,
                    hole: SpinSpotlight.hole(inGlobal: frame, layerOrigin: proxy.frame(in: .global).origin)
                )
                .opacity(SpinSpotlight.opacity(spinning: spotlight))
                .animation(reduceMotion ? nil : Theme.spinDimAnimation, value: spotlight)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 大きさ `size` の幕。盤面の位置だけ円く抜いて縁をぼかす。
struct SpinScrim: View {
    /// 幕の大きさ（原点が幕の左上）。
    let size: CGSize
    /// 盤面の枠に抜く穴（幕の座標）。盤面の大きさが無いときは nil で、穴を抜かない。
    let hole: SpinSpotlight.Hole?

    var body: some View {
        let rect = CGRect(origin: .zero, size: size)
        // 四角 1 枚を、穴の中心からの放射状のグラデーションで塗る。半径 `radius` まで透明、ぼかしの外端で幕の濃さになり、
        // その外は最後の色が延びるので、塗りを 2 枚に分けたときのような継ぎ目（端のアンチエイリアスが重なる細い輪）が出ない
        Rectangle()
            .fill(fill(in: rect))
            .frame(width: size.width, height: size.height)
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
