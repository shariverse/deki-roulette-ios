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
/// 演出は 2D と同じ「スピンの演出」（`effects`）を受け取る。電飾（`lights`）のときは 2D と同じ外周の電飾を盤と同じ面の縁の上に出す（回らない）。明るさは 2D と共有の `WheelLightsTimeline` が
/// 同じ時計（`now`）・同じ規則（`WheelLights`）で毎フレーム引き、盤の角度と同じく SceneKit のノードに写す。
/// `trails` のときは 2D と同じ光の尾と残像を盤と同じ面に出す（回らない）。2D と共有の `WheelTrailsTimeline` が同じ時計・同じ規則
/// （`WheelTrails`）で毎フレーム引き、`Wheel3DScene.trail(_:)` が残像の角度・濃さと光の尾の切れ端の濃さだけをノードに写す。
/// 火花・紙吹雪（`particles`）と、停止の瞬間のフラッシュ・結果表示中の光彩の余韻・結果の帯の登場演出（`stopEffects`）も 2D と同じ規則で出す。
/// 火花・紙吹雪は 2D と共有の `WheelParticlesTimeline`、フラッシュと余韻は `WheelStopEffectsTimeline` が同じ時計で引き、
/// `Wheel3DScene.particles(_:)` / `stopEffects(_:)` が盤と同じ面のノードに写す。停止の時刻は 2D と同じ `WheelStopMoment` で持つ。
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
    /// 「スピンの演出」。2D の盤面（`RouletteWheelView`）と同じ値を受け取り、同じ演出を出す。すべて OFF（`.none`）なら今の盤面のまま何も足さない。
    var effects = SpinEffects.none
    /// 盤面が自分で回っている動き（`RouletteModel.currentMotion`）。電飾の流れと明るさ、光の尾・残像・火花を毎フレームここから引く。
    /// 指で動かしている間は、`WheelDragArea` が記録した指の動き（`WheelDragMotion`）から引く。
    var motion: TimedSpinMotion? = nil
    /// `motion` の開始時刻と同じ時計（`RouletteModel.now`）。
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var onBoundaryCross: ((_ time: TimeInterval) -> Void)? = nil
    var onGrab: (() -> Double?)? = nil
    var onRelease: ((_ angularVelocity: Double?, _ dragRotation: Double) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Config.tiltReferenceKey) private var tiltReference = TiltReference.default
    /// 姿勢の購読。`CMMotionManager` は使い回したいので、ビューを作り直すたびには作らず、最初に画面に出たときに作る。
    @State private var deviceMotion: WheelMotionModel?
    @State private var visible = false
    /// 結果が出た時刻。電飾の点滅と脈動・フラッシュ・光彩の余韻・紙吹雪の経過時間の基準（2D の `RouletteWheelView` と同じ持ち方）。
    @State private var stop = WheelStopMoment()

    /// 盤の傾き。視差効果を減らす設定では正面。
    private var tilt: WheelTilt {
        reduceMotion ? .zero : deviceMotion?.tilt ?? .zero
    }

    private var swayMode: SwayMode {
        SwayMode.mode(showingResult: result != nil, reduceMotion: reduceMotion)
    }

    var body: some View {
        WheelDragArea(
            count: items.count, rotation: rotation, highlightedIndex: highlightedIndex, interactive: interactive,
            onBoundaryCross: onBoundaryCross, onGrab: onGrab, onRelease: onRelease,
            // 速さに連動する演出（電飾・光の尾・火花）を出すときだけ、指で動かしている動きを記録する（どれも出さないときは今のまま記録しない）
            tracksMotion: effects.tracksDragMotion, now: now
        ) { dragRotation, displacedByDrag, dragMotion in
            // 強調するスライス（結果が出たあとに指で動かしたら解く。結果の帯は残る）と、停止の演出に渡す時刻。2D と同じ関数で引く
            let cues = stop.cues(
                effects: effects, reduceMotion: reduceMotion, highlightedIndex: highlightedIndex, displacedByDrag: displacedByDrag
            )
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let canvas = side * (1 + 2 * Theme.Wheel3D.overscan)
                // 電飾の明るさは 2D と同じ時計で毎フレーム引く。電飾を出さないときは止めたまま nil を渡す
                WheelLightsTimeline(
                    enabled: effects.lights, rotation: rotation, dragRotation: dragRotation, motion: motion, drag: dragMotion,
                    // 指で動かして強調を解いたら点滅・脈動も止める
                    stoppedAt: cues.lightsStoppedAt,
                    now: now
                ) { lights in
                    // 光の尾・残像も 2D と同じ時計で毎フレーム引く。出さないときは止めたまま `.none` を渡す
                    WheelTrailsTimeline(
                        enabled: effects.trails, sliceCount: items.count, rotation: rotation, dragRotation: dragRotation,
                        motion: motion, drag: dragMotion, now: now
                    ) { trails in
                        // 火花・紙吹雪も 2D と同じ時計・同じ規則で毎フレーム引く。出さないときは止めたまま `.none` を渡す
                        WheelParticlesTimeline(
                            enabled: effects.particles, side: side, motion: motion, drag: dragMotion,
                            burstAt: cues.confettiStart, now: now
                        ) { particles in
                            // フラッシュと光彩の余韻も 2D と同じ時計で引く。停止の演出が OFF なら止めたまま `.none` を渡す
                            WheelStopEffectsTimeline(
                                enabled: effects.stopEffects, flashStart: cues.flashStart,
                                afterglowStart: cues.afterglowStart, now: now
                            ) { stopEffects in
                                // 追従の角度は足すだけにする。ドラッグ中は `rotation` が変わらないので下の `.animation` は掛からず、指にそのまま付いてくる。
                                // 指を離した更新では、親が追従の角度を `rotation` に取り込むのと `dragRotation` を 0 に戻すのが同じ更新に入るので、
                                // 盤は離した角度から続く
                                Wheel3DSurface(
                                    items: items, rotation: rotation + dragRotation, tilt: tilt, diameter: side,
                                    displayScale: displayScale,
                                    highlight: cues.highlight.map { Wheel3DHighlight(index: $0, glowStyle: glowStyle) },
                                    result: result, showsStopEffects: effects.stopEffects,
                                    lights: lights, trails: trails, particles: particles, stopEffects: stopEffects,
                                    reduceMotion: reduceMotion
                                )
                            }
                        }
                    }
                }
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
            if deviceMotion == nil { deviceMotion = WheelMotionModel(source: DeviceMotionSource()) }
            // 結果を出したまま画面に戻った（3D に切り替えた）ときは、2D と同じく停止の瞬間の点滅・フラッシュ・紙吹雪を飛ばして脈動から始める
            stop.appear(showingResult: highlightedIndex != nil, now: now())
            visible = true
            // 「画面を開いたときの持ち方」基準は、画面を開いたときの姿勢を正面にする
            deviceMotion?.recaptureBaseline()
            updateMotion()
        }
        .onDisappear {
            visible = false
            updateMotion()
        }
        .onChange(of: scenePhase) { _, phase in
            // アプリに戻ったときも持ち直していることが多いので、基準を取り直す
            if phase == .active { deviceMotion?.recaptureBaseline() }
            updateMotion()
        }
        .onChange(of: highlightedIndex) { _, index in
            stop.resultChanged(showingResult: index != nil, now: now())
        }
        .onChange(of: swayMode) { updateMotion() }
        .onChange(of: tiltReference) { updateMotion() }
        .accessibilityHidden(true)
    }

    private func updateMotion() {
        deviceMotion?.update(active: visible && scenePhase == .active, mode: swayMode, reference: tiltReference)
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
    /// 停止の演出（`SpinEffects.stopEffects`）が ON か。結果の帯に登場演出（小さい大きさからばね）を重ね、止まったスライスの光彩を余韻で脈打たせられる形にする。
    let showsStopEffects: Bool
    /// 外周の電飾の場面。電飾を出さないときは nil。
    let lights: WheelLights.Scene?
    /// 光の尾と残像。出さないとき・描かない間は `.none`。
    let trails: WheelTrails.Frame
    /// 火花と紙吹雪。出さないとき・描かない間は `.none`。
    let particles: WheelParticles.Frame
    /// フラッシュの不透明度と光彩の余韻の倍率。出さないときは `.none`。
    let stopEffects: WheelStopEffects.Frame
    let reduceMotion: Bool

    nonisolated var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    var body: some View {
        Wheel3DSceneView(
            items: items, rotation: rotation, tilt: tilt, diameter: diameter, displayScale: displayScale,
            highlight: highlight, result: result, showsStopEffects: showsStopEffects, lights: lights, trails: trails,
            particles: particles, stopEffects: stopEffects, reduceMotion: reduceMotion
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
    let showsStopEffects: Bool
    let lights: WheelLights.Scene?
    let trails: WheelTrails.Frame
    let particles: WheelParticles.Frame
    let stopEffects: WheelStopEffects.Frame
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
        context.coordinator.highlight(highlight, reduceMotion: reduceMotion, afterglow: showsStopEffects)
        context.coordinator.show(result: result, reduceMotion: reduceMotion, popIn: showsStopEffects)
        context.coordinator.light(lights)
        context.coordinator.trail(trails)
        context.coordinator.stopEffects(stopEffects)
        context.coordinator.particles(particles)
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
    /// 止まったスライスを余韻で脈打たせられる形（光彩の板と光彩の無い面の板の 2 枚）で出しているか。
    private var shownAfterglow = false
    private let postNode = SCNNode()
    /// 外周の電飾（`tiltNode` に載せ、盤と一緒に傾くが回らない）。電球は初めて出すときに作り（「なし」では作らない）、
    /// 組み直したら作り直し、出さない間は隠す。
    private let lightsNode = SCNNode()
    private var bulbNodes: [SCNNode] = []
    private var haloNodes: [SCNNode] = []
    /// 電球ごとに最後に塗った明るさ。明るさが変わらない電球の素材は書き換えない。
    private var bulbLevels: [Double?] = []
    private var shownLights: WheelLights.Scene?
    /// 電球の素材の色を書き換えた回数（テストで、明るさの変わらない電球を書き換えていないかを見る）。
    private(set) var bulbColorWriteCount = 0
    /// 作った電球の数（テストで、電飾を出さない間は作らないことを見る）。
    var bulbCount: Int { bulbNodes.count }
    /// 残像（`tiltNode` に載せ、盤と一緒に傾くが回らない）。遅れた角度のスライスの塗り（ハブの内側は抜く）の 1 つの形を、
    /// 残像の枚数分のノードで共有し、毎フレーム角度と不透明度だけを変える。初めて描くときに作り（「なし」では作らない）、組み直したら作り直す。
    private let ghostsNode = SCNNode()
    private var ghostNodes: [SCNNode] = []
    /// 光の尾（`tiltNode` に載せ、回らない）。同じ形の弧の切れ端（芯とにじみ）を 12 時から並べ、毎フレーム濃さだけを変える。
    private let trailNode = SCNNode()
    private var trailCoreNodes: [SCNNode] = []
    private var trailGlowNodes: [SCNNode] = []
    /// 切れ端を並べている向き（尾が伸びる側）。
    private var trailDirection: SpinDirection?
    private var shownTrails = WheelTrails.Frame.none
    /// 光の尾・残像のノードを作ったか（テストで、出さない間は作らないことを見る）。
    var hasTrailNodes: Bool { !trailCoreNodes.isEmpty }
    /// 光の尾の切れ端ごとに最後に写した濃さ（隠しているときは nil）。濃さが変わらない切れ端は書き換えない。
    private var trailPieceLevels: [Double?] = []
    /// 光の尾の切れ端の不透明度を書き換えた回数（テストで、濃さの変わらない切れ端を書き換えていないかを見る）。
    private(set) var trailOpacityWriteCount = 0
    /// 電球を縁の上面から浮かせる高さ（pt）。テストで差し替えて、浮かせないと止まったスライスに隠れることを確かめる。
    var lightLift = Theme.Wheel3D.lightLift
    /// 火花と紙吹雪（`tiltNode` に載せ、盤と一緒に傾くが回らない）。粒のノードは初めて描くときに上限の数だけ作り（「なし」では作らない）、
    /// 毎フレーム位置・大きさ・濃さだけを変えて使い回す。紙吹雪は盤面の枠に収まるよう、浮かせた分の遠近の広がりを `confettiNode` の縮みで打ち消す。
    private let particlesNode = SCNNode()
    private let confettiNode = SCNNode()
    private var sparkNodes: [SCNNode] = []
    private var sparkTailNodes: [SCNNode] = []
    private var confettiNodes: [SCNNode] = []
    /// 紙吹雪の色ごとの形（`Theme.confettiColors` の順）。粒の色が変わったら形を差し替える。
    private var confettiGeometries: [SCNGeometry] = []
    private var shownParticles = WheelParticles.Frame.none
    /// 作った粒のノードの数（テストで、出さない間は作らないこと・上限の数だけ作ることを見る）。
    var particleNodeCount: Int { sparkNodes.count + confettiNodes.count }
    /// 出している火花・紙吹雪の数（テストで、2D と同じ数を出すことを見る）。
    var visibleSparkCount: Int { particlesNode.isHidden ? 0 : sparkNodes.filter { !$0.isHidden }.count }
    var visibleConfettiCount: Int { particlesNode.isHidden ? 0 : confettiNodes.filter { !$0.isHidden }.count }
    /// 停止の瞬間のフラッシュ（`tiltNode` に載せる、盤面の枠の丸い光の板）。初めて光らせるときに作る（「なし」では作らない）。
    private var flashNode: SCNNode?
    /// 止まったスライスの光彩の板（余韻で不透明度を脈打たせる）。強調を出している間だけ。
    private var stoppedGlowNode: SCNNode?
    private var shownStopEffects = WheelStopEffects.Frame.none
    /// フラッシュの板を作ったか（テストで、「なし」では作らないことを見る）。
    var hasFlashNode: Bool { flashNode != nil }
    /// フラッシュの板の一辺・縮め・盤の表面からの高さ（テストで、正面から見た半径が盤面の枠の半径になることを確かめる）。
    var flashPlacement: (side: Double, scale: Double, z: Double)? {
        guard let node = flashNode, let plane = node.geometry as? SCNPlane else { return nil }
        return (Double(plane.width), Double(node.scale.x), Double(node.position.z))
    }
    /// 止まったスライスに貼った画像の板の数（テストで、「なし」は 1 枚・余韻を出すときは 2 枚であることを見る）。
    var stoppedImagePlaneCount: Int {
        stoppedNode?.childNodes.filter { $0.geometry is SCNPlane }.count ?? 0
    }
    /// 結果の帯の登場演出（小さい大きさからばね）を流した回数。
    private(set) var bandPopCount = 0

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
        tiltNode.addChildNode(ghostsNode)
        tiltNode.addChildNode(trailNode)
        tiltNode.addChildNode(lightsNode)
        tiltNode.addChildNode(particlesNode)
        particlesNode.addChildNode(confettiNode)
        ghostsNode.isHidden = true
        trailNode.isHidden = true
        lightsNode.isHidden = true
        particlesNode.isHidden = true
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
    /// （動きを減らす設定では即座に出す）。`popIn` のとき（「スピンの演出」が「なし」以外）は、2D の `ResultBandPopIn` と同じく
    /// 帯の中心を軸に `ResultBand.popInStartScale` からばね（`popInDuration` / `popInBounce`）で 1 倍に収める動きを重ねる。
    /// 消すときは 2D と同じく即座に消す。
    /// 同じ結果のまま文字や枠の色が変わった（結果を出したまま項目の見た目を変えた）ときは、動かさずに焼き直す。
    /// 見た目が変わると先に `update(items:)` が盤を組み直し、出していた帯を前の文字のまま動かさずに焼き直しているので、
    /// ここではその帯を新しい文字・枠の色に差し替える。
    func show(result: Wheel3DResult?, reduceMotion: Bool, popIn: Bool = false) {
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
        guard popIn, let plane = node.childNodes.first else { return }
        // 帯の板（子）だけを拡大し、上の現れ方（親）と重ねる。値は 1 のまま、見た目だけをばねで動かす
        bandPopCount += 1
        let spring = CASpringAnimation(perceptualDuration: ResultBand.popInDuration, bounce: ResultBand.popInBounce)
        spring.keyPath = "scale"
        spring.fromValue = NSValue(scnVector3: Self.planeScale(CGFloat(ResultBand.popInStartScale)))
        spring.toValue = NSValue(scnVector3: Self.planeScale(1))
        spring.duration = spring.settlingDuration
        plane.addAnimation(SCNAnimation(caAnimation: spring), forKey: "popIn")
    }

    /// 止まったスライスを強調する・解く。2D の `RouletteWheelView` と同じ定数で、他のスライスを `Theme.sliceDim` で沈め、
    /// 止まったスライスを縁取りと光彩ごと `stopPulseScale` で押し出して `stopHoldScale` に収め、針を跳ねさせる。
    /// 止まったスライスは縁の高さまで持ち上げ、側面の付いた板として前に出す（隣に隠れず、傾けても浮いて見える）。
    /// 動きを減らす設定では大きさも高さも変えず、暗くする・縁取り・光彩だけを即座に出す。
    /// 大きさが変わって盤を組み直したときは、動かさずに出し直す。
    func highlight(_ highlight: Wheel3DHighlight?, reduceMotion: Bool, afterglow: Bool = false) {
        let pulsesGlow = afterglow && !reduceMotion
        let changed = highlight != shownHighlight
        // 結果を出したまま「スピンの演出」を切り替えた（余韻の有無が変わった）ときは、動かさずに出し直す
        if !changed, stoppedNode != nil, pulsesGlow != shownAfterglow { removeHighlightNodes() }
        shownAfterglow = pulsesGlow
        guard changed || (highlight != nil && stoppedNode == nil) else { return }
        shownHighlight = highlight
        let animate = changed && !reduceMotion
        guard let highlight, let shape = built, highlight.index < shape.count else {
            clearHighlight(animated: animate)
            return
        }
        removeHighlightNodes()
        let dim = makeDim(except: highlight.index, shape: shape)
        let (stopped, glow) = makeStopped(highlight, shape: shape, lifted: !reduceMotion, afterglow: pulsesGlow)
        spinNode.addChildNode(dim)
        spinNode.addChildNode(stopped)
        dimNode = dim
        stoppedNode = stopped
        stoppedGlowNode = glow
        glow?.opacity = CGFloat(shownStopEffects.glowLevel)
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
        Self.pulse(stopped, keyPath: .scale, from: Self.planeScale(1), peak: Self.planeScale(Theme.stopPulseScale),
                   rest: Self.planeScale(Theme.stopHoldScale))
        // 針は沈んでから戻る（y は上向きなので、2D で下へ沈むのは -）
        Self.pulse(pointerNode, keyPath: .position, from: SCNVector3Zero,
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
        let radius = WheelGeometry.sliceRadius(diameter: diameter)
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
        // 電球は大きさに合わせて作り直す。出していなければ次に出すときに作る
        removeLights()
        if shownLights != nil { addLights(shape) }
        applyLights()
        removeTrails()
        if !shownTrails.isEmpty { addTrails(shape) }
        applyTrails()
        // フラッシュの板と粒も大きさに合わせて作り直す。出していなければ次に出すときに作る
        removeFlash()
        if shownStopEffects.flashOpacity > 0 { addFlash(shape) }
        removeParticles()
        if !shownParticles.isEmpty { addParticles(shape) }
        applyStopEffects()
        applyParticles()
    }

    // MARK: 光の尾・残像

    /// 止まっていないスライスを暗くする層と、止まったスライスの画像（光彩ごと焼いた板とその上の光彩の無い板）。
    /// どれも深度を書かないので、盤・ラベル（0）より後、残像より前に描く。
    private static let dimRenderingOrder = 1
    private static let stoppedGlowRenderingOrder = 2
    private static let stoppedFaceRenderingOrder = 3
    /// 残像を重ねる順（大きいほど後に描く）。盤・縁・ハブ（0）より後で、光の尾・電飾・結果の帯より前。手前の残像ほど後に描く。
    private static let ghostRenderingOrder = 5
    /// 光の尾のにじみと芯。残像より後、電飾のにじみ（10）と電球（11）より前に描き、電球の奥にする。
    private static let trailGlowRenderingOrder = 8
    private static let trailCoreRenderingOrder = 9
    /// 停止の瞬間のフラッシュ。電飾（10・11）より後に描いて電球の上に重ね、深度は読むので手前の針には隠れる。
    private static let flashRenderingOrder = 15
    /// 紙吹雪、火花の尾、火花の順（2D の `WheelParticlesView` と同じく紙吹雪の上に火花）。深度を読まずにフラッシュより後に描き、
    /// 針・盤の手前に重ねる。結果の帯はその後（2D と同じく帯の奥）。
    private static let confettiRenderingOrder = 16
    private static let sparkTailRenderingOrder = 17
    private static let sparkRenderingOrder = 18
    /// 結果の帯。残像・光の尾・電飾・火花・紙吹雪より後に描く（帯の画像の透明な余白が、奥の残像を深度で隠さないように）。
    private static let bandRenderingOrder = 20

    /// 光の尾と残像を出す・消す。`frame` は 2D と同じ `WheelTrails.Frame`（`.none` なら出さない）で、残像の角度・不透明度と、
    /// 光の尾の切れ端ごとの濃さ（`WheelTrails.Trail.opacity(atDistance:segments:)`）をノードに写す。盤の角度と同じく毎フレーム呼ばれる。
    func trail(_ frame: WheelTrails.Frame) {
        guard frame != shownTrails else { return }
        shownTrails = frame
        if !frame.isEmpty, !hasTrailNodes, let shape = built { addTrails(shape) }
        applyTrails()
    }

    private func applyTrails() {
        let frame = shownTrails
        guard !frame.isEmpty, hasTrailNodes else {
            ghostsNode.isHidden = true
            trailNode.isHidden = true
            return
        }

        // 残像。手前（遅れの少ない）から順。1 件のときは同じ色の円なので作っていない
        ghostsNode.isHidden = frame.ghosts.isEmpty || ghostNodes.isEmpty
        for (index, node) in ghostNodes.enumerated() {
            guard index < frame.ghosts.count, frame.ghosts[index].opacity > 0 else {
                node.isHidden = true
                continue
            }
            let ghost = frame.ghosts[index]
            node.isHidden = false
            node.opacity = CGFloat(ghost.opacity)
            // 累積の角度は大きくなるので、1 周に畳んでから写す（Float の桁落ちを避ける）
            node.eulerAngles.z = Float(WheelGeometry.spinAngle(rotation: ghost.angle.truncatingRemainder(dividingBy: 360)))
        }

        // 光の尾。切れ端の中央の頭からの距離で 2D と同じ濃さを引く。尾の外の切れ端は隠す
        guard let trail = frame.trail, trail.length > 0, trail.opacity > 0 else {
            trailNode.isHidden = true
            return
        }
        trailNode.isHidden = false
        if trailDirection != trail.direction {
            trailDirection = trail.direction
            placeTrailPieces(direction: trail.direction)
        }
        let piece = Theme.Wheel3D.trailPieceAngle
        for index in trailCoreNodes.indices {
            let opacity = trail.opacity(atDistance: (Double(index) + 0.5) * piece, segments: Theme.TrailRing.segments)
            let level: Double? = opacity > 0 ? opacity : nil
            // 濃さが前と同じ切れ端（残像だけが変わったフレーム・尾の外のまま）は書き換えない
            guard trailPieceLevels[index] != level else { continue }
            trailPieceLevels[index] = level
            let core = trailCoreNodes[index], glow = trailGlowNodes[index]
            core.isHidden = level == nil
            glow.isHidden = level == nil
            guard let level else { continue }
            core.opacity = CGFloat(level)
            glow.opacity = CGFloat(level * Theme.TrailRing.glowOpacity)
            trailOpacityWriteCount += 1
        }
    }

    /// 光の尾の切れ端を、12 時（針の下）を頭にして回転の向きと逆へ並べる。時計回りなら反時計回りの側（12 時から負の角度）。
    private func placeTrailPieces(direction: SpinDirection) {
        let piece = Theme.Wheel3D.trailPieceAngle
        for index in trailCoreNodes.indices {
            // 切れ端の形は 0〜`piece` 度。時計回りでは −(i + 1)·piece から、反時計回りでは i·piece から並べる
            let start = direction == .clockwise ? -Double(index + 1) * piece : Double(index) * piece
            let angle = Float(WheelGeometry.spinAngle(rotation: start))
            trailCoreNodes[index].eulerAngles.z = angle
            trailGlowNodes[index].eulerAngles.z = angle
        }
    }

    /// 残像と光の尾のノードを作る。残像はスライスの塗り（2D と同じ `Theme.sliceColor(in:at:)`。ハブの内側は抜く）を 1 つの形にして、
    /// 残像の枚数分のノードで共有する。光の尾は縁の上の環（2D と同じ `Theme.TrailRing` の半径・太さ）の切れ端を最長の長さ分並べる。
    /// どちらも照明に依らない塗りで、深度は書かない（重なった残像どうし・縁の上の電飾を隠さない）。
    private func addTrails(_ shape: Shape) {
        removeTrails()
        let diameter = Double(shape.diameter)
        let scale = diameter / WheelLabel.referenceDiameter
        let radius = WheelGeometry.sliceRadius(diameter: diameter)
        let vector = { (v: SIMD3<Double>) in SCNVector3(Float(v.x), Float(v.y), Float(v.z)) }

        let count = shape.count
        if count > 1 {
            let sliceAngle = 360 / Double(count)
            var vertices: [SCNVector3] = [], normals: [SCNVector3] = []
            var elements: [SCNGeometryElement] = [], materials: [SCNMaterial] = []
            for index in 0..<count {
                let start = Double(index) * sliceAngle
                let mesh = WheelGeometry.annulusMesh(start: start, end: start + sliceAngle, inner: 19 * scale, outer: radius)
                let offset = Int32(vertices.count)
                vertices += mesh.vertices.map(vector)
                normals += mesh.normals.map(vector)
                elements.append(SCNGeometryElement(indices: mesh.top.map { $0 + offset }, primitiveType: .triangles))
                materials.append(Self.overlayMaterial(Theme.sliceColor(in: shape.items, at: index)))
            }
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: elements
            )
            geometry.materials = materials
            let ghostCount = WheelTrails.ghostCount(lowPower: false)
            for index in 0..<ghostCount {
                let node = SCNNode(geometry: geometry)
                node.position.z = Float(Theme.Wheel3D.ghostLift)
                node.isHidden = true
                // 2D と同じく奥（遅れの大きい）から重ねる
                node.renderingOrder = Self.ghostRenderingOrder + (ghostCount - 1 - index)
                ghostsNode.addChildNode(node)
                ghostNodes.append(node)
            }
        }

        let ring = Double(Theme.TrailRing.ringRadius(diameter: CGFloat(diameter)))
        let piece = Theme.Wheel3D.trailPieceAngle
        let z = Float(Double(Theme.Wheel3D.rimLift) * scale + Double(Theme.Wheel3D.trailLift))
        let shapeOf = { (inner: Double, outer: Double) -> SCNGeometry in
            let mesh = WheelGeometry.annulusMesh(start: 0, end: piece, inner: inner, outer: outer)
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: mesh.vertices.map(vector)), SCNGeometrySource(normals: mesh.normals.map(vector))],
                elements: [SCNGeometryElement(indices: mesh.top, primitiveType: .triangles)]
            )
            geometry.materials = [Self.overlayMaterial(Theme.wheelTrail)]
            return geometry
        }
        let coreHalf = Double(Theme.TrailRing.coreWidth) * scale / 2
        let core = shapeOf(ring - coreHalf, ring + coreHalf)
        // にじみは外周の縁の外へはみ出さない（縁の外は盤の無い宙なので、傾けると浮いて見える）
        let glowBounds = Theme.Wheel3D.trailGlowBounds(diameter: CGFloat(diameter))
        let glow = shapeOf(Double(glowBounds.inner), Double(glowBounds.outer))
        let pieces = Int((Config.wheelTrailMaxLength / piece).rounded(.up))
        for _ in 0..<pieces {
            let glowNode = SCNNode(geometry: glow)
            glowNode.position.z = z
            glowNode.renderingOrder = Self.trailGlowRenderingOrder
            glowNode.isHidden = true
            trailNode.addChildNode(glowNode)
            trailGlowNodes.append(glowNode)
            let coreNode = SCNNode(geometry: core)
            coreNode.position.z = z
            coreNode.renderingOrder = Self.trailCoreRenderingOrder
            coreNode.isHidden = true
            trailNode.addChildNode(coreNode)
            trailCoreNodes.append(coreNode)
        }
        trailPieceLevels = Array(repeating: nil, count: pieces)
    }

    private func removeTrails() {
        ghostsNode.childNodes.forEach { $0.removeFromParentNode() }
        trailNode.childNodes.forEach { $0.removeFromParentNode() }
        ghostNodes = []
        trailCoreNodes = []
        trailGlowNodes = []
        trailPieceLevels = []
        trailDirection = nil
    }

    /// 盤の上に薄く重ねる塗り（残像・光の尾）。照明に依らず塗りの色のままにし、不透明度はノードで掛ける。深度は読むが書かない。
    private static func overlayMaterial(_ color: Color) -> SCNMaterial {
        let overlay = material(color, lit: false)
        overlay.writesToDepthBuffer = false
        return overlay
    }

    // MARK: 電飾

    /// 外周の電飾を出す・消す。`scene` は 2D と同じ `WheelLights.Scene`（nil なら出さない）で、電球ごとの明るさとにじみを
    /// `WheelLights.bulb` から引いてノードに写す。盤の角度と同じく毎フレーム呼ばれる。
    func light(_ scene: WheelLights.Scene?) {
        guard scene != shownLights else { return }
        shownLights = scene
        if scene != nil, bulbNodes.isEmpty, let shape = built { addLights(shape) }
        applyLights()
    }

    /// 縁と電球の色の sRGB の成分。毎フレーム塗る色を混ぜるのに使うので、一度だけ求める。
    private static let rimComponents = components(Theme.wheelRim)
    private static let lightComponents = components(Theme.wheelLight)

    /// 電球の色。2D は縁（`wheelRim`）の上に `wheelLight` を明るさの不透明度で重ねるので、その重ねた色（sRGB で混ぜる）を不透明に塗る
    /// （SceneKit は線形の色空間で重ねるので、不透明度で重ねると 2D より明るく見える）。
    static func bulbColor(brightness: Double) -> UIColor {
        let amount = CGFloat(min(max(brightness, 0), 1))
        let rim = rimComponents, light = lightComponents
        return UIColor(
            red: rim.r + (light.r - rim.r) * amount,
            green: rim.g + (light.g - rim.g) * amount,
            blue: rim.b + (light.b - rim.b) * amount,
            alpha: 1
        )
    }

    private static func components(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private func applyLights() {
        guard let scene = shownLights, !bulbNodes.isEmpty else {
            lightsNode.isHidden = true
            return
        }
        lightsNode.isHidden = false
        let count = bulbNodes.count
        let haloFull = Theme.LightRing.bulbRadius + Theme.LightRing.haloWidth
        for index in 0..<count {
            let bulb = WheelLights.bulb(index: index, count: count, scene: scene)
            if bulbLevels[index] != bulb.brightness {
                bulbLevels[index] = bulb.brightness
                bulbNodes[index].geometry?.firstMaterial?.diffuse.contents = Self.bulbColor(brightness: bulb.brightness)
                bulbColorWriteCount += 1
            }
            let halo = haloNodes[index]
            guard bulb.glow > 0 else {
                halo.isHidden = true
                continue
            }
            // 2D と同じく、にじみの広がり（電球の半径 + 幅 × にじみ）と濃さ（`haloOpacity` × にじみ × 明るさ）を変える
            let spread = Float((Theme.LightRing.bulbRadius + Theme.LightRing.haloWidth * CGFloat(bulb.glow)) / haloFull)
            halo.isHidden = false
            halo.opacity = CGFloat(Theme.LightRing.haloOpacity * bulb.glow * bulb.brightness)
            halo.scale = SCNVector3(spread, spread, 1)
        }
    }

    /// 電球を縁の上に並べる（2D と同じ数・位置・大きさ。12 時から時計回り）。縁の上面から `Theme.Wheel3D.lightLift` だけ浮かせ、
    /// 持ち上げた止まったスライスの光彩より手前、針・結果の帯より奥に置く。にじみは電球の後ろの板（放射状のグラデーションを焼いた画像）。
    private func addLights(_ shape: Shape) {
        removeLights()
        let diameter = Double(shape.diameter)
        let scale = diameter / WheelLabel.referenceDiameter
        let displayScale = shape.displayScale
        let side = CGFloat(diameter)
        let ringRadius = Double(Theme.LightRing.ringRadius(diameter: side))
        let bulbRadius = Double(Theme.LightRing.bulbRadius(diameter: side))
        let haloRadius = bulbRadius + Double(Theme.LightRing.haloWidth(diameter: side))
        let z = Float(Double(Theme.Wheel3D.rimLift) * scale + Double(lightLift))
        let haloImage = Self.haloImage(bulbRadius: bulbRadius, haloRadius: haloRadius, displayScale: displayScale)
        let count = Config.wheelLightCount
        for index in 0..<count {
            let point = WheelGeometry.point(angle: WheelLights.angle(index: index, count: count), radius: ringRadius)

            let plane = SCNPlane(width: haloRadius * 2, height: haloRadius * 2)
            let glow = Self.material(.white, lit: false)
            glow.diffuse.contents = haloImage
            // にじみは隣の電球や盤の手前のものを隠さない
            glow.writesToDepthBuffer = false
            plane.materials = [glow]
            let halo = SCNNode(geometry: plane)
            halo.position = SCNVector3(Float(point.x), Float(point.y), z - 0.1)
            halo.isHidden = true
            // 重ねる順を盤より後にして、縁の上に混ぜる
            halo.renderingOrder = 10
            lightsNode.addChildNode(halo)
            haloNodes.append(halo)

            let disc = SCNCylinder(radius: bulbRadius, height: 0.1)
            disc.radialSegmentCount = Theme.Wheel3D.lightSegments
            // 電球ごとに色を変えるので、素材は電球ごとに持つ（色は `applyLights` が明るさから塗る）
            disc.materials = [Self.material(Theme.wheelLight, lit: false)]
            let bulb = SCNNode(geometry: disc)
            bulb.eulerAngles.x = .pi / 2
            bulb.position = SCNVector3(Float(point.x), Float(point.y), z)
            bulb.renderingOrder = 11
            lightsNode.addChildNode(bulb)
            bulbNodes.append(bulb)
        }
        bulbLevels = Array(repeating: nil, count: count)
    }

    private func removeLights() {
        lightsNode.childNodes.forEach { $0.removeFromParentNode() }
        bulbNodes = []
        haloNodes = []
        bulbLevels = []
    }

    /// にじみの画像。2D の `WheelLightsView` と同じく、電球の半径の半分から外へ `wheelLight` を透明まで薄める放射状のグラデーション
    /// （にじみが最も強いときの大きさ。弱いときは板を縮める）。
    private static func haloImage(bulbRadius: Double, haloRadius: Double, displayScale: CGFloat) -> UIImage {
        let side = CGFloat(haloRadius * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(displayScale, 1)
        format.opaque = false
        let light = UIColor(Theme.wheelLight)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            let colors = [light.cgColor, light.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])
            else { return }
            let center = CGPoint(x: side / 2, y: side / 2)
            renderer.cgContext.drawRadialGradient(
                gradient, startCenter: center, startRadius: CGFloat(bulbRadius * 0.5), endCenter: center,
                endRadius: CGFloat(haloRadius), options: .drawsBeforeStartLocation
            )
        }
    }

    // MARK: 火花・紙吹雪

    /// 火花と紙吹雪を出す・消す。`frame` は 2D と同じ `WheelParticles.Frame`（`.none` なら出さない）で、位置は盤面の枠の左上を原点とする pt
    /// （y は下向き）。盤と同じ面（中心が原点、y が上向き）に写し、粒ごとの位置・大きさ・向き・濃さだけをノードに書く。盤の角度と同じく毎フレーム呼ばれる。
    func particles(_ frame: WheelParticles.Frame) {
        guard frame != shownParticles else { return }
        shownParticles = frame
        if !frame.isEmpty, sparkNodes.isEmpty, let shape = built { addParticles(shape) }
        applyParticles()
    }

    private func applyParticles() {
        let frame = shownParticles
        guard let shape = built, !sparkNodes.isEmpty, !frame.isEmpty else {
            particlesNode.isHidden = true
            return
        }
        particlesNode.isHidden = false
        let half = Double(shape.diameter) / 2
        for index in sparkNodes.indices {
            let node = sparkNodes[index], tail = sparkTailNodes[index]
            guard index < frame.sparks.count, frame.sparks[index].opacity > 0 else {
                if !node.isHidden { node.isHidden = true }
                if !tail.isHidden { tail.isHidden = true }
                continue
            }
            let spark = frame.sparks[index]
            let position = SCNVector3(Float(Double(spark.position.x) - half), Float(half - Double(spark.position.y)), 0)
            let radius = Float(spark.radius)
            node.isHidden = false
            node.position = position
            node.scale = SCNVector3(radius, radius, 1)
            node.opacity = CGFloat(spark.opacity)
            // 尾は速度の逆向き（2D の y は下向きなので、場面では符号を返す）に、芯の太さ × 1.4 で伸ばす
            let dx = Double(spark.tail.dx), dy = -Double(spark.tail.dy)
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0.01 else {
                if !tail.isHidden { tail.isHidden = true }
                continue
            }
            tail.isHidden = false
            tail.position = position
            tail.eulerAngles.z = Float(atan2(dy, dx))
            tail.scale = SCNVector3(Float(length), radius * 1.4, 1)
            tail.opacity = CGFloat(spark.opacity)
        }
        for index in confettiNodes.indices {
            let node = confettiNodes[index]
            guard index < frame.confetti.count, frame.confetti[index].opacity > 0 else {
                if !node.isHidden { node.isHidden = true }
                continue
            }
            let piece = frame.confetti[index]
            let geometry = confettiGeometries[piece.colorIndex % confettiGeometries.count]
            if node.geometry !== geometry { node.geometry = geometry }
            node.isHidden = false
            node.position = SCNVector3(Float(Double(piece.position.x) - half), Float(half - Double(piece.position.y)), 0)
            node.scale = SCNVector3(Float(Double(piece.size.width) * piece.flip), Float(piece.size.height), 1)
            // 2D の回転は画面上の時計回りが正。場面の z 軸まわりは反時計回りが正なので返す
            node.eulerAngles.z = Float(-piece.rotation)
            node.opacity = CGFloat(piece.opacity)
        }
    }

    /// 粒のノードを上限の数（火花 `Config.wheelSparkMaxCount`、紙吹雪 `wheelConfettiMaxCount`。低電力モードでもこの数を作り、出すのは 1/3 まで）
    /// だけ作る。火花は芯とにじみを焼いた 1 枚の板と尾の板、紙吹雪は色ごとの形を共有する長方形の板。どれも照明に依らない塗りで深度を読み書きせず、
    /// 針・盤より後（帯より前）に描く。面は針と同じ奥行きに置き、火花が針の先から出て見えるようにする。
    private func addParticles(_ shape: Shape) {
        removeParticles()
        let scale = Double(shape.diameter) / WheelLabel.referenceDiameter
        let z = Self.pointerZ(scale: scale)
        particlesNode.position.z = z
        // 紙吹雪は盤面の枠に収める。浮かせた分だけ遠近で外へ広がって見えるので、その分を縮めて打ち消す
        let shrink = Float(Self.perspectiveShrink(z: Double(z), diameter: Double(shape.diameter)))
        confettiNode.scale = SCNVector3(shrink, shrink, 1)

        let haloScale = Double(Theme.SparkGlow.haloScale)
        let sprite = SCNPlane(width: haloScale * 2, height: haloScale * 2)
        sprite.materials = [Self.particleMaterial(Self.sparkImage)]
        let tailPlane = SCNPlane(width: 1, height: 1)
        tailPlane.materials = [Self.particleMaterial(Self.sparkTailImage)]
        for _ in 0..<Config.wheelSparkMaxCount {
            let tail = SCNNode(geometry: tailPlane)
            // 板の左端（尾の付け根）を粒の位置に置き、x の大きさで尾の長さにする
            tail.pivot = SCNMatrix4MakeTranslation(-0.5, 0, 0)
            tail.renderingOrder = Self.sparkTailRenderingOrder
            tail.isHidden = true
            particlesNode.addChildNode(tail)
            sparkTailNodes.append(tail)
            let node = SCNNode(geometry: sprite)
            node.renderingOrder = Self.sparkRenderingOrder
            node.isHidden = true
            particlesNode.addChildNode(node)
            sparkNodes.append(node)
        }
        confettiGeometries = Theme.confettiColors.map { color in
            let plane = SCNPlane(width: 1, height: 1)
            let material = Self.particleMaterial(nil)
            material.diffuse.contents = UIColor(color)
            // 裏返っても見えるよう両面を塗る
            material.isDoubleSided = true
            plane.materials = [material]
            return plane
        }
        for _ in 0..<Config.wheelConfettiMaxCount {
            let node = SCNNode(geometry: confettiGeometries[0])
            node.renderingOrder = Self.confettiRenderingOrder
            node.isHidden = true
            confettiNode.addChildNode(node)
            confettiNodes.append(node)
        }
    }

    private func removeParticles() {
        sparkNodes.forEach { $0.removeFromParentNode() }
        sparkTailNodes.forEach { $0.removeFromParentNode() }
        confettiNodes.forEach { $0.removeFromParentNode() }
        sparkNodes = []
        sparkTailNodes = []
        confettiNodes = []
        confettiGeometries = []
    }

    /// 粒の素材。照明に依らず塗りの色のまま、深度を読み書きしない（`renderingOrder` の順に重ねる）。不透明度はノードで掛ける。
    private static func particleMaterial(_ image: UIImage?) -> SCNMaterial {
        let material = material(.white, lit: false)
        if let image {
            material.diffuse.contents = image
            material.diffuse.mipFilter = .linear
        }
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        return material
    }

    /// 火花の芯とにじみ。2D の `WheelParticlesView` と同じく、半径 1 の芯（`wheelSpark`）のまわりに半径 `SparkGlow.haloScale` まで
    /// `wheelSparkGlow` を `SparkGlow.haloOpacity` から透明まで薄めるにじみ（板の一辺が `haloScale` × 2）。
    private static let sparkImage: UIImage = {
        let side: CGFloat = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            let context = renderer.cgContext
            let center = CGPoint(x: side / 2, y: side / 2)
            let glow = UIColor(Theme.wheelSparkGlow)
            let colors = [glow.withAlphaComponent(Theme.SparkGlow.haloOpacity).cgColor, glow.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: [])
            }
            let core = side / 2 / Theme.SparkGlow.haloScale
            context.setFillColor(UIColor(Theme.wheelSpark).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))
        }
    }()

    /// 火花の尾。2D と同じく付け根（左）の `wheelSparkGlow` から先（右）の透明まで薄める。
    private static let sparkTailImage: UIImage = {
        let size = CGSize(width: 64, height: 8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let glow = UIColor(Theme.wheelSparkGlow)
            let colors = [glow.cgColor, glow.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])
            else { return }
            renderer.cgContext.drawLinearGradient(
                gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: []
            )
        }
    }()

    // MARK: 停止の瞬間のフラッシュ・余韻

    /// 停止の瞬間のフラッシュの不透明度と、止まったスライスの光彩の余韻の倍率を写す。`frame` は 2D と同じ `WheelStopEffects.Frame`
    /// （`.none` なら光らせず、光彩は今のまま）。盤の角度と同じく毎フレーム呼ばれる。
    func stopEffects(_ frame: WheelStopEffects.Frame) {
        guard frame != shownStopEffects else { return }
        shownStopEffects = frame
        if frame.flashOpacity > 0, flashNode == nil, let shape = built { addFlash(shape) }
        applyStopEffects()
    }

    private func applyStopEffects() {
        let frame = shownStopEffects
        if let flash = flashNode {
            flash.isHidden = frame.flashOpacity <= 0
            if frame.flashOpacity > 0 { flash.opacity = CGFloat(frame.flashOpacity) }
        }
        if let glow = stoppedGlowNode, glow.opacity != CGFloat(frame.glowLevel) {
            glow.opacity = CGFloat(frame.glowLevel)
        }
    }

    /// フラッシュの板。2D の `WheelStopFlashView` と同じ、中心ほど明るく盤面の枠の縁（半径 = 直径 ÷ 2）で 0 になる丸い光（`Theme.stopFlash`）。
    /// ハブより手前・結果の帯と針より奥に置き、浮かせた分の遠近の広がりを縮めて打ち消す（枠の外へ広げない）。
    private func addFlash(_ shape: Shape) {
        removeFlash()
        let diameter = Double(shape.diameter)
        let scale = diameter / WheelLabel.referenceDiameter
        let plane = SCNPlane(width: diameter, height: diameter)
        let material = Self.material(.white, lit: false)
        material.diffuse.contents = Self.flashImage
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        let z = Double(Theme.Wheel3D.hubLift) * scale + 0.5
        node.position.z = Float(z)
        let shrink = Float(Self.perspectiveShrink(z: z, diameter: diameter))
        node.scale = SCNVector3(shrink, shrink, 1)
        node.renderingOrder = Self.flashRenderingOrder
        node.isHidden = true
        tiltNode.addChildNode(node)
        flashNode = node
    }

    private func removeFlash() {
        flashNode?.removeFromParentNode()
        flashNode = nil
    }

    /// フラッシュの丸い光。不透明度 1 で焼き、ノードの不透明度で `WheelStopEffects.flashOpacity` を掛ける。
    private static let flashImage: UIImage = {
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            let flash = UIColor(Theme.stopFlash)
            let colors = [
                flash.cgColor, flash.withAlphaComponent(Theme.StopFlash.middleOpacity).cgColor, flash.withAlphaComponent(0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1])
            else { return }
            let center = CGPoint(x: side / 2, y: side / 2)
            renderer.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side / 2, options: [])
        }
    }()

    /// 盤の表面から `z` だけ浮かせた面を正面から見たとき、表面と同じ大きさに見せる縮み（カメラまでの距離の比）。
    private static func perspectiveShrink(z: Double, diameter: Double) -> Double {
        let canvas = diameter * (1 + 2 * Double(Theme.Wheel3D.overscan))
        let distance = WheelGeometry.cameraDistance(diameter: canvas, fieldOfView: Theme.Wheel3D.fieldOfView)
        return distance > z ? (distance - z) / distance : 1
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
    private static func pulse(_ node: SCNNode, keyPath: PulseKeyPath, from: SCNVector3, peak: SCNVector3, rest: SCNVector3) {
        // 値は型のあるプロパティに直接書く。`setValue(NSValue(scnVector3:), forKeyPath:)` は iOS では成分を読み違えて
        // （`scale` が (3.7e19, 1.88, 3.7e19) のようになる）、動きが終わったあとの盤が壊れる
        switch keyPath {
        case .scale: node.scale = rest
        case .position: node.position = rest
        }
        let keyPath = keyPath.rawValue
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

    /// 押し出しで動かすノードの値。
    private enum PulseKeyPath: String {
        case scale
        case position
    }

    private func removeHighlightNodes() {
        dimNode?.removeFromParentNode()
        stoppedNode?.removeFromParentNode()
        dimNode = nil
        stoppedNode = nil
        stoppedGlowNode = nil
    }

    /// 強調を解く。2D と同じく暗さと縁取り・光彩を戻しながら、止まったスライスを元の大きさへ戻して外す。
    private func clearHighlight(animated: Bool) {
        guard animated, let dim = dimNode, let stopped = stoppedNode else {
            removeHighlightNodes()
            return
        }
        dimNode = nil
        stoppedNode = nil
        stoppedGlowNode = nil
        // 消している間は深度を書かない。回し直す・指で動かすと同時に描き始める残像・光の尾（奥にある）が、薄れていく板の下で深度で隠れないように
        Self.stopWritingDepth(dim)
        Self.stopWritingDepth(stopped)
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

    /// `node` から下の素材をすべて深度を書かないようにする（深度は読むので、手前のものには隠れる）。
    private static func stopWritingDepth(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            child.geometry?.materials.forEach { $0.writesToDepthBuffer = false }
        }
    }

    /// 止まっていないスライスに `Theme.sliceDim` を重ねた 1 枚の板。ラベルと境目の線より手前に置き、2D と同じく一緒に沈める。
    private func makeDim(except index: Int, shape: Shape) -> SCNNode {
        let diameter = Double(shape.diameter)
        let content = DimmedSlices(count: shape.count, except: index, diameter: diameter)
        let node = Self.imagePlane(content, side: diameter, displayScale: shape.displayScale)
        node.position.z = 0.4
        // 深度を書かないので、奥のラベル（0.3）より後に描いてラベルごと沈める
        node.renderingOrder = Self.dimRenderingOrder
        return node
    }

    /// 前に出した止まったスライス。側面の付いた板（塗りの色）の上に、2D と同じ塗り・ラベル・縁取り・光彩を焼いた画像を貼る。
    /// `afterglow`（「なし」以外で余韻を出すとき）は光彩を脈打たせるので、光彩ごと焼いた画像の板（返す `glow`。不透明度を余韻の倍率にする）の上に、
    /// 光彩の無い同じ面の画像の板を重ねる（スライスの中は不透明な塗りなので、外側にはみ出した光彩だけが倍率で薄くなる。倍率 1 なら 1 枚と同じ見た目）。
    /// 「なし」・動きを減らす設定では光彩ごと焼いた 1 枚だけにする（`glow` は nil。消すときに半透明の塗りが 2 枚重なって濃く残らない）。
    /// 盤の中心を原点に置くので、`scale` は 2D の `scaleEffect` と同じく盤の中心から広がる。
    private func makeStopped(
        _ highlight: Wheel3DHighlight, shape: Shape, lifted: Bool, afterglow: Bool
    ) -> (node: SCNNode, glow: SCNNode?) {
        let diameter = Double(shape.diameter)
        let scale = diameter / WheelLabel.referenceDiameter
        let radius = WheelGeometry.sliceRadius(diameter: diameter)
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
        let glow = Self.imagePlane(
            StoppedSlice(items: shape.items, index: highlight.index, diameter: diameter, glowStyle: highlight.glowStyle).padding(margin),
            side: diameter + margin * 2, displayScale: shape.displayScale
        )
        glow.position.z = 0.1
        // 深度を書かないので、暗くする層より後に描く（板の側面と表は深度を書き、奥のものを隠す）
        glow.renderingOrder = Self.stoppedGlowRenderingOrder
        group.addChildNode(glow)
        guard afterglow else { return (group, nil) }
        let face = Self.imagePlane(
            StoppedSlice(
                items: shape.items, index: highlight.index, diameter: diameter, glowStyle: highlight.glowStyle, showsGlow: false
            ).padding(margin),
            side: diameter + margin * 2, displayScale: shape.displayScale
        )
        face.position.z = 0.1
        face.renderingOrder = Self.stoppedFaceRenderingOrder
        group.addChildNode(face)
        return (group, glow)
    }

    /// SwiftUI のビューを画像に焼き、盤の平面に置く正方形の板にする（中心が盤の中心）。
    private static func imagePlane(_ content: some View, side: Double, displayScale: CGFloat) -> SCNNode {
        let renderer = ImageRenderer(content: content.frame(width: side, height: side).fontDesign(.rounded))
        renderer.scale = displayScale
        let plane = SCNPlane(width: side, height: side)
        let face = material(.white, lit: false)
        face.diffuse.contents = renderer.uiImage
        // 画像の透明な画素も深度を書くと、奥に重ねる残像・光の尾（深度を書かず後に描く）が板の形に抜ける。
        // 板は深度を読むので手前のもの（ハブ・針・電球）には隠れ、奥の盤・ラベルより後に描かれる
        face.writesToDepthBuffer = false
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
        node.position.z = Self.pointerZ(scale: scale)
        pointerNode.addChildNode(node)
    }

    /// 針の板の厚みの中央の奥行き（帯より手前）。針の厚みは 3pt。火花・紙吹雪の面もこの奥行きに置く。
    static func pointerZ(scale: Double) -> Float {
        bandLift(scale: scale) + 1.5 + 0.5
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
        let face = SCNNode(geometry: plane)
        // 指で動かして残像が出ても、帯の透明な余白が奥の残像を隠さないよう後に描く
        face.renderingOrder = Self.bandRenderingOrder
        // 現れ方（不透明度・位置・0.96 倍）は親で、登場演出の拡大は板（子）で動かす。どちらも帯の中心が軸
        let node = SCNNode()
        node.addChildNode(face)
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
        let rim = SCNTube(innerRadius: radius, outerRadius: radius + Double(Theme.Wheel3D.rimWidth) * scale, height: thickness + lift)
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
        let radius = WheelGeometry.sliceRadius(diameter: diameter)
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
    /// 光彩を描くか。余韻で光彩だけを脈打たせるため、光彩の無い面も焼く（`Wheel3DScene.makeStopped`）。
    var showsGlow = true

    var body: some View {
        let side = CGFloat(diameter)
        let scale = side / CGFloat(WheelLabel.referenceDiameter)
        let radius = CGFloat(WheelGeometry.sliceRadius(diameter: Double(side)))
        let count = items.count
        let color = Theme.sliceColor(in: items, at: index)
        let limit = WheelLabel.limit(count: count, diameter: diameter)
        let font = Font.system(size: WheelLabel.fontSize(count: count, diameter: diameter), weight: .bold)
        ZStack {
            if count == 1 {
                Circle().fill(color)
                    .overlay(Circle().strokeBorder(Theme.stopOutline, lineWidth: Theme.stopOutlineWidth * scale))
                    .modifier(StopGlow(
                        shape: Circle(), style: glowStyle, sliceColor: color, shown: showsGlow,
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
                    shape: slice, style: glowStyle, sliceColor: color, shown: showsGlow, radius: Theme.stopGlowRadius * scale
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

#Preview("Trails") {
    Wheel3DView(
        items: ItemLabel.makeItems(["ラーメン", "カレー", "寿司", "焼肉"]), rotation: 0, effects: SpinEffectStyle.trails.effects,
        motion: TimedSpinMotion(
            motion: SpinMotion(from: 0, to: 360 * 1200, duration: 600, easing: CubicBezierCurve(0.33, 0.33, 0.67, 0.67)),
            start: ProcessInfo.processInfo.systemUptime
        )
    )
    .padding(40)
    .background(Theme.ink900)
}
