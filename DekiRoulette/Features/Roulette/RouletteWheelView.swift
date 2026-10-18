import SwiftUI

/// 盤面の描画。回転は親が `rotation` を書き換え、このビューは `rotationEffect` で受ける（補間の曲線はこのビューが保証する）。
/// 角度は 12 時を 0 度として時計回りに数える。針は 12 時に固定。
///
/// `highlightedIndex` を渡すと、そのスライスを止まった位置として強調する（他を強く暗くし、止まったスライスに
/// 縁取りと光彩を付け、渡された瞬間に短く押し出して針を跳ねさせ、そのあとも少し大きいまま前に出しておく）。
/// nil に戻すと強調も解ける。
/// ドラッグ追従とフリックは `WheelDragArea`（3D の盤面と共有）が受け、追従で回した角度を盤面に足す。
/// 結果が出たあとに指で動かしたら強調を解く。`interactive` が false の間（演出中）は追従もフリックもしない。
/// `spinEasing` はスピンの曲線。フリックでは離した瞬間の速さに合わせて親が決める（ボタンでは `Config.spinEasing`）。
/// 盤面の面そのもの（縁・スライス・ラベル・ハブと停止の強調）は `WheelFaceView` で、共有画像（`RouletteShareImageView`）と同じ描画を使う。
struct RouletteWheelView: View {
    let items: [Item]
    let rotation: Double
    var highlightedIndex: Int? = nil
    var interactive = true
    var spinEasing = Config.spinEasing
    /// 回転の補間の長さ。スピンは `Config.spinDuration`、勢いが足りずに惰性で回すときは親が `FlickCoast` から決める。
    var rotationDuration = Config.spinDuration
    /// 止まったスライスの光彩の色（設定の「ルーレットの詳細設定」）。
    var glowStyle = GlowStyle.default
    /// 外周の電飾を出すか（「スピンの演出」が電飾・全部入り）。false なら今の盤面のまま何も足さない。
    var showsLights = false
    /// 盤面が自分で回っている動き（`RouletteModel.currentMotion`）。電飾の流れを毎フレームここから引く。
    var motion: TimedSpinMotion? = nil
    /// `motion` の開始時刻と同じ時計（`RouletteModel.now`）。
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var onBoundaryCross: ((_ time: TimeInterval) -> Void)? = nil
    var onGrab: (() -> Double?)? = nil
    var onRelease: ((_ angularVelocity: Double?, _ dragRotation: Double) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        WheelDragArea(
            count: items.count, rotation: rotation, highlightedIndex: highlightedIndex, interactive: interactive,
            onBoundaryCross: onBoundaryCross, onGrab: onGrab, onRelease: onRelease
        ) { dragRotation, displacedByDrag in
            // 強調するスライス。結果が出たあとに指で動かしたら解く（結果の表示は残る）
            let highlight = displacedByDrag ? nil : highlightedIndex
            ZStack(alignment: .top) {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    WheelFaceView(
                        items: items, side: side, highlight: highlight, glowStyle: glowStyle,
                        highlightScale: highlightScale, animated: !reduceMotion
                    )
                    .frame(width: side, height: side)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                // 追従の角度は足すだけにする。ドラッグ中は `rotation` が変わらないので下の `.animation` は掛からず、指にそのまま付いてくる。
                // 指を離した更新では、親が追従の角度を `rotation` に取り込むのと `dragRotation` を 0 に戻すのが同じ更新に入るので、
                // 見た目の角度は離した位置から続く
                .rotationEffect(.degrees(rotation + dragRotation))
                // キーボードが出た状態で始めると、演出開始で入力欄が無効になってキーボードが閉じ、その安全領域の変化が
                // `withAnimation` の更新に重なって補間が落ちる（盤面が最終角度へ飛び、音だけが鳴る）。回転の値の変化だけは
                // 外側のトランザクションに依らずスピンの曲線で補間させる。曲線は親の `withAnimation` と同じ `spinEasing`。
                // 動きを減らす設定では親が値を直接書くので付けない
                .animation(reduceMotion ? nil : Theme.spinAnimation(easing: spinEasing, duration: rotationDuration), value: rotation)
                .shadow(color: Theme.wheelShadow, radius: 15, y: 10)

                // 電飾は回らない層に置き、縁の上に並べる（盤面の枠と寸法は変えない）。針はその手前
                if showsLights {
                    GeometryReader { proxy in
                        WheelLightsView(
                            side: min(proxy.size.width, proxy.size.height),
                            rotation: rotation,
                            dragRotation: dragRotation,
                            motion: motion,
                            showingResult: highlight != nil,
                            now: now
                        )
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }

                WheelPointerView()
                    .offset(y: -6 + (pulsing ? Theme.pointerBounceOffset : 0))
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .onChange(of: highlightedIndex) { _, index in
            // 止まった瞬間だけ押し出す。動きを減らす設定では暗くするだけにする
            guard index != nil, !reduceMotion else {
                pulsing = false
                return
            }
            withAnimation(Theme.stopPulseAnimation) {
                pulsing = true
            } completion: {
                withAnimation(Theme.stopSettleAnimation) { pulsing = false }
            }
        }
        .accessibilityHidden(true)
    }

    /// 止まったスライスの倍率。動きを減らす設定では大きさを変えない（暗くする・縁取り・光彩だけにする）。
    private var highlightScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return pulsing ? Theme.stopPulseScale : Theme.stopHoldScale
    }
}

/// 盤面の面。縁・スライス・ラベル・中心のハブと、止まったスライスの強調（他を `Theme.sliceDim` で沈め、縁取り・光彩・押し出し）を
/// `side` の正方形に描く。回転・針・ジェスチャは持たず、画面の `RouletteWheelView` と共有画像の `RouletteShareImageView` が同じ描画を使う。
/// 線幅・縁・ハブは基準直径 `WheelLabel.referenceDiameter` を 1 として `side` に比例させ、ラベルの文字サイズと省略は `WheelLabel` に任せる。
struct WheelFaceView: View {
    let items: [Item]
    let side: CGFloat
    /// 止まった位置として強調するスライスの添字。nil なら強調しない。
    var highlight: Int? = nil
    /// 止まったスライスの光彩の色。
    var glowStyle = GlowStyle.default
    /// 止まったスライスの倍率。画面では停止の瞬間の押し出し（`Theme.stopPulseScale`）と結果が出ている間の保持（`stopHoldScale`）を親が渡す。
    var highlightScale: CGFloat = 1
    /// 強調の変化を補間するか。動きを減らす設定と、画像に焼くときは false。
    var animated = true

    private static let referenceSize = CGFloat(WheelLabel.referenceDiameter)
    private static let ink = Theme.onSlice

    var body: some View {
        let scale = side / Self.referenceSize
        let radius = side / 2 - 16 * scale
        let center = CGPoint(x: side / 2, y: side / 2)
        let count = items.count
        let sliceAngle = count > 0 ? 360.0 / Double(count) : 360
        let maxLabelLength = WheelLabel.limit(count: count, diameter: side)
        let fontSize = WheelLabel.fontSize(count: count, diameter: side)

        ZStack {
            Circle().fill(Theme.wheelRim)
                .frame(width: (radius + 11 * scale) * 2, height: (radius + 11 * scale) * 2)
            Circle().strokeBorder(Theme.wheelEdge, lineWidth: 1.5 * scale)
                .frame(width: (radius + 5 * scale) * 2, height: (radius + 5 * scale) * 2)

            if count == 0 {
                Circle().fill(Theme.wheelRim).frame(width: radius * 2, height: radius * 2)
            } else if count == 1 {
                let highlighted = highlight == 0
                Circle().fill(Theme.sliceColor(in: items, at: 0))
                    .overlay(
                        Circle().strokeBorder(Theme.stopOutline, lineWidth: Theme.stopOutlineWidth * scale)
                            .opacity(highlighted ? 1 : 0)
                    )
                    .modifier(StopGlow(
                        shape: Circle(), style: glowStyle, sliceColor: Theme.sliceColor(in: items, at: 0),
                        shown: highlighted, radius: Theme.stopGlowRadius * scale
                    ))
                    .animation(animated ? Theme.stopDimAnimation : nil, value: highlighted)
                    .frame(width: radius * 2, height: radius * 2)
                Text(WheelLabel.display(items[0].label, appearance: items[0].appearance, limit: maxLabelLength))
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(Self.ink)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let start = Double(index) * sliceAngle
                    let end = start + sliceAngle
                    let mid = start + sliceAngle / 2
                    let labelPoint = polar(center: center, angle: mid, radius: radius * WheelLabel.radiusFraction)
                    let highlighted = index == highlight
                    let dimmed = highlight != nil && !highlighted

                    ZStack {
                        SliceShape(startAngle: start, endAngle: end, radius: radius)
                            .fill(Theme.sliceColor(in: items, at: index))
                            .overlay(
                                SliceShape(startAngle: start, endAngle: end, radius: radius)
                                    .stroke(Self.ink, lineWidth: 2 * scale)
                            )

                        Text(WheelLabel.display(item.label, appearance: item.appearance, limit: maxLabelLength))
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundStyle(Self.ink)
                            .fixedSize()
                            // 左半分はそのまま回すと文字が上下逆さまになるため 180 度返す
                            .rotationEffect(.degrees(WheelLabel.rotation(midAngle: mid)))
                            .position(labelPoint)
                    }
                    // 止まったスライス以外に地色を薄く重ねて沈める
                    .overlay(
                        SliceShape(startAngle: start, endAngle: end, radius: radius)
                            .fill(Theme.sliceDim)
                            .opacity(dimmed ? 1 : 0)
                    )
                    // 止まったスライスは縁取りと外側への光彩で浮かせる（前に出すので光彩は沈めた隣に重なる）
                    .overlay(
                        SliceShape(startAngle: start, endAngle: end, radius: radius)
                            .stroke(Theme.stopOutline, style: StrokeStyle(lineWidth: Theme.stopOutlineWidth * scale, lineJoin: .round))
                            .opacity(highlighted ? 1 : 0)
                    )
                    .modifier(StopGlow(
                        shape: SliceShape(startAngle: start, endAngle: end, radius: radius), style: glowStyle,
                        sliceColor: Theme.sliceColor(in: items, at: index), shown: highlighted,
                        radius: Theme.stopGlowRadius * scale
                    ))
                    .animation(animated ? Theme.stopDimAnimation : nil, value: dimmed)
                    .animation(animated ? Theme.stopDimAnimation : nil, value: highlighted)
                    // 止まった瞬間に押し出し、結果が出ている間は少し大きいまま残す。隣に隠れないよう強調中だけ前に出す。
                    // 強調が解けたら（結果が消えた・指で動かした）弾ませて元の大きさに戻す
                    .scaleEffect(highlighted ? highlightScale : 1)
                    .animation(animated ? Theme.stopSettleAnimation : nil, value: highlighted)
                    .zIndex(highlighted ? 1 : 0)
                }
            }

            Group {
                Circle().fill(Theme.wheelHub)
                    .overlay(Circle().strokeBorder(Theme.wheelHubMark, lineWidth: 2.5 * scale))
                    .frame(width: 38 * scale, height: 38 * scale)
                Circle().fill(Theme.wheelHubMark).frame(width: 12 * scale, height: 12 * scale)
            }
            .zIndex(2)
        }
        .frame(width: side, height: side)
    }

    private func polar(center: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        let rad = (angle - 90) * .pi / 180
        return CGPoint(x: center.x + radius * cos(rad), y: center.y + radius * sin(rad))
    }
}

/// 12 時の針。画面では基準直径に依らない 22×26pt の固定（`ShareImageLayout.basePointer*`）で、
/// 共有画像では盤面の直径に比例した大きさを渡す。影も大きさに比例させる。
struct WheelPointerView: View {
    var width = CGFloat(ShareImageLayout.basePointerWidth)
    var height = CGFloat(ShareImageLayout.basePointerHeight)

    var body: some View {
        let scale = height / CGFloat(ShareImageLayout.basePointerHeight)
        Triangle()
            .fill(Theme.flare)
            .frame(width: width, height: height)
            .shadow(color: Theme.pointerShadow, radius: 3 * scale, y: 3 * scale)
    }
}

/// 止まったスライスの外側への光彩。白系と止まったスライスの色は影でにじませる。
/// 虹色は影にできないので、スライスの輪郭を角度のグラデーションで太くなぞってぼかし、スライスの後ろに敷く
/// （スライスの塗りは不透明なので、外側にはみ出した分だけが見える）。3D の盤面も同じ見た目を画像に焼いて使う（`Wheel3DView`）。
struct StopGlow<S: Shape>: ViewModifier {
    let shape: S
    let style: GlowStyle
    let sliceColor: Color
    let shown: Bool
    let radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .white:
            content.shadow(color: shown ? Theme.stopGlow : .clear, radius: radius)
        case .slice:
            content.shadow(color: shown ? sliceColor.opacity(Theme.stopGlowOpacity) : .clear, radius: radius)
        case .rainbow:
            content.background(
                shape.stroke(Theme.stopGlowRainbow, lineWidth: radius)
                    .blur(radius: radius / 2)
                    .opacity(shown ? 1 : 0)
            )
        }
    }
}

/// 12 時を 0 度とする時計回りの扇形。
struct SliceShape: Shape {
    let startAngle: Double
    let endAngle: Double
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        // SwiftUI は y 軸が下向きなので、clockwise: false で画面上は時計回りになる
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle - 90),
            endAngle: .degrees(endAngle - 90),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("4 items") {
    RouletteWheelView(items: ItemLabel.makeItems(["ラーメン", "カレー", "寿司", "焼肉"]), rotation: 0)
        .padding(40)
        .background(Theme.ink900)
}

#Preview("12 items") {
    RouletteWheelView(items: ItemLabel.makeItems((1...12).map { "項目\($0)" }), rotation: 30)
        .padding(40)
        .background(Theme.ink900)
}

#Preview("Lights") {
    RouletteWheelView(
        items: ItemLabel.makeItems(["ラーメン", "カレー", "寿司", "焼肉"]), rotation: 0, showsLights: true
    )
    .padding(40)
    .background(Theme.ink900)
}

#Preview("Stopped") {
    RouletteWheelView(
        items: ItemLabel.makeItems(["ラーメン", "カレー", "寿司", "焼肉"]),
        rotation: 45,
        highlightedIndex: 3
    )
    .padding(40)
    .background(Theme.ink900)
}
