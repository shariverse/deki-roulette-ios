import SwiftUI

/// Dynamic Type（文字サイズ）に応じて切り替えるレイアウト値。
/// しきい値は `DynamicTypeSize.accessibility1`（`isAccessibilitySize`）で、それ以上を「アクセシビリティサイズ」と呼ぶ。
/// View は `@Environment(\.dynamicTypeSize)` の値をそのまま渡す。
enum TypeLayout {
    /// 項目リストの行・順番の結果行・「結果を共有」のボタンに入れる最大行数。
    /// 通常は 1 行に収めて省略するが、アクセシビリティサイズでは短い名前でも省略されてしまうため 2 行まで許す。
    static func labelLineLimit(for size: DynamicTypeSize) -> Int {
        size.isAccessibilitySize ? 2 : 1
    }

    /// 両画面の共有ボタンの領域を内容に合わせて伸ばすか。
    /// 通常は高さを固定して、結果の有無で下の要素の位置が動かないようにする。
    /// アクセシビリティサイズでは固定のままだと文字が枠からはみ出るため、最小高さだけ残して伸ばす。
    static func growsFixedAreas(for size: DynamicTypeSize) -> Bool {
        size.isAccessibilitySize
    }
}
