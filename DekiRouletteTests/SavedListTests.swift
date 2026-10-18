import Foundation
import Testing
@testable import DekiRoulette

struct SavedListTests {
    private let items = ItemLabel.makeItems(["ラーメン", "カレー", "寿司"])

    // MARK: 名前

    @Test func 名前は空白を潰して上限で切る() {
        #expect(SavedListName.normalize("  ランチ   候補 \n") == "ランチ 候補")
        let long = String(repeating: "あ", count: Config.maxSavedListNameLength + 5)
        #expect(SavedListName.normalize(long).count == Config.maxSavedListNameLength)
    }

    // MARK: 追加・変更・削除

    @Test func 追加は末尾に足す() throws {
        let lists = try #require([SavedList]().adding(name: "ランチ", items: items))
        #expect(lists.count == 1)
        #expect(lists[0].name == "ランチ")
        #expect(lists[0].items == items)
    }

    @Test func 空の名前では追加しない() {
        #expect([SavedList]().adding(name: "   ", items: items) == nil)
    }

    @Test func 上限に達していたら追加しない() {
        let full = (0..<Config.maxSavedLists).map { SavedList(name: "\($0)", items: items) }
        #expect(full.atCapacity)
        #expect(full.adding(name: "もう 1 つ", items: items) == nil)
    }

    @Test func 名前を変更できる() throws {
        let original = [SavedList(name: "ランチ", items: items), SavedList(name: "チーム", items: [])]
        let renamed = try #require(original.renaming(id: original[0].id, to: " 夕飯 "))
        #expect(renamed.map(\.name) == ["夕飯", "チーム"])
        #expect(renamed[0].id == original[0].id)
        #expect(renamed[0].items == items)
    }

    @Test func 空の名前や無いidには変更しない() {
        let original = [SavedList(name: "ランチ", items: items)]
        #expect(original.renaming(id: original[0].id, to: "") == nil)
        #expect(original.renaming(id: UUID(), to: "夕飯") == nil)
    }

    @Test func 削除はidで選ぶ() {
        let original = [SavedList(name: "A", items: items), SavedList(name: "B", items: items)]
        let deleted = original.deleting(id: original[0].id)
        #expect(deleted.map(\.name) == ["B"])
        #expect(original.deleting(id: UUID()) == original)
    }

    // MARK: 保存と復元

    @Test func 保存したリストは名前と項目ごと戻る() {
        let store = SavedListStore(storage: InMemoryStorage())
        let lists = [SavedList(name: "ランチ", items: items), SavedList(name: "チーム", items: [])]
        store.save(lists)
        #expect(store.load() == lists)
    }

    @Test func 保存データが無ければ空() {
        #expect(SavedListStore(storage: InMemoryStorage()).load().isEmpty)
    }

    @Test func 壊れたデータは空として扱う() {
        let storage = InMemoryStorage()
        storage.values[SavedListStore.key] = Data("broken".utf8)
        #expect(SavedListStore(storage: storage).load().isEmpty)
        #expect(SavedListStore.decode(Data("broken".utf8)) == nil)
    }

    @Test func 読み込み時に名前と項目を整える() throws {
        let json = #"""
        [
          {"id":"00000000-0000-0000-0000-000000000001","name":"  ランチ  ","items":[
            {"id":"00000000-0000-0000-0000-000000000011","label":" A  B "},
            {"id":"00000000-0000-0000-0000-000000000012","label":"   "}
          ]},
          {"id":"00000000-0000-0000-0000-000000000002","name":"   ","items":[]},
          {"id":"00000000-0000-0000-0000-000000000001","name":"重複","items":[]}
        ]
        """#
        let lists = try #require(SavedListStore.decode(Data(json.utf8)))
        #expect(lists.count == 1)
        #expect(lists[0].name == "ランチ")
        #expect(lists[0].items.map(\.label) == ["A B"])
    }

    @Test func 上限を超えるリストは切り捨てる() throws {
        let many = (0..<(Config.maxSavedLists + 3)).map { SavedList(name: "\($0)", items: []) }
        let data = try #require(SavedListStore.encode(many))
        let lists = try #require(SavedListStore.decode(data))
        #expect(lists.count == Config.maxSavedLists)
    }

    @Test func 保存形式に指定は含まれない() throws {
        let data = try #require(SavedListStore.encode([SavedList(name: "A", items: items)]))
        let object = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let entry = try #require(object?.first)
        #expect(Set(entry.keys) == ["id", "name", "items"])
        let first = try #require((entry["items"] as? [[String: Any]])?.first)
        #expect(Set(first.keys) == ["id", "label"])
    }

    @Test func 保存したリストは項目の見た目ごと戻る() throws {
        let items = [
            Item(label: "A", appearance: .color(.pink)),
            Item(label: "B", appearance: .emoji("🇯🇵")),
            Item(label: "C"),
        ]
        let data = try #require(SavedListStore.encode([SavedList(name: "ランチ", items: items)]))
        let lists = try #require(SavedListStore.decode(data))
        #expect(lists.first?.items == items)
    }

    @Test func 見た目の無い古い保存データの項目は自動として読む() throws {
        let json = #"""
        [{"id":"00000000-0000-0000-0000-000000000010","name":"ランチ",
          "items":[{"id":"00000000-0000-0000-0000-000000000001","label":"A"}]}]
        """#
        let lists = try #require(SavedListStore.decode(Data(json.utf8)))
        #expect(lists.first?.items.map(\.appearance) == [.auto])
    }
}
