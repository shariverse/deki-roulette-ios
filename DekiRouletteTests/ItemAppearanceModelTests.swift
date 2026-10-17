import Foundation
import Testing
@testable import DekiRoulette

/// 両画面のモデルで項目の見た目を変える操作と、その保存。
@MainActor
struct ItemAppearanceModelTests {
    private func store(_ storage: InMemoryStorage, _ key: ItemStore.Key) -> ItemStore {
        ItemStore(key: key, storage: storage, defaultLabels: { ["A", "B", "C"] })
    }

    @Test func 配列の見た目の差し替えはidの項目だけ() {
        let items = ItemLabel.makeItems(["A", "B", "C"])
        let next = items.settingAppearance(.color(.blue), for: items[1].id)
        #expect(next.map(\.id) == items.map(\.id))
        #expect(next.map(\.label) == items.map(\.label))
        #expect(next.map(\.appearance) == [.auto, .color(.blue), .auto])
        #expect(items.settingAppearance(.color(.blue), for: UUID()) == items)
    }

    // MARK: ルーレット

    @Test func ルーレットの見た目を変えると保存され次の起動に残る() {
        let storage = InMemoryStorage()
        let model = RouletteModel(store: store(storage, .roulette))
        let id = model.items[1].id
        model.setAppearance(.emoji("🍣"), for: id)
        #expect(model.items[1].appearance == .emoji("🍣"))
        #expect(model.items[1].id == id)
        #expect(RouletteModel(store: store(storage, .roulette)).items.map(\.appearance) == [.auto, .emoji("🍣"), .auto])
        model.setAppearance(.auto, for: id)
        #expect(RouletteModel(store: store(storage, .roulette)).items.allSatisfy { $0.appearance == .auto })
    }

    @Test func ルーレットの見た目を変えても指定と結果は残る() {
        let model = RouletteModel(items: ItemLabel.makeItems(["A", "B", "C"]))
        model.toggleTarget(id: model.items[0].id)
        model.rotation = model.beginSpin(reducedMotion: false)!
        model.finishSpin()
        let outcome = model.outcome
        #expect(outcome != nil)
        model.setAppearance(.color(.pink), for: model.items[0].id)
        #expect(model.targetId == model.items[0].id)
        #expect(model.outcome == outcome)
    }

    @Test func スピン中は見た目を変えない() {
        let model = RouletteModel(items: ItemLabel.makeItems(["A", "B"]))
        model.rotation = model.beginSpin(reducedMotion: false)!
        #expect(model.spinning)
        model.setAppearance(.color(.red), for: model.items[0].id)
        #expect(model.items[0].appearance == .auto)
        model.finishSpin()
    }

    @Test func ルーレットの追加削除復元のあとも見た目は保存に残る() throws {
        let storage = InMemoryStorage()
        let model = RouletteModel(store: store(storage, .roulette))
        model.setAppearance(.color(.green), for: model.items[0].id)
        model.addItems(["D"])
        let removed = try #require(model.removeItem(id: model.items[0].id))
        model.restore(removed.item, at: removed.index)
        let next = RouletteModel(store: store(storage, .roulette))
        #expect(next.items.map(\.label) == ["A", "B", "C", "D"])
        #expect(next.items[0].appearance == .color(.green))
    }

    // MARK: 順番決め

    @Test func 順番決めの見た目を変えると保存され次の起動に残る() {
        let storage = InMemoryStorage()
        let model = OrderModel(store: store(storage, .order))
        model.setAppearance(.color(.violet), for: model.items[2].id)
        #expect(OrderModel(store: store(storage, .order)).items.map(\.appearance) == [.auto, .auto, .color(.violet)])
    }

    @Test func 順番決めの見た目を変えると結果の行も同じ見た目で指定は残る() async throws {
        let model = OrderModel(items: ItemLabel.makeItems(["A", "B", "C"]))
        let first = model.items[1].id
        model.cycleMark(id: first)
        model.shuffleItems(reducedMotion: true)
        // 演出中は変えない
        model.setAppearance(.color(.red), for: first)
        #expect(model.items[1].appearance == .auto)
        try await Task.sleep(for: .seconds(Config.reducedMotionRevealDuration + 0.3))
        #expect(!model.revealing)
        let order = model.ordered?.map(\.id)
        model.setAppearance(.emoji("🍕"), for: first)
        #expect(model.items[1].appearance == .emoji("🍕"))
        #expect(model.ordered?.map(\.id) == order)
        #expect(model.ordered?.first { $0.id == first }?.appearance == .emoji("🍕"))
        #expect(model.firstId == first)
    }

    @Test func 順番決めで読み込んだ項目の見た目は保たれる() {
        let styled = [Item(label: "A", appearance: .color(.cyan)), Item(label: "B", appearance: .emoji("🍣"))]
        let model = OrderModel(items: ItemLabel.makeItems(["X"]))
        model.replaceItems(styled)
        #expect(model.items == styled)
    }
}
