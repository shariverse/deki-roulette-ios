import SwiftUI

/// 2D の盤面の停止の瞬間のフラッシュ（「スピンの演出」の停止の演出が ON のとき。`docs/SPEC.md` の §5.5）。
/// 結果が出た瞬間に盤面の枠の中へ白系の光（`Theme.stopFlash`）を 1 回だけ重ね、`Config.stopFlashDuration` で消す。
/// 不透明度は `WheelStopEffects.flashOpacity`（`Core/`）が停止からの経過で決め、毎フレームの値は 3D の盤面と共有の
/// `WheelStopEffectsTimeline` が `now()`（`RouletteModel.now` と同じ時計）から引く。光っている間だけ描き直し、消えたら止める。
/// 動きを減らす設定では何も描かない。
/// 入力は結果が出た時刻と時計だけで、項目・指定（`targetId`）・印・止まったスライスは受け取らない。読み上げず、触れられない。
struct WheelStopFlashView: View {
    /// 盤面の一辺（pt）。
    let side: CGFloat
    /// 結果が出た時刻（`WheelStopCues.flashStart`）。結果が無い・停止の瞬間を見ていないときは nil。
    let stoppedAt: TimeInterval?
    let now: () -> TimeInterval

    var body: some View {
        // 余韻は盤面の面（`WheelFaceView`）が自分で引くので、ここはフラッシュだけ
        WheelStopEffectsTimeline(flashStart: stoppedAt, afterglowStart: nil, now: now) { frame in
            let opacity = frame.flashOpacity
            if opacity > 0 {
                // 中心ほど明るく、盤面の枠の縁で 0 にする（枠の外へは広げない）
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.stopFlash.opacity(opacity),
                                Theme.stopFlash.opacity(opacity * Theme.StopFlash.middleOpacity),
                                Theme.stopFlash.opacity(0),
                            ],
                            center: .center, startRadius: 0, endRadius: side / 2
                        )
                    )
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 停止の演出の 1 フレーム（`WheelStopEffects.Frame`: フラッシュの不透明度と光彩の余韻の倍率）を引いて `content` に渡す時計。
/// 2D の `WheelStopFlashView` と 3D の `Wheel3DView` が同じ規則・同じ時刻（`now()` = `RouletteModel.now`）で引くよう共有する
/// （電飾の `WheelLightsTimeline` と同じ作り）。フラッシュが光っている間は毎フレーム、余韻の脈動だけなら `Config.effectPulseFrameInterval` ごとに描き直し、
/// どちらも無い・動きを減らす設定では止める。`enabled` が false なら止めたまま `.none` を渡す（停止の演出が OFF）。
/// 入力は停止の時刻と時計だけで、項目・指定（`targetId`）・印・止まったスライスは受け取らない。
struct WheelStopEffectsTimeline<Content: View>: View {
    var enabled = true
    /// フラッシュを始めた時刻（`WheelStopCues.flashStart`）。
    let flashStart: TimeInterval?
    /// 余韻の基準の時刻（`WheelStopCues.afterglowStart`）。
    let afterglowStart: TimeInterval?
    let now: () -> TimeInterval
    @ViewBuilder let content: (_ frame: WheelStopEffects.Frame) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 光り終えたフラッシュの `flashStart`。消えたら書いて描き直しの間隔を落とす（余韻も無ければ止める）。
    @State private var flashEndedAt: TimeInterval?

    var body: some View {
        let active = enabled && !reduceMotion
        let flashing = active && flashStart != nil && flashEndedAt != flashStart
            && WheelStopEffects.flashes(enabled: true, reduceMotion: false, elapsed: flashStart.map { now() - $0 })
        let pulsing = active && afterglowStart != nil
        TimelineView(.animation(
            minimumInterval: WheelStopEffects.frameInterval(flashing: flashing), paused: !flashing && !pulsing
        )) { _ in
            content(WheelStopEffects.frame(
                enabled: enabled, reduceMotion: reduceMotion,
                flashStart: flashing ? flashStart : nil, afterglowStart: afterglowStart, now: now()
            ))
        }
        .task(id: flashStart) {
            guard let flashStart else { return }
            let remaining = flashStart + Config.stopFlashDuration - now()
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            flashEndedAt = flashStart
        }
    }
}
