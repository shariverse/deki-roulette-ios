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
