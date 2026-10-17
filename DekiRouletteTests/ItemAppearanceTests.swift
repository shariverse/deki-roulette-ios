import Foundation
import Testing
@testable import DekiRoulette

struct ItemAppearanceTests {
    @Test
    func 見た目を指定しない項目は自動() {
        #expect(Item(label: "A").appearance == .auto)
        #expect(Item(id: UUID(), label: "A").appearance == .auto)
    }

    @Test
    func 見た目を指定して作れる() {
        #expect(Item(label: "A", appearance: .color(.blue)).appearance == .color(.blue))
        #expect(Item(label: "A", appearance: .emoji("🍣")).appearance == .emoji("🍣"))
    }

    @Test
    func 色はパレットと同じ並びの10色() {
        #expect(SliceColor.allCases.count == 10)
        #expect(SliceColor.allCases.map(\.paletteIndex) == Array(0..<10))
        #expect(SliceColor.red.paletteIndex == 0)
        #expect(SliceColor.pink.paletteIndex == 9)
    }

    @Test
    func 色の識別子は重ならない() {
        let rawValues = SliceColor.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
        #expect(SliceColor(rawValue: "blue") == .blue)
        #expect(SliceColor(rawValue: "unknown") == nil)
    }
}
