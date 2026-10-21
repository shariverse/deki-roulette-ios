import SwiftUI
import Testing
@testable import DekiRoulette

struct TypeLayoutTests {
    @Test func 標準サイズではラベルは1行() {
        #expect(TypeLayout.labelLineLimit(for: .xSmall) == 1)
        #expect(TypeLayout.labelLineLimit(for: .large) == 1)
        // 標準サイズの最大でもまだ 1 行
        #expect(TypeLayout.labelLineLimit(for: .xxxLarge) == 1)
    }

    @Test func アクセシビリティサイズではラベルは2行() {
        // しきい値は accessibility1
        #expect(TypeLayout.labelLineLimit(for: .accessibility1) == 2)
        #expect(TypeLayout.labelLineLimit(for: .accessibility5) == 2)
    }

    @Test func 固定高さを外すのはアクセシビリティサイズだけ() {
        #expect(!TypeLayout.growsFixedAreas(for: .large))
        #expect(!TypeLayout.growsFixedAreas(for: .xxxLarge))
        #expect(TypeLayout.growsFixedAreas(for: .accessibility1))
        #expect(TypeLayout.growsFixedAreas(for: .accessibility5))
    }

    @Test func 結果の下の行はタップ領域44pt以上() {
        // 「結果を共有」の高さ。開始ボタンより低くしても、押せる大きさの下限は割らない
        #expect(Theme.Layout.resultActionsHeight >= 44)
    }
}
