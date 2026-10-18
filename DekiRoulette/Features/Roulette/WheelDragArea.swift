import SwiftUI

/// 盤面のドラッグ追従とフリック。2D の `RouletteWheelView` と 3D の `Wheel3DView` が同じ手触りになるよう共有する。
/// ドラッグ中は追従で回した角度（`dragRotation`）を `content` に渡して盤面を指に追従させ、指を離したら、追従で回した角度と、
/// 離す直前の動きから出した角速度（度/秒、時計回りが正）を `onRelease` に伝える。指を離さずにジェスチャが取り消されたときは
/// 角速度を nil で伝える。追従した角度は親が `rotation` に取り込むまでこのビューが持つ。
/// 追従を始める直前に `onGrab` を呼ぶ（親は惰性で回っている盤面をその場で止める）。
/// `interactive` が false の間（演出中）は追従もフリックもしない。
/// 追従で針がスライスの境目を越えたら、その時刻（秒）を `onBoundaryCross` に伝える（親が回転音と触覚を鳴らす）。
/// 結果が出たあと（`highlightedIndex` が nil でない）に指で動かしたら `displacedByDrag` を立てる（盤面は強調を解く）。
/// 新しい結果（または結果なし）になったら戻す。角速度は画面平面上の指の動きで出す（盤面が傾いていても同じ式）。
struct WheelDragArea<Content: View>: View {
    let count: Int
    let rotation: Double
    let highlightedIndex: Int?
    let interactive: Bool
    let onBoundaryCross: ((_ time: TimeInterval) -> Void)?
    let onGrab: (() -> Void)?
    let onRelease: ((_ angularVelocity: Double?, _ dragRotation: Double) -> Void)?
    @ViewBuilder let content: (_ dragRotation: Double, _ displacedByDrag: Bool) -> Content

    @State private var flickSamples = FlickSampleBuffer()
    /// 追従で回した角度。指を離すと親に渡して 0 に戻す。親の `rotation` と違ってスピンの曲線で補間しない
    @State private var dragRotation = 0.0
    /// 結果が出たあとに盤面を指で動かした。止まったスライスが針の下から外れるので強調を解く
    @State private var displacedByDrag = false
    @State private var dragSession = WheelDragSession()
    @GestureState private var dragging = false

    var body: some View {
        content(dragRotation, displacedByDrag)
            .overlay {
                // ドラッグ中は盤面を指に追従させ、指を離したらその角度からスピンを始める（結果は開始時に決まり、そこから止める）
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .highPriorityGesture(flickGesture(center: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)))
                }
            }
            .onChange(of: dragging) { _, isDragging in
                // 指を離さずにジェスチャが取り消されたときも、追従した角度を親に渡して残す（盤面がその角度で止まり、回さない）。
                // 指を離したときは `onEnded` が先に片付けるので、次のランループで残っているときだけ扱う
                guard !isDragging else { return }
                Task { @MainActor in release(angularVelocity: nil) }
            }
            .onChange(of: highlightedIndex) {
                // 新しい結果（または結果なし）になったら、指で動かした分の強調の解除を戻す
                displacedByDrag = false
            }
    }

    private func flickGesture(center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in
                // 演出中に触り始めたドラッグは、指を離すまで追従もフリックもしない（途中で演出が終わっても拾わない）
                if !dragSession.started {
                    dragSession.started = true
                    dragSession.ignored = !interactive
                    if !dragSession.ignored { onGrab?() }
                }
                guard !dragSession.ignored else { return }
                follow(
                    to: value.location, from: dragSession.lastLocation ?? value.startLocation, center: center,
                    time: value.time.timeIntervalSinceReferenceDate
                )
                flickSamples.append(FlickSpin.Sample(time: value.time.timeIntervalSinceReferenceDate, location: value.location))
            }
            .onEnded { value in
                guard dragSession.started, !dragSession.ignored else {
                    dragSession.reset()
                    return
                }
                follow(
                    to: value.location, from: dragSession.lastLocation ?? value.startLocation, center: center,
                    time: value.time.timeIntervalSinceReferenceDate
                )
                flickSamples.append(FlickSpin.Sample(time: value.time.timeIntervalSinceReferenceDate, location: value.location))
                release(angularVelocity: FlickSpin.angularVelocity(samples: flickSamples.samples, center: center))
            }
    }

    /// 前の位置から今の位置までに指が中心のまわりを回った分だけ盤面を回す。針が境目を越えたら親に伝える（音と触覚）。
    private func follow(to location: CGPoint, from previous: CGPoint, center: CGPoint, time: TimeInterval) {
        dragSession.lastLocation = location
        let delta = WheelDrag.rotationDelta(from: previous, to: location, center: center)
        guard delta != 0 else { return }
        let before = rotation + dragRotation
        dragRotation += delta
        if highlightedIndex != nil { displacedByDrag = true }
        if WheelDrag.boundaryCrossings(from: before, to: rotation + dragRotation, count: count) > 0 {
            onBoundaryCross?(time)
        }
    }

    /// 指を離した（またはジェスチャが取り消された。角速度は nil）。追従した角度と角速度を親に渡す。
    /// `dragRotation` を 0 に戻すのと、親がそれを `rotation` に取り込むのを同じ更新に入れて、盤面が跳ねないようにする。
    private func release(angularVelocity: Double?) {
        let active = dragSession.started && !dragSession.ignored
        dragSession.reset()
        flickSamples.reset()
        guard active else { return }
        let rotated = dragRotation
        dragRotation = 0
        onRelease?(angularVelocity, rotated)
    }
}

/// 1 回のドラッグの途中経過。指が動くたびに書き換えるので、View を描き直さないよう参照型で持つ。
@MainActor
final class WheelDragSession {
    /// ドラッグが始まり、まだ指を離していない。
    var started = false
    /// 演出中に始まったドラッグ。指を離すまで追従もフリックもしない。
    var ignored = false
    /// 直前に追従した指の位置。nil ならまだ追従していない（最初の 1 回は `startLocation` から測る）。
    var lastLocation: CGPoint?

    func reset() {
        started = false
        ignored = false
        lastLocation = nil
    }
}
