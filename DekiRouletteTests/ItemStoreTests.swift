import Foundation
import Testing
@testable import DekiRoulette

/// `UserDefaults` の代わりにメモリへ書く保存先。
final class InMemoryStorage: ItemStorage {
    var values: [String: Data] = [:]

    func data(forKey key: String) -> Data? { values[key] }

    func setData(_ data: Data?, forKey key: String) {
        values[key] = data
    }
}

struct ItemStoreTests {
    private func makeStore(
        _ storage: InMemoryStorage = InMemoryStorage(),
        defaults: [String] = ["X", "Y"]
    ) -> ItemStore {
        ItemStore(key: .roulette, storage: storage, defaultLabels: { defaults })
    }

    @Test func 保存した項目はidとラベルごと戻る() {
        let store = makeStore()
        let items = ItemLabel.makeItems(["ラーメン", "カレー", "寿司"])
        store.save(items)
        #expect(store.loadSaved() == items)
        #expect(store.load() == items)
    }

    @Test func 保存データが無ければ初期項目() {
        let store = makeStore()
        #expect(store.loadSaved() == nil)
        #expect(store.load().map(\.label) == ["X", "Y"])
    }

    @Test func 初期項目は読むたびに評価する() {
        var labels = ["X"]
        let store = ItemStore(key: .order, storage: InMemoryStorage(), defaultLabels: { labels })
        #expect(store.load().map(\.label) == ["X"])
        labels = ["Y", "Z"]
        #expect(store.load().map(\.label) == ["Y", "Z"])
    }

    @Test func 空のリストも保存済みとして扱う() {
        let store = makeStore()
        store.save([])
        #expect(store.loadSaved() == [])
        #expect(store.load().isEmpty)
    }

    @Test func 壊れたデータは初期項目に戻す() {
        let storage = InMemoryStorage()
        let store = makeStore(storage)
        storage.values[ItemStore.Key.roulette.rawValue] = Data("not json".utf8)
        #expect(store.loadSaved() == nil)
        #expect(store.load().map(\.label) == ["X", "Y"])
    }

    @Test func 形の違うJSONは初期項目に戻す() {
        let storage = InMemoryStorage()
        let store = makeStore(storage)
        storage.values[ItemStore.Key.roulette.rawValue] = Data(#"{"items":[]}"#.utf8)
        #expect(store.loadSaved() == nil)
        storage.values[ItemStore.Key.roulette.rawValue] = Data(#"[{"label":"A"}]"#.utf8)
        #expect(store.loadSaved() == nil)
    }

    @Test func 消すと初期項目に戻る() {
        let store = makeStore()
        store.save(ItemLabel.makeItems(["A"]))
        store.clear()
        #expect(store.loadSaved() == nil)
        #expect(store.load().map(\.label) == ["X", "Y"])
    }

    @Test func 画面ごとに別のキーへ保存する() {
        let storage = InMemoryStorage()
        let roulette = ItemStore(key: .roulette, storage: storage, defaultLabels: { [] })
        let order = ItemStore(key: .order, storage: storage, defaultLabels: { [] })
        roulette.save(ItemLabel.makeItems(["A"]))
        order.save(ItemLabel.makeItems(["B"]))
        #expect(roulette.load().map(\.label) == ["A"])
        #expect(order.load().map(\.label) == ["B"])
    }

    @Test func 読み込み時にラベルを正規化し空になったものは落とす() throws {
        let json = #"""
        [
          {"id":"00000000-0000-0000-0000-000000000001","label":"  A   B  "},
          {"id":"00000000-0000-0000-0000-000000000002","label":"   "},
          {"id":"00000000-0000-0000-0000-000000000003","label":"\#(String(repeating: "あ", count: 30))"}
        ]
        """#
        let items = try #require(ItemStore.decode(Data(json.utf8)))
        #expect(items.map(\.label) == ["A B", String(repeating: "あ", count: Config.maxLabelLength)])
    }

    @Test func idが重複する項目は最初のものだけ残す() throws {
        let json = #"""
        [
          {"id":"00000000-0000-0000-0000-000000000001","label":"A"},
          {"id":"00000000-0000-0000-0000-000000000001","label":"B"},
          {"id":"00000000-0000-0000-0000-000000000002","label":"C"}
        ]
        """#
        let items = try #require(ItemStore.decode(Data(json.utf8)))
        #expect(items.map(\.label) == ["A", "C"])
    }

    @Test func 上限を超える項目は切り捨てる() throws {
        let stored = (0..<(Config.maxItems + 5)).map { StoredItem(Item(label: "\($0)")) }
        let data = try JSONEncoder().encode(stored)
        let items = try #require(ItemStore.decode(data))
        #expect(items.count == Config.maxItems)
        #expect(items.last?.label == "\(Config.maxItems - 1)")
    }

    @Test func 自動の項目の保存形式はidとラベルだけ() throws {
        let item = Item(label: "A")
        let data = try #require(ItemStore.encode([item]))
        let object = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let entry = try #require(object?.first)
        #expect(Set(entry.keys) == ["id", "label"])
        #expect(entry["id"] as? String == item.id.uuidString)
    }

    @Test func 見た目つきの項目は見た目ごと戻る() {
        let store = makeStore()
        let items = [
            Item(label: "ラーメン"),
            Item(label: "カレー", appearance: .color(.blue)),
            Item(label: "寿司", appearance: .emoji("🍣")),
            Item(label: "家族", appearance: .emoji("👨‍👩‍👧‍👦")),
        ]
        store.save(items)
        #expect(store.load() == items)
        #expect(store.load().map(\.appearance) == [.auto, .color(.blue), .emoji("🍣"), .emoji("👨‍👩‍👧‍👦")])
    }

    @Test func 見た目の無い古い保存データは自動として読む() throws {
        let json = #"""
        [
          {"id":"00000000-0000-0000-0000-000000000001","label":"A"},
          {"id":"00000000-0000-0000-0000-000000000002","label":"B"}
        ]
        """#
        let items = try #require(ItemStore.decode(Data(json.utf8)))
        #expect(items.map(\.label) == ["A", "B"])
        #expect(items.map(\.appearance) == [.auto, .auto])
    }

    @Test func 読めない見た目は項目を残して自動として読む() throws {
        let json = #"""
        [
          {"id":"00000000-0000-0000-0000-000000000001","label":"A","appearance":{"kind":"color","value":"magenta"}},
          {"id":"00000000-0000-0000-0000-000000000002","label":"B","appearance":{"kind":"emoji","value":"あ"}},
          {"id":"00000000-0000-0000-0000-000000000003","label":"C","appearance":{"kind":"emoji","value":"1"}},
          {"id":"00000000-0000-0000-0000-000000000004","label":"D","appearance":{"kind":"pattern","value":"stripe"}},
          {"id":"00000000-0000-0000-0000-000000000005","label":"E","appearance":"blue"},
          {"id":"00000000-0000-0000-0000-000000000006","label":"F","appearance":{"kind":"color"}},
          {"id":"00000000-0000-0000-0000-000000000007","label":"G","appearance":{"kind":"emoji","value":""}},
          {"id":"00000000-0000-0000-0000-000000000008","label":"H","appearance":null},
          {"id":"00000000-0000-0000-0000-000000000009","label":"I","appearance":{"kind":"color","value":"green"}}
        ]
        """#
        let items = try #require(ItemStore.decode(Data(json.utf8)))
        #expect(items.map(\.label) == ["A", "B", "C", "D", "E", "F", "G", "H", "I"])
        #expect(items.dropLast().allSatisfy { $0.appearance == .auto })
        #expect(items.last?.appearance == .color(.green))
    }

    @Test func 保存された絵文字は1文字に整えて読む() throws {
        let json = #"""
        [{"id":"00000000-0000-0000-0000-000000000001","label":"A","appearance":{"kind":"emoji","value":" 🍣🍕"}}]
        """#
        let items = try #require(ItemStore.decode(Data(json.utf8)))
        #expect(items.first?.appearance == .emoji("🍣"))
    }

    @Test func 色は並びの添字ではなく識別子で保存する() throws {
        let items = [Item(label: "A", appearance: .color(.violet)), Item(label: "B", appearance: .emoji("🍣"))]
        let data = try #require(ItemStore.encode(items))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(Set(object[0].keys) == ["id", "label", "appearance"])
        #expect(object[0]["appearance"] as? [String: String] == ["kind": "color", "value": "violet"])
        #expect(object[1]["appearance"] as? [String: String] == ["kind": "emoji", "value": "🍣"])
    }
}
