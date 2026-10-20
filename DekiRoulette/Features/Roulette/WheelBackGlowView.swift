import SwiftUI

/// 2D の盤面の背景の光の脈動（「スピンの演出」の電飾が ON のとき。`docs/SPEC.md` の §5.5）。
/// 盤面の枠の中、外周の縁の外側の環（`Theme.BackGlow`）に柔らかい光を置き、回転の速さに比例して明るくする（`WheelBackGlow`）。
/// 毎フレームの不透明度は 3D の盤面と共有の `WheelBackGlowTimeline` が引き、このビューは `Canvas` に描くだけ（盤面の枠と同じ大きさ）。
/// 入力は動き（スピン・惰性と指の動き）だけで、項目・指定（`targetId`）・印は受け取らない。読み上げず、触れられない。
struct WheelBackGlowView: View {
    /// 盤面の一辺（pt）。光の環の大きさはこれに比例させる。
    let side: CGFloat
    /// 盤面が自分で回っている動き（`RouletteModel.currentMotion`）。
    let motion: TimedSpinMotion?
    /// 指で動かしている動き（`WheelDragArea` の記録）。
    let drag: WheelDragMotion?
    let now: () -> TimeInterval

    var body: some View {
        WheelBackGlowTimeline(motion: motion, drag: drag, now: now) { opacity in
            Canvas { context, size in
                guard opacity > 0 else { return }
                let inner = Theme.BackGlow.innerRadius(diameter: side)
                let outer = Theme.BackGlow.outerRadius(diameter: side)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                // 縁の外周から枠までの環だけを塗る（盤面の面には重ねない）
                var ring = Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
                ring.addPath(Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)))
                context.fill(
                    ring,
                    with: .radialGradient(
                        Gradient(colors: [Theme.wheelBackGlow.opacity(opacity), Theme.wheelBackGlow.opacity(0)]),
                        center: center, startRadius: inner, endRadius: outer
                    ),
                    style: FillStyle(eoFill: true)
                )
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 背景の光の脈動の不透明度（`WheelBackGlow.opacity`）を毎フレーム引いて `content` に渡す時計。2D の `WheelBackGlowView` と
/// 3D の盤面が同じ規則・同じ時刻（`now()` = `RouletteModel.now`）で引くよう共有する。
/// 盤面が自分で回っている間（`motion`）と指で動かしている間（`drag`）は `TimelineView` で毎フレーム、選んだ動き（`WheelEffectMotion`）の
/// 強さから引く。待機中・止まり切った惰性・指の動きが止まり切ったあと・動きを減らす設定では止め、0 を渡す。
/// `enabled` が false なら止めたまま 0 を渡す（光を出さない）。入力は動きだけで、項目・指定（`targetId`）・印は受け取らない。
struct WheelBackGlowTimeline<Content: View>: View {
    var enabled = true
    let motion: TimedSpinMotion?
    let drag: WheelDragMotion?
    let now: () -> TimeInterval
    @ViewBuilder let content: (_ opacity: Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 止まり切った動き。惰性・指の動きは止まり切っても残り、親が描き直さないので、止まり切ったらここに入れて
    /// 描き直させ、`TimelineView` を止める（電飾と同じ）。
    @State private var settledMotion: WheelEffectMotion?

    var body: some View {
        let current = now()
        let effect = enabled ? WheelEffectMotion.current(spin: motion, drag: drag, now: current) : nil
        let moving = WheelEffectMotion.isMoving(effect, settled: settledMotion, now: current)
        let animates = enabled && WheelBackGlow.animates(reduceMotion: reduceMotion, moving: moving)
        TimelineView(.animation(paused: !animates)) { _ in
            // 時刻は `TimelineView` の日付ではなく、動きの開始時刻と同じ時計で取る。止めている間は 0（光は消えている）
            content(animates ? WheelBackGlow.opacity(intensity: effect?.intensity(now: now()) ?? 0, reduceMotion: reduceMotion) : 0)
        }
        .task(id: effect) {
            guard let effect, !reduceMotion else { return }
            let remaining = effect.remaining(now: now())
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            settledMotion = effect
        }
    }
}
