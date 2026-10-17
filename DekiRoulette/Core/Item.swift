import Foundation

struct Item: Identifiable, Hashable, Sendable {
    let id: UUID
    let label: String
    /// 色・絵文字の見た目。未指定は自動（並び順と件数から色を引く）。
    let appearance: ItemAppearance

    init(id: UUID = UUID(), label: String, appearance: ItemAppearance = .auto) {
        self.id = id
        self.label = label
        self.appearance = appearance
    }

    /// 見た目だけを差し替えた項目。`id` とラベルは保つ。
    func with(appearance: ItemAppearance) -> Item {
        Item(id: id, label: label, appearance: appearance)
    }
}

extension Array where Element == Item {
    /// `id` の項目の見た目を差し替えた配列。該当が無いときはそのまま返す。並びと他の項目は変えない。
    func settingAppearance(_ appearance: ItemAppearance, for id: UUID) -> [Item] {
        map { $0.id == id ? $0.with(appearance: appearance) : $0 }
    }
}

/// 削除した項目と、削除前にあった位置。「元に戻す」で同じ位置に差し戻すために使う。
struct RemovedItem: Hashable, Sendable {
    let item: Item
    let index: Int
}

/// リストの行に出す印。ルーレットは当たり、順番決めは先頭・末尾を指す。
enum Mark: Sendable {
    case target
    case first
    case last
}

typealias Marks = [UUID: Mark]
