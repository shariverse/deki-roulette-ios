import Foundation

/// 名前を付けて保存した項目リスト。ルーレットと順番決めで共通に使う。
/// 項目の `id`・`label`・見た目だけを持ち、当たり・先頭・末尾の指定は含めない。
struct SavedList: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var items: [Item]

    init(id: UUID = UUID(), name: String, items: [Item]) {
        self.id = id
        self.name = name
        self.items = items
    }
}

enum SavedListName {
    /// 項目のラベルと同じ規則で空白を潰し、リスト名の上限で切る。
    static func normalize(_ raw: String) -> String {
        let collapsed = raw
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        return String(collapsed.prefix(Config.maxSavedListNameLength))
    }
}

extension Array where Element == SavedList {
    var atCapacity: Bool { count >= Config.maxSavedLists }

    /// 末尾に追加した配列を返す。名前が空、または上限に達しているときは nil。
    func adding(name rawName: String, items: [Item]) -> [SavedList]? {
        let name = SavedListName.normalize(rawName)
        guard !name.isEmpty, !atCapacity else { return nil }
        return self + [SavedList(name: name, items: items)]
    }

    /// 名前を付け替えた配列を返す。名前が空、または該当が無いときは nil。
    func renaming(id: UUID, to rawName: String) -> [SavedList]? {
        let name = SavedListName.normalize(rawName)
        guard !name.isEmpty, let index = firstIndex(where: { $0.id == id }) else { return nil }
        var next = self
        next[index].name = name
        return next
    }

    func deleting(id: UUID) -> [SavedList] {
        filter { $0.id != id }
    }
}

/// 保存する形。`StoredItem` と同じく `Codable` は保存用の型にだけ付ける。
struct StoredSavedList: Codable {
    let id: UUID
    let name: String
    let items: [StoredItem]

    init(_ list: SavedList) {
        id = list.id
        name = list.name
        items = list.items.map(StoredItem.init)
    }
}

/// 保存したリストの読み書き。保存先は画面に依らず 1 つ。
struct SavedListStore {
    static let key = "savedLists"

    let storage: any ItemStorage

    init(storage: any ItemStorage = UserDefaults.standard) {
        self.storage = storage
    }

    /// 保存済みのリスト。無い・読めないときは空。
    func load() -> [SavedList] {
        guard let data = storage.data(forKey: Self.key) else { return [] }
        return Self.decode(data) ?? []
    }

    func save(_ lists: [SavedList]) {
        storage.setData(Self.encode(lists), forKey: Self.key)
    }

    // MARK: コーデック

    static func encode(_ lists: [SavedList]) -> Data? {
        try? JSONEncoder().encode(lists.map(StoredSavedList.init))
    }

    /// JSON として読めないときは nil。名前が空になるリスト・`id` が重複するリストは落とし、上限で切る。
    /// 項目は `ItemStore` と同じ規則で整える。
    static func decode(_ data: Data) -> [SavedList]? {
        guard let stored = try? JSONDecoder().decode([StoredSavedList].self, from: data) else { return nil }
        var seen = Set<UUID>()
        var lists: [SavedList] = []
        for entry in stored {
            let name = SavedListName.normalize(entry.name)
            guard !name.isEmpty, seen.insert(entry.id).inserted else { continue }
            lists.append(SavedList(id: entry.id, name: name, items: ItemStore.sanitize(entry.items)))
            if lists.count == Config.maxSavedLists { break }
        }
        return lists
    }
}
