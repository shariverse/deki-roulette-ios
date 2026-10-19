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

    /// スピン中（または惰性で回る間）に針がスライスの境目を越えた回数。境目ごとに触覚を鳴らすトリガで、リセットしない。
    private(set) var boundaryTick = 0
    /// 指で盤面を動かしている間に境目を越えた回数（間引いたあと）。スピン中より強い触覚を鳴らすトリガで、リセットしない。
    private(set) var dragBoundaryTick = 0
    private var dragFeedback = WheelDrag.FeedbackThrottle()

    /// スピン中（または惰性で回る間）にクリック音を鳴らす時刻（開始からの秒）。View が再生に渡す。
    private(set) var clickTimes: [TimeInterval] = []

    /// スピン中に流すうなり（ドラムロール）の打ち（`SpinHum.strokes(along:)`）。View が再生に渡す。
    /// 「スピンの演出」が「なし」・動きを減らす設定・惰性では空（鳴らさない）。指定の有無では変わらない。
    private(set) var humStrokes: [SpinHum.Stroke] = []

    /// 始めたスピンの回数。同じラベルが続けて出ても結果表示を出し直すための識別子に使う（`rotation` は指で動かしても変わるため使わない）。
    private(set) var spinCount = 0

    /// いま（または直前）の回転の動き。View の補間（`Theme.spinAnimation(path:)`）と、回転音・触覚の時刻・完了の保険はこの動きを共有する。
    /// スピンは `SpinPath.spin`（演出「なし」なら `Config.spinDuration` 秒・`Config.spinEasing` の区間 1 つ。フリックでは
    /// 離した瞬間の速さに合わせて始点の傾きを変える。「なし」以外では止まり際の焦らしを足した区間の列）、
    /// 勢いが足りずに惰性で回すときは `FlickCoast` が決めた区間 1 つ。
    private(set) var rotationPath = SpinPath.idle

    /// 直前のフリックの向き。「スピン」ボタンはこの向きで回す。保存しないので起動ごとに時計回りから始まる。
    private(set) var lastDirection: SpinDirection = .clockwise

    /// いま盤面が自分で回っている動き（スピン・惰性）と、その開始時刻（`now()` の時計の秒）。
    /// 補間中の角度は observable でないので、速さに連動する演出は `TimelineView` で毎フレーム
    /// `motion.angle(at:)` / `angularVelocity(at:)` に `now() - start` を渡して引く。動きを減らす設定のスピン（回らない）と、
    /// 止まったあと（スピンの完了・惰性を止めた・指で回した）は nil。惰性は止まり切っても次の操作までは残る（長さを過ぎた角速度は 0）。
    private(set) var currentMotion: TimedSpinMotion?

    private var pendingOutcome: SpinOutcome?
    /// 惰性で回っている動き。補間中の角度は observable でないので、途中で盤面に触れたときはここから今の角度を逆算する。
    private var coasting: Coasting?
    private var fallbackTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    /// 項目の保存先。nil のときは保存しない（プレビューやテスト向け）。
    private let store: ItemStore?

    /// 今の時刻（秒）。惰性の途中の角度の逆算に使う。テストで差し替える。
    @ObservationIgnored var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    /// スピンの乱数の取得元（止まる項目・止まる位置と周回数・焦らしの入り方）。テストで決まった列に差し替える。
    /// 指定の有無で引く回数と順番が変わらないよう、`beginSpin` は指定があっても止まる項目の乱数を引く。
    @ObservationIgnored var randomSource = AnyRandomNumberGenerator(SystemRandomNumberGenerator())

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
        currentMotion = nil
        rotation += delta
    }

    /// 勢いの足りないフリックで指を離したあと、盤面を少しだけ惰性で回す。止まるべき累積回転角を返す。惰性を付けないときは nil。
    /// 抽選ではないので、結果・`spinCount`・`pendingOutcome`・「スピン」ボタンの向き（`lastDirection`）は変えない。
    /// 呼び出し側はこの値を `rotation` に `Theme.spinAnimation(path: rotationPath)` で反映する。
    /// 演出中と動きを減らす設定では付けない（離した角度のまま止める）。
    /// スピンと同じく、針が境目を越える時刻を惰性の曲線から先に求め、回転音の時刻（`clickTimes`）と
    /// 触覚の刻み（`boundaryTick`。盤面が自分で回っている間なのでスピン中と同じ `.selection`）を用意する。
    func beginCoast(angularVelocity: Double, reducedMotion: Bool) -> Double? {
        guard !spinning, !reducedMotion, let coast = FlickCoast.coast(angularVelocity: angularVelocity) else { return nil }
        let path = SpinPath(coast.motion(from: rotation))
        rotationPath = path
        let start = now()
        coasting = Coasting(from: rotation, start: start, coast: coast)
        currentMotion = TimedSpinMotion(path: path, start: start)

        clickTimes = SpinTicks.boundaryCrossings(along: path, count: items.count, minInterval: Config.clickMinInterval)
        // 抽選しないので、うなりは付けない
        humStrokes = []
        tickTask?.cancel()
        let crossings = HapticSchedule.boundaryCrossings(along: path, count: items.count, minInterval: Config.hapticMinInterval)
        tickTask = TickScheduler.run(at: crossings) { [weak self] in self?.boundaryTick += 1 }
        return path.to
    }

    /// 惰性で回っている途中なら、今の角度を曲線から逆算して返し、惰性を打ち切る（盤面に再び触れた、画面を離れたとき）。
    /// 残りの触覚の刻みも止める（回転音は View が `SpinSoundPlayer.stop()` で止める）。
    /// 呼び出し側はこの値を補間なしで `rotation` に書く。惰性で回っていない・もう止まっているときは nil（何もしない）。
    @discardableResult
    func stopCoast() -> Double? {
        guard let coasting else { return nil }
        self.coasting = nil
        currentMotion = nil
        tickTask?.cancel()
        tickTask = nil
        let elapsed = now() - coasting.start
        guard elapsed < coasting.coast.duration else { return nil }
        return coasting.from + coasting.coast.angle(after: max(elapsed, 0))
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
    /// 呼び出し側はこの値を `rotation` に `Theme.spinAnimation(path: rotationPath)` で反映し、
    /// アニメーション完了時に `finishSpin()` を呼ぶ。
    /// `effects` は「スピンの演出」。焦らし（`tease`）が ON なら止まり際の焦らし（`SpinTease`）を入れ（動きを減らす設定では入れない）、
    /// 演出の効果音（`sounds`）が ON ならうなりの打ちを用意する。
    /// 焦らしは止まる位置を変えず、入り方は演出の設定・乱数・止まる累積角と件数だけで決める（指定は渡さない）。
    /// `fullSpins` を渡すと周回数だけをその値にする（フリックの強さの反映）。止まる位置の決め方は変わらない。
    /// `direction` を渡すとその向きに回し、以後のボタンのスピンもその向きを引き継ぐ（フリックの向きの反映）。
    /// 省くと直前に渡された向き（初期値は時計回り）で回す。
    /// `releaseVelocity` に指を離した瞬間の角速度（度/秒）を渡すと、盤面の初速をそれに合わせる（`SpinPath.spin` が主の区間の曲線を決める）。
    /// 長さと止まる位置は変わらない。省くと `Config.spinEasing` で回す（ボタンには初速が無い）。
    func beginSpin(
        reducedMotion: Bool, effects: SpinEffects = .none, fullSpins: Int? = nil,
        direction: SpinDirection? = nil, releaseVelocity: Double? = nil
    ) -> Double? {
        guard canSpin else { return nil }
        if let targetId, !items.contains(where: { $0.id == targetId }) { return nil }
        if let direction { lastDirection = direction }

        // 乱数は指定の有無に依らず同じ順・同じ回数で引く（止まる項目 → 止まる位置と周回数 → 焦らしの入り方）。
        // 指定があるときも止まる項目の乱数を引いてから捨てるので、後に続く焦らしの入り方が指定の有無で変わらない
        let drawnIndex = Int.random(in: 0..<items.count, using: &randomSource)
        let targetIndex = targetId.flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? drawnIndex

        // 惰性の途中で始めたら、惰性はそこで打ち切る（止まる位置は惰性の行き先の `rotation` から求める）。
        // 惰性の音と触覚の刻みは、下でスピンのものに差し替える
        coasting = nil

        let next = if let fullSpins {
            RouletteMath.nextRotation(
                current: rotation, targetIndex: targetIndex, count: items.count, fullSpins: fullSpins,
                direction: lastDirection, using: &randomSource
            )
        } else {
            RouletteMath.nextRotation(
                current: rotation, targetIndex: targetIndex, count: items.count, direction: lastDirection, using: &randomSource
            )
        }
        // 動きを減らす設定では回さないので、焦らしを入れない（乱数も引かない）
        let path = SpinPath.spin(
            from: rotation, to: next, count: items.count, effects: reducedMotion ? .none : effects,
            releaseVelocity: releaseVelocity, using: &randomSource
        )
        rotationPath = path
        pendingOutcome = SpinOutcome(index: targetIndex, label: items[targetIndex].label)
        outcome = nil
        spinning = true
        spinCount += 1
        currentMotion = reducedMotion ? nil : TimedSpinMotion(path: path, start: now())

        // 補間中の角度は observable でないので、境目を越える時刻を先に求めておく。焦らしで戻る向きに越える境目も数える。
        // 動きを減らす設定では盤面が回らないので鳴らさない
        clickTimes = reducedMotion ? [] : SpinTicks.boundaryCrossings(
            along: path, count: items.count, minInterval: Config.clickMinInterval
        )
        // うなりも同じ動きから打つ時刻と強さを先に求める。「なし」と動きを減らす設定では付けない
        humStrokes = SpinHum.plays(effects: effects, reducedMotion: reducedMotion) ? SpinHum.strokes(along: path) : []

        // 完了コールバックが来ない環境（バックグラウンド等）向けの保険。長さ（焦らしを含む）の 0.6 秒後
        fallbackTask?.cancel()
        let wait = reducedMotion ? Config.reducedMotionSpinDuration : path.fallback
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.finishSpin()
        }

        // 補間中の角度は observable でないので、境目を越える時刻を先に求めて順に刻む。
        // 動きを減らす設定では回らないので刻まない
        tickTask?.cancel()
        let crossings = reducedMotion ? [] : HapticSchedule.boundaryCrossings(
            along: path, count: items.count, minInterval: Config.hapticMinInterval
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
        currentMotion = nil
        guard let pendingOutcome else { return }
        outcome = pendingOutcome
        self.pendingOutcome = nil
    }
}

/// 惰性で回り始めた角度・時刻と、その動き。
private struct Coasting {
    let from: Double
    let start: TimeInterval
    let coast: FlickCoast.Coast
}
