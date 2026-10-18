import SwiftUI

/// 2D の盤面の外周の電飾（「スピンの演出」が電飾・全部入りのとき。`docs/SPEC.md` の §5.5）。
/// 盤面の縁の上に `Config.wheelLightCount` 個の電球を回らない層で並べ、明るさは `WheelLights`（`Core/`）が決める。
/// 毎フレームの明るさは 3D の盤面と共有の `WheelLightsTimeline` が引き、このビューは `Canvas` に描くだけ。
/// 入力は角度・動き・結果を出しているかだけで、項目・指定（`targetId`）・印は受け取らない。読み上げず、触れられない。
struct WheelLightsView: View {
    /// 盤面の一辺（pt）。電球の大きさと位置はこれに比例させる。
    let side: CGFloat
    let rotation: Double
    let dragRotation: Double
    /// 盤面が自分で回っている動き（`RouletteModel.currentMotion`）。
    let motion: TimedSpinMotion?
    /// 指で動かしている動き（`WheelDragArea` の記録）。指を離したあとも次のドラッグまで残る。
    let drag: WheelDragMotion?
    /// 結果を出していて止まったスライスを強調している間だけ、結果が出た時刻（`now()` の秒）。点滅と脈動の経過時間の基準。
    /// 結果が無い・指で動かして強調を解いたら nil。止まったスライスの光彩の余韻と同じ時刻を親（`RouletteWheelView`）から受け取る。
    let stoppedAt: TimeInterval?
    let now: () -> TimeInterval

    var body: some View {
        WheelLightsTimeline(
            rotation: rotation, dragRotation: dragRotation, motion: motion, drag: drag, stoppedAt: stoppedAt, now: now
        ) { scene in
            Canvas { context, size in
                if let scene { draw(scene: scene, in: &context, size: size) }
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(scene: WheelLights.Scene, in context: inout GraphicsContext, size: CGSize) {
        let ringRadius = Theme.LightRing.ringRadius(diameter: side)
        let bulbRadius = Theme.LightRing.bulbRadius(diameter: side)
        let haloWidth = Theme.LightRing.haloWidth(diameter: side)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = Config.wheelLightCount

        for index in 0..<count {
            let bulb = WheelLights.bulb(index: index, count: count, scene: scene)
            let radians = (WheelLights.angle(index: index, count: count) - 90) * .pi / 180
            let point = CGPoint(x: center.x + ringRadius * cos(radians), y: center.y + ringRadius * sin(radians))

            if bulb.glow > 0 {
                let haloRadius = bulbRadius + haloWidth * bulb.glow
                let halo = CGRect(x: point.x - haloRadius, y: point.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
                context.fill(
                    Path(ellipseIn: halo),
                    with: .radialGradient(
                        Gradient(colors: [
                            Theme.wheelLight.opacity(Theme.LightRing.haloOpacity * bulb.glow * bulb.brightness),
                            Theme.wheelLight.opacity(0),
                        ]),
                        center: point, startRadius: bulbRadius * 0.5, endRadius: haloRadius
                    )
                )
            }
            let rect = CGRect(x: point.x - bulbRadius, y: point.y - bulbRadius, width: bulbRadius * 2, height: bulbRadius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Theme.wheelLight.opacity(bulb.brightness)))
        }
    }
}

/// 電飾の場面（`WheelLights.Scene`）を毎フレーム引いて `content` に渡す時計。2D の `WheelLightsView` と 3D の `Wheel3DView` が
/// 同じ規則・同じ時刻（`now()` = `RouletteModel.now`）で引くよう共有する。
/// 補間中の角度は observable でないので、盤面が自分で回っている間（`motion`）は `TimelineView` で毎フレーム、
/// `now()` から角度と強さを引く。動いていないときは `rotation + dragRotation`。
/// 光の並びは盤面の角度の変化だけ流し、1 フレームに `Config.wheelLightMaxFlowPerFrame` 個を超える分は遅れとして持ち越す（`WheelLights.Flow`）。
/// 指で動かしている間（`drag`）は、指が回した角度の変化から求めた角速度で強さを引き、指を止めたあとの落ち方も描くので `TimelineView` を動かす。
/// 待機中・止まり切った惰性・指の動きが止まり切ったあとは `TimelineView` を止め（角度が変われば親の描き直しで足りる）、
/// 結果表示中は点滅と脈動のために動かす（点滅の間は毎フレーム、脈動だけになったら `Config.effectPulseFrameInterval` ごと）。
/// 動きを減らす設定では止めたまま一定の明るさで点ける。`enabled` が false なら止めたまま場面を nil で渡す（電飾を出さない）。
/// false の間は流れを進めないので、true に戻したら流れはそのときの盤面の角度から始め直す（出していない間に回った分を流さない）。
/// 入力は角度・動き・結果を出しているかだけで、項目・指定（`targetId`）・印は受け取らない。
struct WheelLightsTimeline<Content: View>: View {
    var enabled = true
    let rotation: Double
    let dragRotation: Double
    let motion: TimedSpinMotion?
    let drag: WheelDragMotion?
    /// 結果を出していて止まったスライスを強調している間だけ、結果が出た時刻（`now()` の秒）。
    let stoppedAt: TimeInterval?
    let now: () -> TimeInterval
    @ViewBuilder let content: (_ scene: WheelLights.Scene?) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 点滅が終わった結果の `stoppedAt`。点滅の終わりに書いて描き直させ、描き直しの間隔を落とす。
    @State private var blinkEndedAt: TimeInterval?
    /// 止まり切った動き。惰性・指の動きは止まり切っても残り、親が描き直さないので、止まり切ったらここに入れて
    /// 描き直させ、`TimelineView` を止める。
    @State private var settledMotion: WheelEffectMotion?
    /// 光の並びを流す角度（`WheelLights.Flow`）。描くたびに進めるので、書き換えても描き直さないよう参照型に入れて持つ。
    /// View の値が作られるたびに作り直さないよう、最初に画面に出たときに 1 つだけ作る（それまでは盤面の角度のまま流す）。
    @State private var flow: LightFlowBox?

    var body: some View {
        let current = now()
        let stoppedAt = enabled ? stoppedAt : nil
        let effect = enabled ? WheelEffectMotion.current(spin: motion, drag: drag, now: current) : nil
        let moving = WheelEffectMotion.isMoving(effect, settled: settledMotion, now: current)
        let animates = enabled && WheelLights.animates(reduceMotion: reduceMotion, moving: moving, showingResult: stoppedAt != nil)
        // 点滅が終わるまでは毎フレーム。終わりは下の `.task(id: stoppedAt)` が待って `blinkEndedAt` に書く
        let interval = WheelLights.frameInterval(
            moving: moving,
            stoppedElapsed: stoppedAt.map { blinkEndedAt == $0 ? WheelLights.blinkDuration : 0 }
        )
        TimelineView(.animation(minimumInterval: interval, paused: !animates)) { _ in
            content(enabled ? scene(effect: effect, stoppedAt: stoppedAt) : nil)
        }
        .task(id: stoppedAt) {
            guard let stoppedAt, !reduceMotion else { return }
            let remaining = stoppedAt + WheelLights.blinkDuration - now()
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            blinkEndedAt = stoppedAt
        }
        .task(id: effect) {
            guard let effect, !reduceMotion else { return }
            let remaining = effect.remaining(now: now())
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            settledMotion = effect
        }
        .onAppear {
            if flow == nil { flow = LightFlowBox() }
        }
        .onChange(of: enabled) { _, enabled in
            // 出していない間は流さないので、次に出したときに溜まった角度の差を流さないよう、そのときの角度から始め直す
            if !enabled { flow?.value = WheelLights.Flow() }
        }
    }

    /// 今の時刻の場面。
    private func scene(effect: WheelEffectMotion?, stoppedAt: TimeInterval?) -> WheelLights.Scene {
        // 時刻は `TimelineView` の日付ではなく、動きの開始時刻と同じ時計で取る
        let time = now()
        let board = effect?.displayedAngle(now: time, rotation: rotation, dragRotation: dragRotation) ?? rotation + dragRotation
        // 並びは盤面の角度の変化だけ流す。速すぎる分は 1 フレームに `Config.wheelLightMaxFlowPerFrame` 個までに抑えて持ち越す
        let flowAngle = reduceMotion ? 0 : flow?.value.advance(to: board, at: time) ?? board
        return WheelLights.scene(
            reduceMotion: reduceMotion,
            angle: flowAngle,
            // 盤面が自分で回っている間はその動きの、指で動かしている間は指が回した角度の変化から求めた強さ
            intensity: effect?.intensity(now: time) ?? 0,
            stoppedElapsed: stoppedAt.map { time - $0 }
        )
    }
}

/// 電飾の光の並びを流す角度の入れ物。描くたびに進めても View を描き直さないよう参照型にする。
@MainActor
final class LightFlowBox {
    var value = WheelLights.Flow()
}
