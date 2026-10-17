import Foundation

/// 項目ごとの見た目。自動・色・絵文字のどれか 1 つで、併用はしない。
///
/// 自動は今までどおり並び順と件数から色を引く（`SlicePalette`）。絵文字の項目も色は自動で、ラベルの前に絵文字を出す。
/// 見た目だけの値で、抽選・指定・止まる位置・音・触覚には使わない。
enum ItemAppearance: Hashable, Sendable {
    case auto
    case color(SliceColor)
    /// `EmojiInput.normalize` を通した 1 書記素。
    case emoji(Character)
}

/// 項目に選べる 10 色。盤面のパレット（`Theme.sliceColors` / `sliceAccents`）と同じ並びで、同じ添字の色を指す。
///
/// 保存には並びの添字ではなく `rawValue` を使う。パレットの並びを変えても、保存済みの項目の色が変わらないようにするため。
/// `rawValue` はリリースしたら変えない。
enum SliceColor: String, CaseIterable, Hashable, Sendable {
    case red
    case orange
    case yellow
    case lime
    case green
    case cyan
    case blue
    case violet
    case purple
    case pink

    /// パレット（`Theme.sliceColors` / `sliceAccents`）の添字。
    var paletteIndex: Int {
        Self.allCases.firstIndex(of: self)!
    }
}
