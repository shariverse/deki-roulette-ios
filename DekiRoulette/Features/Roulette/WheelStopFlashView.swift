import SwiftUI

/// 2D の盤面の停止の瞬間のフラッシュ（「スピンの演出」が「なし」以外のとき。`docs/SPEC.md` の §5.5）。
/// 結果が出た瞬間に盤面の枠の中へ白系の光（`Theme.stopFlash`）を 1 回だけ重ね、`Config.stopFlashDuration` で消す。
/// 不透明度は `WheelStopEffects.flashOpacity`（`Core/`）が停止からの経過で決め、ここは光っている間だけ `TimelineView` を動かして
/// `now()`（`RouletteModel.now` と同じ時計）から引く。消えたら `TimelineView` を止める。動きを減らす設定では何も描かない。
/// 入力は結果が出た時刻と時計だけで、項目・指定（`targetId`）・印・止まったスライスは受け取らない。読み上げず、触れられない。
struct WheelStopFlashView: View {
    /// 盤面の一辺（pt）。
    let side: CGFloat
    /// 結果が出た時刻（`now()` の秒）。結果が無いときは nil。
    let stoppedAt: TimeInterval?
    let now: () -> TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 光り終えた結果の `stoppedAt`。消えたら書いて `TimelineView` を止める。
    @State private var flashEndedAt: TimeInterval?

    var body: some View {
        let active = stoppedAt != nil && flashEndedAt != stoppedAt
            && WheelStopEffects.flashes(enabled: true, reduceMotion: reduceMotion, elapsed: stoppedAt.map { now() - $0 })
        TimelineView(.animation(paused: !active)) { _ in
            let opacity = active ? stoppedAt.map { WheelStopEffects.flashOpacity(at: now() - $0) } ?? 0 : 0
            if opacity > 0 {
                // 中心ほど明るく、盤面の枠の縁で 0 にする（枠の外へは広げない）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.stopFlash.opacity(opacity),
                                Theme.stopFlash.opacity(opacity * 0.7),
                                Theme.stopFlash.opacity(0),
                            ],
                            center: .center, startRadius: 0, endRadius: side / 2
                        )
                    )
            }
        }
        .frame(width: side, height: side)
        .task(id: stoppedAt) {
            guard let stoppedAt else { return }
            let remaining = stoppedAt + Config.stopFlashDuration - now()
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            flashEndedAt = stoppedAt
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
