import SwiftUI

/// 2D の盤面の針の先の火花と停止の瞬間の紙吹雪（「スピンの演出」が紙吹雪・全部入りのとき。`docs/SPEC.md` の §5.5）。
/// 盤面が自分で回っている間（`motion`）と指で動かしている間（`drag`。指を止めた・離したあとは生まれた粒が消えるまで）は
/// 針の先から火花を出し、結果が出た瞬間（`burstAt`）に盤面の上から紙吹雪をはじけさせる。
/// 粒の位置・大きさ・濃さは `WheelParticles`（`Core/`）が時刻と種から決め、毎フレームの値は 3D の盤面と共有の `WheelParticlesTimeline` が引く。
/// このビューは `Canvas` に描くだけ。
/// 入力は動き（自分で回る動き・指で動かしている動き）・紙吹雪がはじけた時刻・時計だけで、項目・指定（`targetId`）・印・止まったスライスは受け取らない（紙吹雪は結果に依らず同じ）。
/// 読み上げず、触れられない。
struct WheelParticlesView: View {
    /// 盤面の一辺（pt）。粒の速さ・大きさはこれに比例させる。
    let side: CGFloat
    /// 盤面が自分で回っている動き（`RouletteModel.currentMotion`）。
    let motion: TimedSpinMotion?
    /// 指で動かしている動き（`WheelDragArea` の記録）。指を離したあとも次のドラッグまで残る。
    let drag: WheelDragMotion?
    /// 紙吹雪がはじけた時刻（`WheelStopCues.confettiStart`）。nil から値になった瞬間にはじけさせる。
    let burstAt: TimeInterval?
    let now: () -> TimeInterval

    var body: some View {
        WheelParticlesTimeline(side: side, motion: motion, drag: drag, burstAt: burstAt, now: now) { frame in
            if !frame.isEmpty {
                Canvas { context, _ in
                    draw(confetti: frame.confetti, in: &context)
                    draw(sparks: frame.sparks, in: &context)
                }
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(confetti: [WheelParticles.Confetto], in context: inout GraphicsContext) {
        for piece in confetti where piece.opacity > 0 {
            var layer = context
            layer.translateBy(x: piece.position.x, y: piece.position.y)
            layer.rotate(by: .radians(piece.rotation))
            let width = piece.size.width * piece.flip
            let rect = CGRect(x: -width / 2, y: -piece.size.height / 2, width: width, height: piece.size.height)
            let color = Theme.confettiColors[piece.colorIndex % Theme.confettiColors.count]
            layer.fill(Path(rect), with: .color(color.opacity(piece.opacity)))
        }
    }

    private func draw(sparks: [WheelParticles.Spark], in context: inout GraphicsContext) {
        for spark in sparks where spark.opacity > 0 {
            let point = spark.position
            let tailEnd = CGPoint(x: point.x + spark.tail.dx, y: point.y + spark.tail.dy)
            // にじみ（橙）を奥に、尾と芯（白）を手前に
            let haloRadius = spark.radius * Theme.SparkGlow.haloScale
            let halo = CGRect(x: point.x - haloRadius, y: point.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
            context.fill(
                Path(ellipseIn: halo),
                with: .radialGradient(
                    Gradient(colors: [
                        Theme.wheelSparkGlow.opacity(Theme.SparkGlow.haloOpacity * spark.opacity),
                        Theme.wheelSparkGlow.opacity(0),
                    ]),
                    center: point, startRadius: 0, endRadius: haloRadius
                )
            )
            var tail = Path()
            tail.move(to: point)
            tail.addLine(to: tailEnd)
            context.stroke(
                tail,
                with: .linearGradient(
                    Gradient(colors: [Theme.wheelSparkGlow.opacity(spark.opacity), Theme.wheelSparkGlow.opacity(0)]),
                    startPoint: point, endPoint: tailEnd
                ),
                style: StrokeStyle(lineWidth: spark.radius * 1.4, lineCap: .round)
            )
            let core = CGRect(x: point.x - spark.radius, y: point.y - spark.radius, width: spark.radius * 2, height: spark.radius * 2)
            context.fill(Path(ellipseIn: core), with: .color(Theme.wheelSpark.opacity(spark.opacity)))
        }
    }
}

/// 火花と紙吹雪の 1 フレーム（`WheelParticles.Frame`）を毎フレーム引いて `content` に渡す時計。2D の `WheelParticlesView` と 3D の `Wheel3DView` が
/// 同じ規則・同じ時刻（`now()` = `RouletteModel.now`）で引くよう共有する（電飾の `WheelLightsTimeline`・光の尾の `WheelTrailsTimeline` と同じ作り）。
/// 火花の種はスピン・惰性の動きが変わるたびとドラッグを始めるたびに、紙吹雪の種ははじけるたびに引き直す。
/// 火花も紙吹雪も出ていない・動きを減らす設定では `TimelineView` を止めて `.none` を渡す。低電力モードでは粒の数の上限を 1/3 にする。
/// `enabled` が false なら止めたまま `.none` を渡し、低電力モードの購読も作らない（火花・紙吹雪を出さない）。
/// 入力は動き・紙吹雪がはじけた時刻・時計だけで、項目・指定（`targetId`）・印・止まったスライスは受け取らない。
struct WheelParticlesTimeline<Content: View>: View {
    var enabled = true
    /// 盤面の一辺（pt）。
    let side: CGFloat
    let motion: TimedSpinMotion?
    let drag: WheelDragMotion?
    /// 紙吹雪がはじけた時刻。nil から値になった瞬間にはじけさせ、はじけた紙吹雪は値が nil に戻っても（次のスピン・結果が消えた）最後まで落とす。
    let burstAt: TimeInterval?
    let now: () -> TimeInterval
    @ViewBuilder let content: (_ frame: WheelParticles.Frame) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 最初に必要になったときに 1 つだけ作る（光の尾と同じ。作る前は今の値を直接読む）。
    @State private var lowPower: LowPowerModeMonitor?
    /// 止まり切った動き。止まり切ったら火花の分の描き直しを止める（光の尾と同じ）。
    @State private var settledMotion: TimedSpinMotion?
    /// 消え切った指の動き。指の動きの火花の分の描き直しを止める。
    @State private var settledDrag: WheelDragMotion?
    /// 火花の種。動きが変わるたびに引き直す。
    @State private var sparkSeed: UInt64 = 0
    /// 指の動きの火花の種。ドラッグを始めるたびに引き直す。
    @State private var dragSeed: UInt64 = 0
    /// はじけた紙吹雪。消え切ったら nil。
    @State private var burst: WheelParticles.Burst?

    var body: some View {
        let sparkMotion = enabled ? motion.flatMap { moving($0) ? $0 : nil } : nil
        let sparkDrag = enabled ? drag.flatMap { $0 != settledDrag && $0.isMoving(now: now()) ? $0 : nil } : nil
        let shownBurst = enabled ? burst : nil
        let animates = WheelParticles.animates(
            reduceMotion: reduceMotion, moving: sparkMotion != nil || sparkDrag != nil, bursting: shownBurst != nil
        )
        TimelineView(.animation(paused: !animates)) { _ in
            // 時刻は `TimelineView` の日付ではなく、動きの開始時刻と同じ時計で取る
            content(animates ? WheelParticles.frame(
                motion: sparkMotion, drag: sparkDrag, burst: shownBurst, now: now(), spinSeed: sparkSeed, dragSeed: dragSeed,
                side: side, colorCount: Theme.confettiColors.count,
                lowPower: lowPower?.isEnabled ?? ProcessInfo.processInfo.isLowPowerModeEnabled, reduceMotion: reduceMotion
            ) : .none)
        }
        // 画面に出たときにすでに動いていても（回転中に演出を切り替えた）種を引く
        .onChange(of: motion, initial: true) { _, motion in
            guard motion != nil else { return }
            var random = SystemRandomNumberGenerator()
            sparkSeed = WheelParticles.seed(using: &random)
        }
        .onChange(of: drag?.start, initial: true) { _, start in
            guard start != nil else { return }
            var random = SystemRandomNumberGenerator()
            dragSeed = WheelParticles.seed(using: &random)
        }
        .onChange(of: burstAt) { _, start in
            guard let start, enabled, !reduceMotion else { return }
            var random = SystemRandomNumberGenerator()
            burst = WheelParticles.Burst(start: start, seed: WheelParticles.seed(using: &random))
        }
        .task(id: motion) {
            guard let motion, !reduceMotion else { return }
            let remaining = motion.remaining(now: now())
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            settledMotion = motion
        }
        .task(id: drag) {
            // 指の動きは止まっても次のドラッグまで残り、親が描き直さないので、最後に生まれた粒が消えたら止める
            guard let drag, !reduceMotion else { return }
            let remaining = drag.remaining(now: now())
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            settledDrag = drag
        }
        .task(id: burst) {
            guard let burst else { return }
            let remaining = burst.start + Config.wheelConfettiDuration - now()
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            self.burst = nil
        }
        .onAppear(perform: watchLowPower)
        .onChange(of: enabled) { watchLowPower() }
    }

    private func watchLowPower() {
        if enabled, lowPower == nil { lowPower = LowPowerModeMonitor() }
    }

    /// 盤面がまだ自分で回っているか。止まり切った惰性は `motion` に残るので、止まり切ったものは除く。
    private func moving(_ motion: TimedSpinMotion) -> Bool {
        motion != settledMotion && motion.isMoving(now: now())
    }
}
