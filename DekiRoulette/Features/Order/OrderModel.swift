import Foundation
import Observation

/// 項目・先頭末尾の指定・並べ替え結果のステートと演出時間の計算。Web 版 `useOrder` に対応する。
@MainActor
@Observable
final class OrderModel {
    private(set) var items: [Item]
    private(set) var firstId: UUID?
    private(set) var lastId: UUID?
    private(set) var ordered: [Item]?
    private(set) var revealing = false

    /// 結果ごとに変わる識別子。結果の行を作り直して演出をやり直すために使う。
    private(set) var resultId = UUID()

    /// 結果の行が現れた回数。1 件ごとに触覚を鳴らすトリガで、リセットしない。
    private(set) var revealTick = 0

    private var revealTask: Task<Void, Never>?
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

    var canShuffle: Bool { !revealing && items.count >= Config.minItems }
    var atCapacity: Bool { items.count >= Config.maxItems }

    var marks: Marks {
        var next: Marks = [:]
        if let firstId { next[firstId] = .first }
        if let lastId { next[lastId] = .last }
        return next
    }

    func addItem(_ raw: String) {
        let label = ItemLabel.normalize(raw)
        guard !label.isEmpty, !atCapacity else { return }
        items.append(Item(label: label))
        ordered = nil
        persist()
    }

    /// 複数のラベルをまとめて追加する。上限に収まらない分は切り捨て、追加できた件数を返す。
    @discardableResult
    func addItems(_ raws: [String]) -> Int {
        let labels = raws.map(ItemLabel.normalize).filter { !$0.isEmpty }
        let accepted = Array(labels.prefix(max(0, Config.maxItems - items.count)))
        guard !accepted.isEmpty else { return 0 }
        items.append(contentsOf: ItemLabel.makeItems(accepted))
        ordered = nil
        persist()
        return accepted.count
    }

    /// 項目を削除し、削除した項目と元の位置を返す。「元に戻す」（`restore`）に使う。
    @discardableResult
    func removeItem(id: UUID) -> RemovedItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items.remove(at: index)
        if firstId == id { firstId = nil }
        if lastId == id { lastId = nil }
        ordered = nil
        persist()
        return RemovedItem(item: item, index: index)
    }

    /// 項目をすべて削除する。指定と結果も消える。
    func removeAll() {
        items.removeAll()
        firstId = nil
        lastId = nil
        ordered = nil
        persist()
    }

    /// 削除した項目を元の位置に戻す。指定は復元しない。
    /// 同じ項目がすでにあるとき、上限に達しているときは何もしない。
    func restore(_ item: Item, at index: Int) {
        guard !items.contains(where: { $0.id == item.id }), !atCapacity else { return }
        items.insert(item, at: min(index, items.count))
        ordered = nil
        persist()
    }

    /// 項目を丸ごと入れ替える。指定と結果は前のリストのものなので捨てる。
    func replaceItems(_ next: [Item]) {
        items = next
        firstId = nil
        lastId = nil
        ordered = nil
        persist()
    }

    /// 項目の見た目（色・絵文字）を変える。見た目だけなので、指定と結果の並びはそのまま残す（結果の行も同じ見た目にする）。
    /// 演出中は変えない。
    func setAppearance(_ appearance: ItemAppearance, for id: UUID) {
        guard !revealing, items.contains(where: { $0.id == id }) else { return }
        items = items.settingAppearance(appearance, for: id)
        ordered = ordered?.settingAppearance(appearance, for: id)
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

    /// 長押しのたびに 先頭 → 末尾 → 解除 と回す。
    /// 先頭と末尾はそれぞれ 1 項目までなので、付け替えると前の指定は落ちる。
    func cycleMark(id: UUID) {
        if firstId == id {
            firstId = nil
            lastId = id
        } else if lastId == id {
            lastId = nil
        } else {
            firstId = id
        }
        ordered = nil
    }

    func shuffleItems(reducedMotion: Bool) {
        guard canShuffle else { return }
        ordered = Shuffler.arrange(items, firstId: firstId, lastId: lastId)
        resultId = UUID()
        revealing = true

        revealTask?.cancel()
        let wait = RevealTiming.duration(count: items.count, reducedMotion: reducedMotion)
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.revealing = false
        }

        // 行が現れる時刻は View のアニメーション遅延と同じ式で決まるので、同じ時刻に刻む
        tickTask?.cancel()
        let ticks = HapticSchedule.revealTicks(count: items.count, reducedMotion: reducedMotion)
        tickTask = TickScheduler.run(at: ticks) { [weak self] in self?.revealTick += 1 }
    }
}
