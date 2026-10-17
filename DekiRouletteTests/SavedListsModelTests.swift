import Foundation
import Testing
@testable import DekiRoulette

@MainActor
struct SavedListsModelTests {
    private let items = ItemLabel.makeItems(["A", "B", "C"])

    @Test func 保存するとすぐ書き込まれる() {
        let storage = InMemoryStorage()
        let model = SavedListsModel(store: SavedListStore(storage: storage))
        #expect(model.save(name: "ランチ", items: items))
        #expect(model.lists.map(\.name) == ["ランチ"])
        #expect(SavedListStore(storage: storage).load() == model.lists)
    }

    @Test func 次の起動で保存したリストから始まる() {
        let storage = InMemoryStorage()
        let first = SavedListsModel(store: SavedListStore(storage: storage))
        first.save(name: "ランチ", items: items)
        let second = SavedListsModel(store: SavedListStore(storage: storage))
        #expect(second.lists == first.lists)
    }

    @Test func 空の名前や上限では保存しない() {
        let model = SavedListsModel(lists: [])
        #expect(!model.save(name: "  ", items: items))
        for i in 0..<Config.maxSavedLists { model.save(name: "\(i)", items: items) }
        #expect(model.atCapacity)
        #expect(!model.save(name: "overflow", items: items))
        #expect(model.lists.count == Config.maxSavedLists)
    }

    @Test func 名前の変更と削除が保存に反映される() throws {
        let storage = InMemoryStorage()
        let model = SavedListsModel(store: SavedListStore(storage: storage))
        model.save(name: "A", items: items)
        model.save(name: "B", items: items)
        let a = try #require(model.lists.first)
        #expect(model.rename(id: a.id, to: "A2"))
        #expect(model.list(id: a.id)?.name == "A2")
        model.delete(id: a.id)
        #expect(model.lists.map(\.name) == ["B"])
        #expect(SavedListStore(storage: storage).load().map(\.name) == ["B"])
    }

    @Test func 保存と名前の変更と次の起動で見た目が保たれる() throws {
        let styled = [Item(label: "A", appearance: .color(.cyan)), Item(label: "B", appearance: .emoji("🍕")), Item(label: "C")]
        let storage = InMemoryStorage()
        let model = SavedListsModel(store: SavedListStore(storage: storage))
        model.save(name: "ランチ", items: styled)
        let saved = try #require(model.lists.first)
        #expect(model.rename(id: saved.id, to: "夕食"))
        #expect(model.list(id: saved.id)?.items == styled)
        let next = SavedListsModel(store: SavedListStore(storage: storage))
        #expect(next.list(id: saved.id)?.items == styled)

        let roulette = RouletteModel(items: ItemLabel.makeItems(["X"]))
        roulette.replaceItems(next.lists[0].items)
        #expect(roulette.items.map(\.appearance) == styled.map(\.appearance))
    }

    @Test func 読み込んだ項目で置き換えると指定と結果が消える() {
        let saved = SavedListsModel(lists: [SavedList(name: "ランチ", items: items)])
        let roulette = RouletteModel(items: ItemLabel.makeItems(["X", "Y"]))
        roulette.toggleTarget(id: roulette.items[0].id)
        roulette.rotation = roulette.beginSpin(reducedMotion: false)!
        roulette.finishSpin()
        roulette.replaceItems(saved.lists[0].items)
        #expect(roulette.items == items)
        #expect(roulette.targetId == nil)
        #expect(roulette.result == nil)

        let order = OrderModel(items: ItemLabel.makeItems(["X", "Y"]))
        order.cycleMark(id: order.items[0].id)
        order.shuffleItems(reducedMotion: true)
        order.replaceItems(saved.lists[0].items)
        #expect(order.items == items)
        #expect(order.marks.isEmpty)
        #expect(order.ordered == nil)
    }
}
