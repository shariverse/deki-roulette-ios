import SwiftUI

/// 2D の盤面の光の尾と残像（「スピンの演出」が光の尾・全部入りのとき。`docs/SPEC.md` の §5.5）。
/// 盤面が速く回っている間だけ、回らない層に、遅れた時刻の角度で描いた簡略な盤面（スライスの塗りだけ。ラベル・縁・ハブ・停止の強調なし）を
/// 薄く重ね、盤面の縁の上に針の下から回転の向きと逆へ伸びる光の弧を描く。角度・濃さは `WheelTrails`（`Core/`）が決める。
/// 補間中の角度は observable でないので、盤面が自分で回っている間（`motion`）は `TimelineView` で毎フレーム、
/// `now()`（`RouletteModel.now` と同じ時計）から引く。指で速く動かしている間（`drag`）も、指が回した角度の変化から求めた角速度で
/// 同じように描く（残像は盤面に見えている `rotation + dragRotation` から、指の動きの遅れた角度の差だけずらす）。
/// 動いていない・止まり切った・動きを減らす設定では `TimelineView` を止めて何も描かない。低電力モードでは残像を 1 枚に減らす。
/// 入力は項目（スライスの塗りのため）・動き・時計だけで、指定（`targetId`）・印・止まったスライスは受け取らない。読み上げず、触れられない。
struct WheelTrailsView: View {
    let items: [Item]
    /// 盤面の一辺（pt）。弧の太さと位置はこれに比例させる。
    let side: CGFloat
    let rotation: Double
    let dragRotation: Double
    /// 盤面が自分で回っている動き（`RouletteModel.currentMotion`）。
    let motion: TimedSpinMotion?
    /// 指で動かしている動き（`WheelDragArea` の記録）。指を離したあとも次のドラッグまで残る。
    let drag: WheelDragMotion?
    let now: () -> TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 最初に画面に出たときに 1 つだけ作る（`@State` の初期値の式は View の値が作られるたびに評価され、
    /// ドラッグの指の動きのたびに購読を作り直すことになるため）。作る前は今の値を直接読む。
    @State private var lowPower: LowPowerModeMonitor?
    /// 止まり切った動き。惰性・指の動きは止まり切っても残り、親が描き直さないので、止まり切ったらここに入れて
    /// 描き直させ、`TimelineView` を止める（電飾と同じ）。
    @State private var settledMotion: WheelEffectMotion?

    var body: some View {
        let current = now()
        let effect = WheelEffectMotion.current(spin: motion, drag: drag, now: current)
        let moving = effect.map { $0 != settledMotion && $0.isMoving(now: current) } ?? false
        let animates = WheelTrails.animates(reduceMotion: reduceMotion, moving: moving)
        let colors = items.indices.map { Theme.sliceColor(in: items, at: $0) }
        TimelineView(.animation(paused: !animates)) { _ in
            // 時刻は `TimelineView` の日付ではなく、動きの開始時刻と同じ時計で取る
            let frame = WheelTrails.frame(
                effect: animates ? effect : nil,
                now: now(),
                rotation: rotation,
                dragRotation: dragRotation,
                sliceCount: items.count,
                lowPower: lowPower?.isEnabled ?? ProcessInfo.processInfo.isLowPowerModeEnabled,
                reduceMotion: reduceMotion
            )
            if !frame.isEmpty {
                Canvas { context, size in
                    draw(frame, colors: colors, in: &context, size: size)
                }
            }
        }
        .frame(width: side, height: side)
        .task(id: effect) {
            guard let effect, !reduceMotion else { return }
            let remaining = effect.remaining(now: now())
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            settledMotion = effect
        }
        .onAppear {
            if lowPower == nil { lowPower = LowPowerModeMonitor() }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ frame: WheelTrails.Frame, colors: [Color], in context: inout GraphicsContext, size: CGSize) {
        let scale = side / CGFloat(WheelLabel.referenceDiameter)
        // スライスの円の半径とハブの半径は `WheelFaceView` と同じ（枠から 16pt 内側、ハブは直径 38pt）
        let radius = CGFloat(WheelGeometry.sliceRadius(diameter: Double(side)))
        let hubRadius = 19 * scale
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // 残像。1 枚の盤面は同じ色の円なのでずらしても見えず、描かない。奥（遅れの大きい）から重ねる
        let count = colors.count
        if count > 1 {
            let sliceAngle = 360 / Double(count)
            for ghost in frame.ghosts.reversed() where ghost.opacity > 0 {
                for index in 0..<count {
                    let start = ghost.angle + Double(index) * sliceAngle
                    let path = annularSector(
                        center: center, inner: hubRadius, outer: radius, start: start, end: start + sliceAngle
                    )
                    context.fill(path, with: .color(colors[index].opacity(ghost.opacity)))
                }
            }
        }

        // 光の尾。頭（針の下）がいちばん濃く、尾の先へ区間ごとに薄くする
        if let trail = frame.trail, trail.length > 0, trail.opacity > 0 {
            let ringRadius = radius + Theme.TrailRing.ringOffset * scale
            let segments = Theme.TrailRing.segments
            let range = trail.range
            let step = (range.upperBound - range.lowerBound) / Double(segments)
            for segment in 0..<segments {
                let start = range.lowerBound + step * Double(segment)
                // 頭からの近さ（1 が頭）。時計回りの頭は範囲の終わり、反時計回りは始まり
                let nearHead = trail.direction == .clockwise
                    ? Double(segment + 1) / Double(segments)
                    : Double(segments - segment) / Double(segments)
                let opacity = trail.opacity * nearHead * nearHead
                var arc = Path()
                arc.addArc(
                    center: center, radius: ringRadius,
                    startAngle: .degrees(start - 90), endAngle: .degrees(start + step - 90), clockwise: false
                )
                context.stroke(
                    arc, with: .color(Theme.wheelTrail.opacity(opacity * Theme.TrailRing.glowOpacity)),
                    style: StrokeStyle(lineWidth: Theme.TrailRing.glowWidth * scale, lineCap: .butt)
                )
                context.stroke(
                    arc, with: .color(Theme.wheelTrail.opacity(opacity)),
                    style: StrokeStyle(lineWidth: Theme.TrailRing.coreWidth * scale, lineCap: .butt)
                )
            }
        }
    }

    /// 12 時を 0 度とする時計回りの、内径 `inner`・外径 `outer` の扇形の帯。
    private func annularSector(center: CGPoint, inner: CGFloat, outer: CGFloat, start: Double, end: Double) -> Path {
        var path = Path()
        // SwiftUI は y 軸が下向きなので、clockwise: false で画面上は時計回りになる（`SliceShape` と同じ）
        path.addArc(center: center, radius: outer, startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .degrees(end - 90), endAngle: .degrees(start - 90), clockwise: true)
        path.closeSubpath()
        return path
    }
}
