import Foundation
import Observation

/// スピンの結果。結果表示の色を止まったスライスに合わせるため、
/// ラベルだけでなく盤面上の添字も持つ（同じラベルの項目があっても色が一意に決まる）。
struct SpinOutcome: Equatable {
    let index: Int
    let label: String
}

/// 項目・当たり指定・回転・結果のステートとスピンロジック。Web 版 `useRoulette` に対応する。
@MainActor
@Observable
final class RouletteModel {
    private(set) var items: [Item]
    private(set) var targetId: UUID?
    private(set) var spinning = false
    private(set) var outcome: SpinOutcome?

    /// 累積の回転角（度）。View がアニメーションの中で書き込む。
    var rotation: Double = 0

    /// スピン中に針がスライスの境目を越えた回数。境目ごとに触覚を鳴らすトリガで、リセットしない。
    private(set) var boundaryTick = 0
    /// 指で盤面を動かしている間に境目を越えた回数（間引いたあと）。スピン中より強い触覚を鳴らすトリガで、リセットしない。
    private(set) var dragBoundaryTick = 0
    private var dragFeedback = WheelDrag.FeedbackThrottle()

    /// スピン中にクリック音を鳴らす時刻（開始からの秒）。View が再生に渡す。
    private(set) var clickTimes: [TimeInterval] = []

    /// 始めたスピンの回数。同じラベルが続けて出ても結果表示を出し直すための識別子に使う（`rotation` は指で動かしても変わるため使わない）。
    private(set) var spinCount = 0

    /// いまのスピンの曲線。ボタンでは `Config.spinEasing`、フリックでは離した瞬間の速さに合わせて始点の傾きを変える。
    /// View の補間と、回転音・触覚の時刻の逆算はこの曲線を共有する。
    private(set) var spinEasing = Config.spinEasing

    /// 直前のフリックの向き。「スピン」ボタンはこの向きで回す。保存しないので起動ごとに時計回りから始まる。
    private(set) var lastDirection: SpinDirection = .clockwise

    private var pendingOutcome: SpinOutcome?
    private var fallbackTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    /// 項目の保存先。nil のときは保存しない（プレビューやテスト向け）。
    private let store: ItemStore?

    init(items: [Item]) {
        self.items = items
        store = nil
    }

    /// 保存済みの項目から始める。無ければ初期項目。
    init(store: ItemStore) {
        self.store = store
        items = store.load()
    }

    var canSpin: Bool { !spinning && items.count >= Config.minItems }
    var atCapacity: Bool { items.count >= Config.maxItems }

    var result: String? { outcome?.label }

    var marks: Marks {
        guard let targetId else { return [:] }
        return [targetId: .target]
    }

    func addItem(_ raw: String) {
        let label = ItemLabel.normalize(raw)
        guard !label.isEmpty, !atCapacity else { return }
        items.append(Item(label: label))
        outcome = nil
        persist()
    }

    /// 複数のラベルをまとめて追加する。上限に収まらない分は切り捨て、追加できた件数を返す。
    @discardableResult
    func addItems(_ raws: [String]) -> Int {
        let labels = raws.map(ItemLabel.normalize).filter { !$0.isEmpty }
        let accepted = Array(labels.prefix(max(0, Config.maxItems - items.count)))
        guard !accepted.isEmpty else { return 0 }
        items.append(contentsOf: ItemLabel.makeItems(accepted))
        outcome = nil
        persist()
        return accepted.count
    }

    /// 項目を削除し、削除した項目と元の位置を返す。「元に戻す」（`restore`）に使う。
    @discardableResult
    func removeItem(id: UUID) -> RemovedItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items.remove(at: index)
        if targetId == id { targetId = nil }
        outcome = nil
        persist()
        return RemovedItem(item: item, index: index)
    }

    /// 項目をすべて削除する。指定と結果も消える。
    func removeAll() {
        items.removeAll()
        targetId = nil
        outcome = nil
        persist()
    }

    /// 削除した項目を元の位置に戻す。指定は復元しない。
    /// 同じ項目がすでにあるとき、上限に達しているときは何もしない。
    func restore(_ item: Item, at index: Int) {
        guard !items.contains(where: { $0.id == item.id }), !atCapacity else { return }
        items.insert(item, at: min(index, items.count))
        outcome = nil
        persist()
    }

    /// 項目を丸ごと入れ替える。指定と結果は前のリストのものなので捨てる。
    func replaceItems(_ next: [Item]) {
        items = next
        targetId = nil
        outcome = nil
        persist()
    }

    /// 項目の見た目（色・絵文字）を変える。見た目だけなので、指定と結果はそのまま残す。スピン中は変えない。
    func setAppearance(_ appearance: ItemAppearance, for id: UUID) {
        guard !spinning, items.contains(where: { $0.id == id }) else { return }
        items = items.settingAppearance(appearance, for: id)
        persist()
    }

    /// 項目を初期状態に戻す。保存データも消すので、以降は言語設定に応じた初期項目に追従する。
    func resetItems() {
        guard let store else { return }
        replaceItems(store.defaultItems)
        store.clear()
    }

    private func persist() {
        store?.save(items)
    }

    /// 長押しで当たりの指定と解除を切り替える。
    func toggleTarget(id: UUID) {
        targetId = targetId == id ? nil : id
        outcome = nil
    }

    /// 指で回した分だけ盤面を回す（ドラッグの追従を取り込む）。演出中は動かさない。
    /// 次のスピンはこの角度から始まり、止まる累積角・回転音・触覚の時刻もここから求める。結果の決まり方は変わらない。
    func rotate(by delta: Double) {
        guard !spinning, delta != 0 else { return }
        rotation += delta
    }

    /// 指で動かしている盤面の針が、時刻 `time`（秒）に境目を越えた。間引いたうえで触覚の刻み（`dragBoundaryTick`）を進め、
    /// 回転音を鳴らすかを返す。演出中は指で動かせないので何もしない。
    func crossDragBoundary(at time: TimeInterval) -> Bool {
        guard !spinning else { return false }
        let feedback = dragFeedback.cross(at: time)
        if feedback.haptic { dragBoundaryTick += 1 }
        return feedback.click
    }

    /// スピンを開始し、盤面が止まるべき累積回転角を返す。回せないときは nil。
    /// 呼び出し側はこの値を `rotation` にアニメーション付きで反映し、
    /// アニメーション完了時に `finishSpin()` を呼ぶ。
    /// `fullSpins` を渡すと周回数だけをその値にする（フリックの強さの反映）。止まる位置の決め方は変わらない。
    /// `direction` を渡すとその向きに回し、以後のボタンのスピンもその向きを引き継ぐ（フリックの向きの反映）。
    /// 省くと直前に渡された向き（初期値は時計回り）で回す。
    /// `releaseVelocity` に指を離した瞬間の角速度（度/秒）を渡すと、盤面の初速をそれに合わせる（`spinEasing`）。
    /// 長さと止まる位置は変わらない。省くと `Config.spinEasing` で回す（ボタンには初速が無い）。
    func beginSpin(
        reducedMotion: Bool, fullSpins: Int? = nil, direction: SpinDirection? = nil, releaseVelocity: Double? = nil
    ) -> Double? {
        guard canSpin else { return nil }
        if let direction { lastDirection = direction }

        let targetIndex: Int
        if let targetId {
            guard let found = items.firstIndex(where: { $0.id == targetId }) else { return nil }
            targetIndex = found
        } else {
            targetIndex = Int.random(in: 0..<items.count)
        }

        let next = if let fullSpins {
            RouletteMath.nextRotation(
                current: rotation, targetIndex: targetIndex, count: items.count, fullSpins: fullSpins, direction: lastDirection
            )
        } else {
            RouletteMath.nextRotation(current: rotation, targetIndex: targetIndex, count: items.count, direction: lastDirection)
        }
        spinEasing = if let releaseVelocity {
            FlickSpin.easing(angularVelocity: releaseVelocity, distance: abs(next - rotation), duration: Config.spinDuration)
        } else {
            Config.spinEasing
        }
        pendingOutcome = SpinOutcome(index: targetIndex, label: items[targetIndex].label)
        outcome = nil
        spinning = true
        spinCount += 1

        // 補間中の角度は observable でないので、境目を越える時刻を先に求めておく。
        // 動きを減らす設定では盤面が回らないので鳴らさない
        clickTimes = reducedMotion ? [] : SpinTicks.boundaryCrossings(
            from: rotation,
            to: next,
            count: items.count,
            duration: Config.spinDuration,
            easing: spinEasing,
            minInterval: Config.clickMinInterval
        )

        // 完了コールバックが来ない環境（バックグラウンド等）向けの保険
        fallbackTask?.cancel()
        let wait = reducedMotion ? Config.reducedMotionSpinDuration : Config.spinFallback
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.finishSpin()
        }

        // 補間中の角度は observable でないので、境目を越える時刻を先に求めて順に刻む。
        // 動きを減らす設定では回らないので刻まない
        tickTask?.cancel()
        let crossings = reducedMotion ? [] : HapticSchedule.boundaryCrossings(
            from: rotation,
            to: next,
            count: items.count,
            duration: Config.spinDuration,
            easing: spinEasing,
            minInterval: Config.hapticMinInterval
        )
        tickTask = TickScheduler.run(at: crossings) { [weak self] in self?.boundaryTick += 1 }
        return next
    }

    func finishSpin() {
        fallbackTask?.cancel()
        fallbackTask = nil
        tickTask?.cancel()
        tickTask = nil
        spinning = false
        guard let pendingOutcome else { return }
        outcome = pendingOutcome
        self.pendingOutcome = nil
    }
}
