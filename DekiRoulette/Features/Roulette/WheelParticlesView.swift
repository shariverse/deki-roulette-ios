import SwiftUI

/// 2D の盤面の針の先の火花と停止の瞬間の紙吹雪（「スピンの演出」が紙吹雪・全部入りのとき。`docs/SPEC.md` の §5.5）。
/// 盤面が自分で回っている間（`motion`）は針の先から火花を出し、結果が出た瞬間（`stopped` が偽から真になったとき）に盤面の上から紙吹雪をはじけさせる。
/// 粒の位置・大きさ・濃さは `WheelParticles`（`Core/`）が時刻と種から決め、ここは `TimelineView` の毎フレームに
/// `now()`（`RouletteModel.now` と同じ時計）を渡して `Canvas` に描くだけ。火花も紙吹雪も出ていない・動きを減らす設定では
/// `TimelineView` を止めて何も描かない。低電力モードでは粒の数の上限を 1/3 にする。
/// 入力は動き・結果が出ているか・時計だけで、項目・指定（`targetId`）・印・止まったスライスは受け取らない（紙吹雪は結果に依らず同じ）。
/// 読み上げず、触れられない。
struct WheelParticlesView: View {
    /// 盤面の一辺（pt）。粒の速さ・大きさはこれに比例させる。
    let side: CGFloat
    /// 盤面が自分で回っている動き（`RouletteModel.currentMotion`）。
    let motion: TimedSpinMotion?
    /// 結果が出ている（止まったスライスの強調がある）。偽から真になった瞬間に紙吹雪をはじけさせる。
    let stopped: Bool
    let now: () -> TimeInterval

    /// 針の先の y（盤面の枠の上端から pt）。針は 26pt の高さを 6pt 上にずらして置いている（`RouletteWheelView`）。針は盤面の大きさに依らない。
    private static let pointerTipY = CGFloat(ShareImageLayout.basePointerHeight) - 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 最初に画面に出たときに 1 つだけ作る（光の尾と同じ。作る前は今の値を直接読む）。
    @State private var lowPower: LowPowerModeMonitor?
    /// 止まり切った動き。止まり切ったら火花の分の描き直しを止める（光の尾と同じ）。
    @State private var settledMotion: TimedSpinMotion?
    /// 火花の種。動きが変わるたびに引き直す。
    @State private var sparkSeed: UInt64 = 0
    /// 紙吹雪がはじけた時刻（`now()` の秒）と種。消え切ったら nil。
    @State private var burst: Burst?

    private struct Burst: Equatable {
        var start: TimeInterval
        var seed: UInt64
    }

    var body: some View {
        let sparkMotion = motion.flatMap { moving($0) ? $0 : nil }
        let animates = WheelParticles.animates(reduceMotion: reduceMotion, moving: sparkMotion != nil, bursting: burst != nil)
        TimelineView(.animation(paused: !animates)) { _ in
            if animates {
                // 時刻は `TimelineView` の日付ではなく、動きの開始時刻と同じ時計で取る
                let time = now()
                let lowPower = lowPower?.isEnabled ?? ProcessInfo.processInfo.isLowPowerModeEnabled
                let scale = side / CGFloat(WheelLabel.referenceDiameter)
                let sparks = WheelParticles.sparks(
                    motion: sparkMotion, now: time, seed: sparkSeed,
                    origin: CGPoint(x: side / 2, y: Self.pointerTipY),
                    scale: scale, lowPower: lowPower, reduceMotion: reduceMotion
                )
                let confetti = burst.map {
                    WheelParticles.confetti(
                        elapsed: time - $0.start, seed: $0.seed, side: side,
                        colorCount: Theme.confettiColors.count, lowPower: lowPower, reduceMotion: reduceMotion
                    )
                } ?? []
                if !sparks.isEmpty || !confetti.isEmpty {
                    Canvas { context, _ in
                        draw(confetti: confetti, in: &context)
                        draw(sparks: sparks, in: &context)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        // 画面に出たときにすでに動いていても（回転中に演出を切り替えた）種を引く
        .onChange(of: motion, initial: true) { _, motion in
            guard motion != nil else { return }
            var random = SystemRandomNumberGenerator()
            sparkSeed = WheelParticles.seed(using: &random)
        }
        .onChange(of: stopped) { _, stopped in
            guard stopped, !reduceMotion else { return }
            var random = SystemRandomNumberGenerator()
            burst = Burst(start: now(), seed: WheelParticles.seed(using: &random))
        }
        .task(id: motion) {
            guard let motion, !reduceMotion else { return }
            let remaining = motion.remaining(now: now())
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            settledMotion = motion
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
        .onAppear {
            if lowPower == nil { lowPower = LowPowerModeMonitor() }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 盤面がまだ自分で回っているか。止まり切った惰性は `motion` に残るので、止まり切ったものは除く。
    private func moving(_ motion: TimedSpinMotion) -> Bool {
        motion != settledMotion && motion.isMoving(now: now())
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
