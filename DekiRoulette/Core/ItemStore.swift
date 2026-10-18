import Foundation

/// 項目リストの保存先。`UserDefaults` を直接触らず、テストではメモリ実装を差し込む。
protocol ItemStorage: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
}

extension UserDefaults: ItemStorage {
    func setData(_ data: Data?, forKey key: String) {
        set(data, forKey: key)
    }
}

/// 保存する項目の形。`Item` そのものを `Codable` にすると保存形式が実装の都合に引きずられるため分ける。
struct StoredItem: Codable, Equatable {
    let id: UUID
    let label: String
    /// 見た目。自動のときは書かない（見た目が入る前の保存データと同じ形になる）。
    let appearance: StoredAppearance?

    init(_ item: Item) {
        id = item.id
        label = item.label
        appearance = StoredAppearance(item.appearance)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        // 見た目が読めなくても項目は捨てず、自動として読む。
        appearance = (try? container.decodeIfPresent(StoredAppearance.self, forKey: .appearance)) ?? nil
    }
}

/// 保存する見た目の形。`{"kind": "color", "value": "blue"}` / `{"kind": "emoji", "value": "🍣"}`。
/// 色は並びの添字ではなく `SliceColor.rawValue` で持つ（パレットの並びを変えても保存済みの色が変わらないように）。
struct StoredAppearance: Codable, Equatable {
    let kind: String
    let value: String

    static let colorKind = "color"
    static let emojiKind = "emoji"

    init(kind: String, value: String) {
        self.kind = kind
        self.value = value
    }

    /// 自動のときは nil（保存しない）。
    init?(_ appearance: ItemAppearance) {
        switch appearance {
        case .auto:
            return nil
        case .color(let color):
            self.init(kind: Self.colorKind, value: color.rawValue)
        case .emoji(let emoji):
            self.init(kind: Self.emojiKind, value: String(emoji))
        }
    }

    /// 読み込んだ値を見た目に戻す。知らない種類・範囲外の色・絵文字でない文字列は自動として読む。
    var appearance: ItemAppearance {
        switch kind {
        case Self.colorKind:
            SliceColor(rawValue: value).map(ItemAppearance.color) ?? .auto
        case Self.emojiKind:
            EmojiInput.normalize(value).map(ItemAppearance.emoji) ?? .auto
        default:
            .auto
        }
    }
}

/// 画面ごとの項目リストの保存と復元。保存するのは `id`・`label` と見た目（自動以外のとき）だけで、
/// 当たり・先頭・末尾の指定は含めない（前回の仕込みが次の起動に残らないようにする）。
struct ItemStore {
    /// 保存キー。ルーレットと順番決めは別のリストを持つ。
    enum Key: String {
        case roulette = "items.roulette"
        case order = "items.order"
    }

    let key: Key
    let storage: any ItemStorage
    /// 保存データが無い・壊れているときに使う初期項目。言語が変わっても追従するよう、使う時点で読む。
    let defaultLabels: () -> [String]

    init(key: Key, storage: any ItemStorage = UserDefaults.standard, defaultLabels: @escaping () -> [String]) {
        self.key = key
        self.storage = storage
        self.defaultLabels = defaultLabels
    }

    var defaultItems: [Item] { ItemLabel.makeItems(defaultLabels()) }

    /// 保存済みの項目。無い・読めないときは初期項目。
    func load() -> [Item] {
        loadSaved() ?? defaultItems
    }

    /// 保存済みの項目。無い・読めないときは nil。
    func loadSaved() -> [Item]? {
        guard let data = storage.data(forKey: key.rawValue) else { return nil }
        return Self.decode(data)
    }

    func save(_ items: [Item]) {
        storage.setData(Self.encode(items), forKey: key.rawValue)
    }

    /// 保存データを消す。次の起動からは初期項目（そのときの言語）に戻る。
    func clear() {
        storage.setData(nil, forKey: key.rawValue)
    }

    // MARK: コーデック

    static func encode(_ items: [Item]) -> Data? {
        try? JSONEncoder().encode(items.map(StoredItem.init))
    }

    /// JSON として読めないときは nil。読めた項目は `sanitize` で整える。
    static func decode(_ data: Data) -> [Item]? {
        guard let stored = try? JSONDecoder().decode([StoredItem].self, from: data) else { return nil }
        return sanitize(stored)
    }

    /// 読み込んだ項目を追加時と同じ正規化に通し、空になったもの・`id` が重複するものは落とし、上限で切る。
    static func sanitize(_ stored: [StoredItem]) -> [Item] {
        var seen = Set<UUID>()
        var items: [Item] = []
        for entry in stored {
            let label = ItemLabel.normalize(entry.label)
            guard !label.isEmpty, seen.insert(entry.id).inserted else { continue }
            items.append(Item(id: entry.id, label: label, appearance: entry.appearance?.appearance ?? .auto))
            if items.count == Config.maxItems { break }
        }
        return items
    }
}
