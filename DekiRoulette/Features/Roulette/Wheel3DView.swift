import SceneKit
import SwiftUI

/// 3D 表示の盤面（設定の「3D 表示」が ON のとき）。厚みのある盤・外周の縁・中心のハブと、盤を裏から 1 点で支える支柱を
/// SceneKit で描く。OFF のときの `RouletteWheelView` と同じく、回転は親が `rotation` を書き換え、補間の曲線はこのビューが保証する。
/// 補間は SwiftUI に任せ（`Wheel3DSurface` の `animatableData`）、毎フレームの角度を SceneKit の盤に写すだけにするので、
/// 2D と同じ時刻に同じ角度で止まる。スピンの完了判定は今どおり親の `withAnimation … completion:` と保険のタイマーが担う。
/// 針と結果の帯（`result`）は盤と同じ面に乗せ、盤と一緒に傾ける（回転はしない）。盤が傾いても針が指すスライスと
/// 止まったスライスが一致して見えるようにするため、2D のように画面に固定した層には置かない。
/// 傾いた盤や針がはみ出しても切れないよう、場面は盤面の枠より `Theme.Wheel3D.overscan` だけ広く描く（触れた操作は受けない）。
/// `highlightedIndex` を渡すと、2D と同じくそのスライスを止まった位置として強調する（他を暗くし、縁取りと光彩を付け、
/// 押し出して針を跳ねさせ、結果が出ている間は前に出したままにする）。
/// ドラッグ追従とフリックは 2D と同じ `WheelDragArea` が盤面の枠で受け、追従で回した角度を盤の回転に足す（補間はしない）。
/// 角速度は画面平面上の指の動きで出す。結果が出たあとに指で動かしたら強調だけ解く。
/// 盤は端末の姿勢で傾け、動かした勢いで支点まわりに揺らす（`WheelMotionModel`）。揺れるのは待機中と回転中だけで、
/// 結果表示中は正面へ戻して止め、姿勢の購読も止める。視差効果を減らす設定では揺らさず正面に置く。
/// 姿勢を読むのは、この盤面が画面に出ていてアプリが前面にある間だけ。揺れは見た目だけで、回転・結果・音・触覚には影響しない。
struct Wheel3DView: View {
    let items: [Item]
    let rotation: Double
    var highlightedIndex: Int? = nil
    var interactive = true
    /// 回転の動き（`RouletteModel.rotationPath`）。2D の盤面と同じく、補間の曲線と長さ（焦らしの区間を含む）はここから決める。
    var rotationPath = SpinPath.idle
    /// 止まったスライスの光彩の色（設定の「ルーレットの詳細設定」）。
    var glowStyle = GlowStyle.default
    /// 結果の帯。結果が出ている間だけ渡す。
    var result: Wheel3DResult? = nil
    var onBoundaryCross: ((_ time: TimeInterval) -> Void)? = nil
    var onGrab: (() -> Double?)? = nil
    var onRelease: ((_ angularVelocity: Double?, _ dragRotation: Double) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Config.tiltReferenceKey) private var tiltReference = TiltReference.default
    /// 姿勢の購読。`CMMotionManager` は使い回したいので、ビューを作り直すたびには作らず、最初に画面に出たときに作る。
    @State private var motion: WheelMotionModel?
    @State private var visible = false

    /// 盤の傾き。視差効果を減らす設定では正面。
    private var tilt: WheelTilt {
        reduceMotion ? .zero : motion?.tilt ?? .zero
    }

    private var swayMode: SwayMode {
        SwayMode.mode(showingResult: result != nil, reduceMotion: reduceMotion)
    }

    var body: some View {
        WheelDragArea(
            count: items.count, rotation: rotation, highlightedIndex: highlightedIndex, interactive: interactive,
            onBoundaryCross: onBoundaryCross, onGrab: onGrab, onRelease: onRelease
        ) { dragRotation, displacedByDrag, _ in
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let canvas = side * (1 + 2 * Theme.Wheel3D.overscan)
                // 追従の角度は足すだけにする。ドラッグ中は `rotation` が変わらないので下の `.animation` は掛からず、指にそのまま付いてくる。
                // 指を離した更新では、親が追従の角度を `rotation` に取り込むのと `dragRotation` を 0 に戻すのが同じ更新に入るので、
                // 盤は離した角度から続く
                Wheel3DSurface(
                    items: items, rotation: rotation + dragRotation, tilt: tilt, diameter: side, displayScale: displayScale,
                    // 結果が出たあとに指で動かしたら強調を解く（結果の帯は残る）
                    highlight: displacedByDrag ? nil : highlightedIndex.map { Wheel3DHighlight(index: $0, glowStyle: glowStyle) },
                    result: result, reduceMotion: reduceMotion
                )
                .frame(width: canvas, height: canvas)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .allowsHitTesting(false)
            }
            // 2D の盤面と同じく、回転の値の変化だけは外側のトランザクションに依らずスピンの動き（焦らしの区間を含む）で補間させる
            // （キーボードが閉じる更新に重なっても盤面が最終角度へ飛ばない）。動きを減らす設定では親が値を直接書くので付けない
            .animation(reduceMotion ? nil : Theme.spinAnimation(path: rotationPath), value: rotation)
            .aspectRatio(1, contentMode: .fit)
        }
        .onAppear {
            if motion == nil { motion = WheelMotionModel(source: DeviceMotionSource()) }
            visible = true
            // 「画面を開いたときの持ち方」基準は、画面を開いたときの姿勢を正面にする
            motion?.recaptureBaseline()
            updateMotion()
        }
        .onDisappear {
            visible = false
            updateMotion()
        }
        .onChange(of: scenePhase) { _, phase in
            // アプリに戻ったときも持ち直していることが多いので、基準を取り直す
            if phase == .active { motion?.recaptureBaseline() }
            updateMotion()
        }
        .onChange(of: swayMode) { updateMotion() }
        .onChange(of: tiltReference) { updateMotion() }
        .accessibilityHidden(true)
    }

    private func updateMotion() {
        motion?.update(active: visible && scenePhase == .active, mode: swayMode, reference: tiltReference)
    }
}

/// 3D の盤面に乗せる結果の帯。`id` が変わったときだけ出し直す（2D と同じく `spinCount` 基準）。
struct Wheel3DResult: Equatable {
    let id: String
    let label: String
    /// 帯の枠の色（止まったスライスの塗り）。
    let accent: Color
}

/// 止まったスライスの強調。
struct Wheel3DHighlight: Equatable {
    let index: Int
    let glowStyle: GlowStyle
}

/// 補間中の回転角を毎フレーム受け取る層。SwiftUI が `animatableData` を補間して `body` を描き直す。
private struct Wheel3DSurface: View, Animatable {
    let items: [Item]
    var rotation: Double
    let tilt: WheelTilt
    let diameter: CGFloat
    let displayScale: CGFloat
    let highlight: Wheel3DHighlight?
    let result: Wheel3DResult?
    let reduceMotion: Bool

    nonisolated var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    var body: some View {
        Wheel3DSceneView(
            items: items, rotation: rotation, tilt: tilt, diameter: diameter, displayScale: displayScale,
            highlight: highlight, result: result, reduceMotion: reduceMotion
        )
    }
}

private struct Wheel3DSceneView: UIViewRepresentable {
    let items: [Item]
    let rotation: Double
    let tilt: WheelTilt
    let diameter: CGFloat
    let displayScale: CGFloat
    let highlight: Wheel3DHighlight?
    let result: Wheel3DResult?
    let reduceMotion: Bool

    func makeCoordinator() -> Wheel3DScene {
        Wheel3DScene()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        // 触れたときの操作は SwiftUI 側で受ける
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(items: items, diameter: diameter, displayScale: displayScale)
        context.coordinator.spin(to: rotation)
        context.coordinator.tilt(to: tilt)
        context.coordinator.highlight(highlight, reduceMotion: reduceMotion)
        context.coordinator.show(result: result, reduceMotion: reduceMotion)
    }
}

/// 盤面の 3D の場面。項目のラベル・見た目と大きさが変わったときだけ組み直し、回転は盤のノードの角度を書き換えるだけにする。
@MainActor
final class Wheel3DScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    /// 盤を傾けるノード（支点は表面の中心）。針と結果の帯も載せる。支柱は傾けない。
    private let tiltNode = SCNNode()
    private let pointerNode = SCNNode()
    /// 出している結果の帯。
    private var bandNode: SCNNode?
    private var shownResult: Wheel3DResult?
    /// 結果の帯の登場の動きを流した回数（テストで、出し直しの動きを繰り返していないかを見る）。
    private(set) var bandRevealCount = 0
    /// 盤を回すノード。スライス・縁・ハブを載せる。
    private let spinNode = SCNNode()
    /// 止まっていないスライスに重ねて暗くする層と、前に出した止まったスライス（どちらも `spinNode` に載せる）。
    private var dimNode: SCNNode?
    private var stoppedNode: SCNNode?
    private var shownHighlight: Wheel3DHighlight?
    private let postNode = SCNNode()

    private struct Shape: Equatable {
        /// 項目。比べるのはラベルと見た目だけ（`id` が変わっても見た目が同じなら組み直さない）。
        let items: [Item]
        let diameter: CGFloat
        let displayScale: CGFloat

        var count: Int { items.count }

        static func == (lhs: Shape, rhs: Shape) -> Bool {
            // スピン中は毎フレーム比べるので、配列を作らずに比べる
            lhs.diameter == rhs.diameter
                && lhs.displayScale == rhs.displayScale
                && lhs.items.elementsEqual(rhs.items) { $0.label == $1.label && $0.appearance == $1.appearance }
        }
    }

    private var built: Shape?

    init() {
        let camera = SCNCamera()
        camera.fieldOfView = Theme.Wheel3D.fieldOfView
        camera.projectionDirection = .vertical
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = Theme.Wheel3D.ambientLight
        scene.rootNode.addChildNode(ambient)

        // 左上の手前から照らす。表面のスライスは照明に依らないので、側面・縁・支柱にだけ陰影が付く
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = Theme.Wheel3D.keyLight
        key.eulerAngles = SCNVector3(Float.pi / 6, -Float.pi / 8, 0)
        scene.rootNode.addChildNode(key)

        tiltNode.addChildNode(spinNode)
        tiltNode.addChildNode(pointerNode)
        scene.rootNode.addChildNode(tiltNode)
        scene.rootNode.addChildNode(postNode)
    }

    /// 項目のラベル（件数）・見た目か大きさが変わっていれば盤を組み直す。`displayScale` はラベルを焼く画像の倍率。
    /// 塗りは `Theme.sliceColor(in:at:)`、ラベルは `WheelLabel.display` で 2D と同じに引く。
    func update(items: [Item], diameter: CGFloat, displayScale: CGFloat = 2) {
        let shape = Shape(items: items, diameter: diameter, displayScale: max(displayScale, 1))
        guard shape != built, diameter > 0 else { return }
        built = shape
        build(shape)
    }

    /// 見た目の無い（自動の）項目として組む。
    func update(labels: [String], diameter: CGFloat, displayScale: CGFloat = 2) {
        update(items: ItemLabel.makeItems(labels), diameter: diameter, displayScale: displayScale)
    }

    /// 盤を累積の回転角 `rotation`（度、時計回りが正）まで回す。
    func spin(to rotation: Double) {
        spinNode.eulerAngles.z = Float(WheelGeometry.spinAngle(rotation: rotation))
    }

    /// 盤を傾ける（針と結果の帯も一緒に）。支点は盤の表面の中心で、支柱は傾けない。
    /// `pitch` が正で上端が奥へ（x 軸まわりに負）、`roll` が正で右端が手前へ（y 軸まわりに負）倒れる。
    func tilt(to tilt: WheelTilt) {
        tiltNode.eulerAngles.x = Float(-tilt.pitch * .pi / 180)
        tiltNode.eulerAngles.y = Float(-tilt.roll * .pi / 180)
    }

    /// 結果の帯を出す・消す。`id` が変わったときだけ焼き直し、2D の `revealOnAppear` と同じ動きで現れる
    /// （動きを減らす設定では即座に出す）。消すときは 2D と同じく即座に消す。
    /// 同じ結果のまま文字や枠の色が変わった（結果を出したまま項目の見た目を変えた）ときは、動かさずに焼き直す。
    /// 見た目が変わると先に `update(items:)` が盤を組み直し、出していた帯を前の文字のまま動かさずに焼き直しているので、
    /// ここではその帯を新しい文字・枠の色に差し替える。
    func show(result: Wheel3DResult?, reduceMotion: Bool) {
        if let result, result.id == shownResult?.id, result != shownResult, let old = bandNode, let shape = built {
            shownResult = result
            guard let node = makeBand(result, shape: shape) else { return }
            old.removeFromParentNode()
            tiltNode.addChildNode(node)
            bandNode = node
            return
        }
        guard result?.id != shownResult?.id || (result != nil && bandNode == nil) else { return }
        bandNode?.removeFromParentNode()
        bandNode = nil
        shownResult = result
        guard let result, let shape = built else { return }
        guard let node = makeBand(result, shape: shape) else { return }
        tiltNode.addChildNode(node)
        bandNode = node
        guard !reduceMotion else { return }
        bandRevealCount += 1
        let rest = node.position
        node.opacity = 0
        node.scale = SCNVector3(0.96, 0.96, 1)
        // y は上向きなので、2D で 6pt 下から上がってくるのは -6
        node.position.y = rest.y - 6
        SCNTransaction.begin()
        SCNTransaction.animationDuration = Config.revealAnimationDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        node.opacity = 1
        node.scale = SCNVector3(1, 1, 1)
        node.position = rest
        SCNTransaction.commit()
    }

    /// 止まったスライスを強調する・解く。2D の `RouletteWheelView` と同じ定数で、他のスライスを `Theme.sliceDim` で沈め、
    /// 止まったスライスを縁取りと光彩ごと `stopPulseScale` で押し出して `stopHoldScale` に収め、針を跳ねさせる。
    /// 止まったスライスは縁の高さまで持ち上げ、側面の付いた板として前に出す（隣に隠れず、傾けても浮いて見える）。
    /// 動きを減らす設定では大きさも高さも変えず、暗くする・縁取り・光彩だけを即座に出す。
    /// 大きさが変わって盤を組み直したときは、動かさずに出し直す。
    func highlight(_ highlight: Wheel3DHighlight?, reduceMotion: Bool) {
        let changed = highlight != shownHighlight
        guard changed || (highlight != nil && stoppedNode == nil) else { return }
        shownHighlight = highlight
        let animate = changed && !reduceMotion
        guard let highlight, let shape = built, highlight.index < shape.count else {
            clearHighlight(animated: animate)
            return
        }
        removeHighlightNodes()
        let dim = makeDim(except: highlight.index, shape: shape)
        let stopped = makeStopped(highlight, shape: shape, lifted: !reduceMotion)
        spinNode.addChildNode(dim)
        spinNode.addChildNode(stopped)
        dimNode = dim
        stoppedNode = stopped
        if !reduceMotion {
            stopped.scale = Self.planeScale(Theme.stopHoldScale)
        }
        guard animate else { return }
        // 縁取り・光彩は止まったスライスの塗りとラベルと 1 枚に焼いてあるので、押し出しに任せて薄めない
        dim.opacity = 0
        SCNTransaction.begin()
        SCNTransaction.animationDuration = Self.dimDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        dim.opacity = 1
        SCNTransaction.commit()
        Self.pulse(stopped, keyPath: "scale", from: Self.planeScale(1), peak: Self.planeScale(Theme.stopPulseScale),
                   rest: Self.planeScale(Theme.stopHoldScale))
        // 針は沈んでから戻る（y は上向きなので、2D で下へ沈むのは -）
        Self.pulse(pointerNode, keyPath: "position", from: SCNVector3Zero,
                   peak: SCNVector3(0, -Float(Theme.pointerBounceOffset), 0), rest: SCNVector3Zero)
    }

    private func build(_ shape: Shape) {
        // 強調は組み直したあとに出し直す（`highlight` が `stoppedNode` の無いのを見て作る）
        removeHighlightNodes()
        spinNode.childNodes.forEach { $0.removeFromParentNode() }
        postNode.childNodes.forEach { $0.removeFromParentNode() }
        pointerNode.childNodes.forEach { $0.removeFromParentNode() }
        // 帯は大きさ・見た目に合わせて焼き直す。出していた帯は、組み直しで登場の動きを繰り返さないよう動かさずに出す
        bandNode?.removeFromParentNode()
        bandNode = nil
        defer {
            if let shownResult, let node = makeBand(shownResult, shape: shape) {
                tiltNode.addChildNode(node)
                bandNode = node
            }
        }

        let diameter = Double(shape.diameter)
        let scale = diameter / WheelLabel.referenceDiameter
        // 2D の盤面と同じ割り付け（外周の縁の内側にスライスを置く）
        let radius = diameter / 2 - 16 * scale
        let thickness = Double(Theme.Wheel3D.thickness) * scale
        let count = shape.count

        // 盤面の枠より `overscan` だけ広く描く（ビューも同じだけ広げてあるので、盤の大きさは 2D と同じに見える）
        let canvas = diameter * (1 + 2 * Double(Theme.Wheel3D.overscan))
        cameraNode.position = SCNVector3(
            0, 0, Float(WheelGeometry.cameraDistance(diameter: canvas, fieldOfView: Theme.Wheel3D.fieldOfView))
        )
        cameraNode.camera?.zNear = 1
        cameraNode.camera?.zFar = diameter * 10

        if count == 0 {
            spinNode.addChildNode(sliceNode(start: 0, end: 360, radius: radius, thickness: thickness, color: Theme.wheelRim))
        } else {
            let sliceAngle = 360 / Double(count)
            for index in 0..<count {
                let start = Double(index) * sliceAngle
                spinNode.addChildNode(sliceNode(
                    start: start, end: start + sliceAngle, radius: radius, thickness: thickness,
                    color: Theme.sliceColor(in: shape.items, at: index)
                ))
            }
            if count > 1 {
                addSeparators(count: count, radius: radius, scale: scale)
            }
            addLabels(shape, radius: radius)
        }
        addRim(radius: radius, thickness: thickness, scale: scale)
        addHub(scale: scale)
        addPost(thickness: thickness, scale: scale)
        addPointer(diameter: diameter, scale: scale)
    }

    // MARK: 停止の強調

    /// 2D の `Theme.stopDimAnimation`（easeOut 0.25 秒）。
    private static let dimDuration = 0.25
    /// 2D の `Theme.stopPulseAnimation`（easeOut 0.14 秒）。
    private static let pulseDuration = 0.14

    private static func planeScale(_ value: CGFloat) -> SCNVector3 {
        SCNVector3(Float(value), Float(value), 1)
    }

    /// 2D の押し出し（`stopPulseAnimation` で `peak` へ、`stopSettleAnimation` の弾むばねで `rest` へ）を SceneKit で再現する。
    /// 値はすぐ `rest` にし、見た目だけをアニメーションで動かす。
    private static func pulse(_ node: SCNNode, keyPath: String, from: SCNVector3, peak: SCNVector3, rest: SCNVector3) {
        node.setValue(NSValue(scnVector3: rest), forKeyPath: keyPath)
        let out = CABasicAnimation(keyPath: keyPath)
        out.fromValue = NSValue(scnVector3: from)
        out.toValue = NSValue(scnVector3: peak)
        out.duration = pulseDuration
        out.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // SwiftUI の `.spring(duration: 0.4, bounce: 0.35)` と同じばね
        let settle = CASpringAnimation(perceptualDuration: 0.4, bounce: 0.35)
        settle.keyPath = keyPath
        settle.fromValue = NSValue(scnVector3: peak)
        settle.toValue = NSValue(scnVector3: rest)
        settle.beginTime = pulseDuration
        settle.duration = settle.settlingDuration
        let group = CAAnimationGroup()
        group.animations = [out, settle]
        group.duration = settle.beginTime + settle.duration
        group.isRemovedOnCompletion = true
        node.addAnimation(SCNAnimation(caAnimation: group), forKey: "stopPulse")
    }

    private func removeHighlightNodes() {
        dimNode?.removeFromParentNode()
        stoppedNode?.removeFromParentNode()
        dimNode = nil
        stoppedNode = nil
    }

    /// 強調を解く。2D と同じく暗さと縁取り・光彩を戻しながら、止まったスライスを元の大きさへ戻して外す。
    private func clearHighlight(animated: Bool) {
        guard animated, let dim = dimNode, let stopped = stoppedNode else {
            removeHighlightNodes()
            return
        }
        dimNode = nil
        stoppedNode = nil
        SCNTransaction.begin()
        SCNTransaction.animationDuration = Self.dimDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        SCNTransaction.completionBlock = {
            dim.removeFromParentNode()
            stopped.removeFromParentNode()
        }
        dim.opacity = 0
        stopped.opacity = 0
        stopped.scale = Self.planeScale(1)
        SCNTransaction.commit()
    }

    /// 止まっていないスライスに `Theme.sliceDim` を重ねた 1 枚の板。ラベルと境目の線より手前に置き、2D と同じく一緒に沈める。
    private func makeDim(except index: Int, shape: Shape) -> SCNNode {
        let diameter = Double(shape.diameter)
        let content = DimmedSlices(count: shape.count, except: index, diameter: diameter)
        let node = Self.imagePlane(content, side: diameter, displayScale: shape.displayScale)
        node.position.z = 0.4
        return node
    }

    /// 前に出した止まったスライス。側面の付いた板（塗りの色）の上に、2D と同じ塗り・ラベル・縁取り・光彩を焼いた画像を貼る。
    /// 盤の中心を原点に置くので、`scale` は 2D の `scaleEffect` と同じく盤の中心から広がる。
    private func makeStopped(_ highlight: Wheel3DHighlight, shape: Shape, lifted: Bool) -> SCNNode {
        let diameter = Double(shape.diameter)
        let scale = diameter / WheelLabel.referenceDiameter
        let radius = diameter / 2 - 16 * scale
        let count = shape.count
        // 縁より少し手前（ハブよりは奥）まで持ち上げる。動きを減らす設定では暗くする層のすぐ上に置くだけにする
        let lift = lifted ? Double(Theme.Wheel3D.rimLift) * scale + 0.5 : 0.5
        let group = SCNNode()
        group.position.z = Float(lift)

        let color = Theme.sliceColor(in: shape.items, at: highlight.index)
        let sliceAngle = 360 / Double(max(count, 1))
        let start = count == 1 ? 0 : Double(highlight.index) * sliceAngle
        let mesh = WheelGeometry.sliceMesh(start: start, end: start + sliceAngle, radius: radius, thickness: lift)
        let vector = { (v: SIMD3<Double>) in SCNVector3(Float(v.x), Float(v.y), Float(v.z)) }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: mesh.vertices.map(vector)),
                SCNGeometrySource(normals: mesh.normals.map(vector)),
            ],
            elements: [
                SCNGeometryElement(indices: mesh.top, primitiveType: .triangles),
                SCNGeometryElement(indices: mesh.side, primitiveType: .triangles),
            ]
        )
        geometry.materials = [Self.material(color, lit: false), Self.material(color, lit: true)]
        group.addChildNode(SCNNode(geometry: geometry))

        // 光彩が切れないよう、焼く範囲を光彩の分だけ広げる
        let margin = Double(Theme.stopGlowRadius) * scale * 3
        let content = StoppedSlice(
            items: shape.items, index: highlight.index, diameter: diameter, glowStyle: highlight.glowStyle
        )
        .padding(margin)
        let face = Self.imagePlane(content, side: diameter + margin * 2, displayScale: shape.displayScale)
        face.position.z = 0.1
        group.addChildNode(face)
        return group
    }

    /// SwiftUI のビューを画像に焼き、盤の平面に置く正方形の板にする（中心が盤の中心）。
    private static func imagePlane(_ content: some View, side: Double, displayScale: CGFloat) -> SCNNode {
        let renderer = ImageRenderer(content: content.frame(width: side, height: side).fontDesign(.rounded))
        renderer.scale = displayScale
        let plane = SCNPlane(width: side, height: side)
        let face = material(.white, lit: false)
        face.diffuse.contents = renderer.uiImage
        plane.materials = [face]
        return SCNNode(geometry: plane)
    }

    /// 帯と針を置く奥行き（盤の表面からの高さ）。縁・ハブより手前に出し、針を帯より手前にする。
    private static func bandLift(scale: Double) -> Float {
        Float(Double(max(Theme.Wheel3D.rimLift, Theme.Wheel3D.hubLift)) * scale) + 1
    }

    /// 12 時の針。2D と同じ大きさ（基準直径に依らない 22 × 26pt）・位置（盤面の枠の上端から 6pt はみ出す）・色で、
    /// 盤と一緒に傾けるが回さない。
    private func addPointer(diameter: Double, scale: Double) {
        let width = 22.0, height = 26.0
        let top = diameter / 2 + 6
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -width / 2, y: top))
        path.addLine(to: CGPoint(x: width / 2, y: top))
        path.addLine(to: CGPoint(x: 0, y: top - height))
        path.close()
        let depth = 3.0
        let shape = SCNShape(path: path, extrusionDepth: depth)
        // 表は塗りの色のまま、側面だけ陰影を付ける（SCNShape の素材は表・裏・側面の順）
        shape.materials = [
            Self.material(Theme.flare, lit: false), Self.material(Theme.flare, lit: false), Self.material(Theme.flare, lit: true),
        ]
        let node = SCNNode(geometry: shape)
        node.position.z = Self.bandLift(scale: scale) + Float(depth / 2) + 0.5
        pointerNode.addChildNode(node)
    }

    /// 結果の帯の板。2D と同じ `ResultBandLabel` を画像に焼き、2D と同じく盤面の中心より下（`ResultBand.centerOffset`）に置く。
    /// 傾く面（`tiltNode`）に乗せるので盤と一緒に傾き、回転はしない。ハブ・縁より手前（`bandLift`）に出す。
    private func makeBand(_ result: Wheel3DResult, shape: Shape) -> SCNNode? {
        let diameter = Double(shape.diameter)
        let scale = diameter / WheelLabel.referenceDiameter
        // 影が切れないよう、焼く範囲を影の分だけ広げる
        let margin = 8 * scale
        let content = ResultBandLabel(label: result.label, accent: result.accent, diameter: diameter)
            .padding(margin)
            .fontDesign(.rounded)
        let renderer = ImageRenderer(content: content)
        renderer.scale = shape.displayScale
        renderer.proposedSize = ProposedViewSize(width: ResultBand.maxWidth(diameter: diameter) + margin * 2, height: nil)
        guard let image = renderer.uiImage else { return nil }
        let plane = SCNPlane(width: image.size.width, height: image.size.height)
        let material = Self.material(.white, lit: false)
        material.diffuse.contents = image
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        // 場面の y は上向きなので、中心より下は負
        node.position = SCNVector3(0, Float(-ResultBand.centerOffset(diameter: diameter)), Self.bandLift(scale: scale))
        return node
    }

    /// 1 枚のスライス。表面は照明に依らない塗り、外周の側面は陰影の付く同じ色。
    private func sliceNode(start: Double, end: Double, radius: Double, thickness: Double, color: Color) -> SCNNode {
        let mesh = WheelGeometry.sliceMesh(start: start, end: end, radius: radius, thickness: thickness)
        let vector = { (v: SIMD3<Double>) in SCNVector3(Float(v.x), Float(v.y), Float(v.z)) }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: mesh.vertices.map(vector)),
                SCNGeometrySource(normals: mesh.normals.map(vector)),
            ],
            elements: [
                SCNGeometryElement(indices: mesh.top, primitiveType: .triangles),
                SCNGeometryElement(indices: mesh.side, primitiveType: .triangles),
            ]
        )
        geometry.materials = [Self.material(color, lit: false), Self.material(color, lit: true)]
        return SCNNode(geometry: geometry)
    }

    /// スライスの境目と外周の線（2D の `onSlice` の線と同じ太さ）。
    private func addSeparators(count: Int, radius: Double, scale: Double) {
        let width = 2 * scale
        let ink = Self.material(Theme.onSlice, lit: false)
        let lift: Float = 0.2
        for index in 0..<count {
            let angle = 360 / Double(count) * Double(index)
            let line = SCNBox(width: width, height: radius, length: 0.1, chamferRadius: 0)
            line.materials = [ink]
            let node = SCNNode(geometry: line)
            let middle = WheelGeometry.point(angle: angle, radius: radius / 2)
            node.position = SCNVector3(Float(middle.x), Float(middle.y), lift)
            node.eulerAngles.z = Float(-angle * .pi / 180)
            spinNode.addChildNode(node)
        }
        spinNode.addChildNode(ring(inner: radius - width / 2, outer: radius + width / 2, z: lift, color: Theme.onSlice))
    }

    /// スライスのラベル。2D と同じ位置・向き・省略・文字サイズで 1 枚の画像に焼き、盤の表面（境目の線より手前）に貼る。
    private func addLabels(_ shape: Shape, radius: Double) {
        let diameter = Double(shape.diameter)
        let image = WheelLabelImage.render(
            items: shape.items, diameter: diameter, radius: radius, displayScale: shape.displayScale
        )
        let plane = SCNPlane(width: diameter, height: diameter)
        let material = Self.material(.white, lit: false)
        material.diffuse.contents = image
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.position.z = 0.3
        spinNode.addChildNode(node)
    }

    /// 外周の縁。盤の表面より少し手前に出し、2D と同じ位置に細い線を入れる。
    private func addRim(radius: Double, thickness: Double, scale: Double) {
        let lift = Double(Theme.Wheel3D.rimLift) * scale
        let rim = SCNTube(innerRadius: radius, outerRadius: radius + 11 * scale, height: thickness + lift)
        rim.radialSegmentCount = 96
        rim.materials = [Self.material(Theme.wheelRim, lit: true)]
        let node = SCNNode(geometry: rim)
        node.eulerAngles.x = .pi / 2
        node.position.z = Float((lift - thickness) / 2)
        spinNode.addChildNode(node)
        let edge = 5 * scale
        spinNode.addChildNode(ring(
            inner: radius + edge - 1.5 * scale, outer: radius + edge, z: Float(lift) + 0.1, color: Theme.wheelEdge
        ))
    }

    /// 中心のハブ。2D と同じ大きさで、盤の表面より手前に出す。
    private func addHub(scale: Double) {
        let lift = Double(Theme.Wheel3D.hubLift) * scale
        let hub = SCNCylinder(radius: 19 * scale, height: lift)
        hub.radialSegmentCount = 48
        hub.materials = [Self.material(Theme.wheelHub, lit: true)]
        let node = SCNNode(geometry: hub)
        node.eulerAngles.x = .pi / 2
        node.position.z = Float(lift / 2)
        spinNode.addChildNode(node)
        spinNode.addChildNode(ring(inner: (19 - 2.5) * scale, outer: 19 * scale, z: Float(lift) + 0.1, color: Theme.wheelHubMark))
        let dot = SCNCylinder(radius: 6 * scale, height: 0.1)
        dot.radialSegmentCount = 24
        dot.materials = [Self.material(Theme.wheelHubMark, lit: false)]
        let dotNode = SCNNode(geometry: dot)
        dotNode.eulerAngles.x = .pi / 2
        dotNode.position.z = Float(lift) + 0.2
        spinNode.addChildNode(dotNode)
    }

    /// 盤を裏の中心 1 点で支える支柱。盤と一緒には回さず、傾けもしない。
    private func addPost(thickness: Double, scale: Double) {
        let length = Double(Theme.Wheel3D.postLength) * scale
        let post = SCNCylinder(radius: Double(Theme.Wheel3D.postRadius) * scale, height: length)
        post.radialSegmentCount = 32
        post.materials = [Self.material(Theme.wheelHub, lit: true)]
        let node = SCNNode(geometry: post)
        node.eulerAngles.x = .pi / 2
        node.position.z = Float(-thickness - length / 2)
        postNode.addChildNode(node)
    }

    /// 盤の平面に置く薄い輪。
    private func ring(inner: Double, outer: Double, z: Float, color: Color) -> SCNNode {
        let tube = SCNTube(innerRadius: inner, outerRadius: outer, height: 0.1)
        tube.radialSegmentCount = 96
        tube.materials = [Self.material(color, lit: false)]
        let node = SCNNode(geometry: tube)
        node.eulerAngles.x = .pi / 2
        node.position.z = z
        return node
    }

    /// `lit` が false なら照明に依らず塗りの色のまま出す（盤面の色がライティングでずれないように）。
    private static func material(_ color: Color, lit: Bool) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(color)
        material.lightingModel = lit ? .lambert : .constant
        return material
    }
}

/// 止まっていないスライスに重ねる暗い層（2D の `Theme.sliceDim` の重ね）。盤面の枠と同じ大きさ。
private struct DimmedSlices: View {
    let count: Int
    let except: Int
    let diameter: Double

    var body: some View {
        let scale = diameter / WheelLabel.referenceDiameter
        let radius = diameter / 2 - 16 * scale
        let sliceAngle = 360 / Double(max(count, 1))
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                if index != except {
                    SliceShape(
                        startAngle: Double(index) * sliceAngle, endAngle: Double(index + 1) * sliceAngle, radius: radius
                    )
                    .fill(Theme.sliceDim)
                }
            }
        }
    }
}

/// 止まったスライスの表面。2D の `RouletteWheelView` の強調したスライスと同じ塗り・境目の線・ラベル・縁取り・光彩
/// （`StopGlow`）を、盤面の枠と同じ大きさで描く。
private struct StoppedSlice: View {
    let items: [Item]
    let index: Int
    let diameter: Double
    let glowStyle: GlowStyle

    var body: some View {
        let side = CGFloat(diameter)
        let scale = side / CGFloat(WheelLabel.referenceDiameter)
        let radius = side / 2 - 16 * scale
        let count = items.count
        let color = Theme.sliceColor(in: items, at: index)
        let limit = WheelLabel.limit(count: count, diameter: diameter)
        let font = Font.system(size: WheelLabel.fontSize(count: count, diameter: diameter), weight: .bold)
        ZStack {
            if count == 1 {
                Circle().fill(color)
                    .overlay(Circle().strokeBorder(Theme.stopOutline, lineWidth: Theme.stopOutlineWidth * scale))
                    .modifier(StopGlow(
                        shape: Circle(), style: glowStyle, sliceColor: color, shown: true,
                        radius: Theme.stopGlowRadius * scale
                    ))
                    .frame(width: radius * 2, height: radius * 2)
                Text(WheelLabel.display(items[0].label, appearance: items[0].appearance, limit: limit))
                    .font(font)
                    .foregroundStyle(Theme.onSlice)
            } else {
                let sliceAngle = 360 / Double(count)
                let start = Double(index) * sliceAngle
                let mid = start + sliceAngle / 2
                let slice = SliceShape(startAngle: start, endAngle: start + sliceAngle, radius: radius)
                let point = WheelGeometry.point(angle: mid, radius: Double(radius) * WheelLabel.radiusFraction)
                ZStack {
                    slice.fill(color)
                        .overlay(slice.stroke(Theme.onSlice, lineWidth: 2 * scale))
                    Text(WheelLabel.display(items[index].label, appearance: items[index].appearance, limit: limit))
                        .font(font)
                        .foregroundStyle(Theme.onSlice)
                        .fixedSize()
                        .rotationEffect(.degrees(WheelLabel.rotation(midAngle: mid)))
                        .position(x: side / 2 + CGFloat(point.x), y: side / 2 - CGFloat(point.y))
                }
                .overlay(
                    slice.stroke(Theme.stopOutline, style: StrokeStyle(lineWidth: Theme.stopOutlineWidth * scale, lineJoin: .round))
                )
                .modifier(StopGlow(
                    shape: slice, style: glowStyle, sliceColor: color, shown: true, radius: Theme.stopGlowRadius * scale
                ))
            }
        }
        .frame(width: side, height: side)
    }
}

/// 盤面のラベルを焼いた画像。盤と同じ大きさの正方形で、2D の `RouletteWheelView` と同じ位置・向きに置く
/// （画像の上が 12 時。y は下向きなので、2D の座標の取り方がそのまま使える）。
@MainActor
private enum WheelLabelImage {
    static func render(items: [Item], diameter: Double, radius: Double, displayScale: CGFloat) -> UIImage {
        let count = items.count
        let side = CGFloat(diameter)
        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = false
        let font = roundedBold(size: WheelLabel.fontSize(count: count, diameter: diameter))
        let limit = WheelLabel.limit(count: count, diameter: diameter)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Theme.onSlice)]
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            let context = renderer.cgContext
            let sliceAngle = count > 0 ? 360 / Double(count) : 360
            for (index, item) in items.enumerated() {
                let label = WheelLabel.display(item.label, appearance: item.appearance, limit: limit)
                let text = NSAttributedString(string: label, attributes: attributes)
                let size = text.size()
                context.saveGState()
                if count == 1 {
                    // 1 件だけのときは中央に置く
                    context.translateBy(x: side / 2, y: side / 2)
                } else {
                    let mid = (Double(index) + 0.5) * sliceAngle
                    let point = WheelGeometry.point(angle: mid, radius: radius * WheelLabel.radiusFraction)
                    context.translateBy(x: side / 2 + CGFloat(point.x), y: side / 2 - CGFloat(point.y))
                    context.rotate(by: CGFloat(WheelLabel.rotation(midAngle: mid) * .pi / 180))
                }
                text.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
                context.restoreGState()
            }
        }
    }

    /// 2D の盤面と同じ書体（アプリ全体の `.fontDesign(.rounded)` と `.bold`）。
    private static func roundedBold(size: Double) -> UIFont {
        let font = UIFont.systemFont(ofSize: CGFloat(size), weight: .bold)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return UIFont(descriptor: descriptor, size: CGFloat(size))
    }
}

#Preview("4 items") {
    Wheel3DView(items: ItemLabel.makeItems(["ラーメン", "カレー", "寿司", "焼肉"]), rotation: 0)
        .padding(40)
        .background(Theme.ink900)
}

#Preview("Stopped") {
    Wheel3DView(
        items: ItemLabel.makeItems(["ラーメン", "カレー", "寿司", "焼肉"]), rotation: 45, highlightedIndex: 3
    )
    .padding(40)
    .background(Theme.ink900)
}

#Preview("12 items") {
    Wheel3DView(items: ItemLabel.makeItems((1...12).map { "項目\($0)" }), rotation: 30)
        .padding(40)
        .background(Theme.ink900)
}
