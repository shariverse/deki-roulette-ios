import Testing
@testable import DekiRoulette

struct SlicePaletteTests {
    private static let maxCount = 24

    private func indices(count: Int, paletteSize: Int) -> [Int] {
        (0..<count).map { SlicePalette.index(at: $0, count: count, paletteSize: paletteSize) }
    }

    @Test(arguments: [10, 12])
    func どの件数でも隣り合うスライスは同じ色にならない(paletteSize: Int) {
        for count in 2...Self.maxCount {
            let colors = indices(count: count, paletteSize: paletteSize)
            for i in 1..<count {
                #expect(colors[i] != colors[i - 1], "count=\(count) i=\(i)")
            }
            if count >= 3 {
                #expect(colors[count - 1] != colors[0], "count=\(count) の継ぎ目")
            }
        }
    }

    @Test(arguments: [10, 12])
    func ずらすのは継ぎ目が重なる件数の末尾だけ(paletteSize: Int) {
        for count in 1...Self.maxCount {
            let colors = indices(count: count, paletteSize: paletteSize)
            for i in 0..<count {
                let shifted = count > 1 && count % paletteSize == 1 && i == count - 1
                if shifted {
                    #expect(colors[i] != i % paletteSize, "count=\(count) i=\(i)")
                } else {
                    #expect(colors[i] == i % paletteSize, "count=\(count) i=\(i)")
                }
            }
        }
    }

    @Test func 十色では11件と21件の末尾をずらす() {
        #expect(indices(count: 11, paletteSize: 10).last == 4)
        #expect(indices(count: 21, paletteSize: 10).last == 4)
        #expect(indices(count: 12, paletteSize: 10).last == 1)
    }

    @Test func 戻り値はパレットの範囲に収まる() {
        for count in 1...Self.maxCount {
            #expect(indices(count: count, paletteSize: 10).allSatisfy { (0..<10).contains($0) })
        }
    }

    @Test func 盤面の塗りと色見本は継ぎ目で同じようにずらす() {
        let shifted = SlicePalette.index(at: 10, count: 11, paletteSize: Theme.sliceColors.count)
        #expect(Theme.sliceColor(at: 10, count: 11) == Theme.sliceColors[shifted])
        #expect(Theme.sliceAccent(at: 10, count: 11) == Theme.sliceAccents[shifted])
        #expect(Theme.sliceColor(at: 10, count: 11) != Theme.sliceColor(at: 0, count: 11))
        #expect(Theme.sliceColor(at: 10, count: 12) == Theme.sliceColor(at: 0, count: 12))
    }

    // MARK: 項目の見た目

    @Test func 色の項目は件数や並びに依らず選んだ色() {
        for color in SliceColor.allCases {
            for count in 1...Self.maxCount {
                for index in 0..<count {
                    let picked = SlicePalette.index(for: .color(color), at: index, count: count, paletteSize: 10)
                    #expect(picked == color.paletteIndex, "\(color) count=\(count) i=\(index)")
                }
            }
        }
    }

    @Test func 自動と絵文字の項目は今の規則() {
        for count in 1...Self.maxCount {
            for index in 0..<count {
                let rule = SlicePalette.index(at: index, count: count, paletteSize: 10)
                #expect(SlicePalette.index(for: .auto, at: index, count: count, paletteSize: 10) == rule)
                #expect(SlicePalette.index(for: .emoji("🍣"), at: index, count: count, paletteSize: 10) == rule)
            }
        }
    }

    @Test func 継ぎ目の末尾でも色の項目は選んだ色のまま() {
        #expect(SlicePalette.index(for: .color(.red), at: 10, count: 11, paletteSize: 10) == SliceColor.red.paletteIndex)
        #expect(SlicePalette.index(for: .auto, at: 10, count: 11, paletteSize: 10) == 4)
    }

    @Test func 選べる色の数は盤面のパレットと同じ() {
        #expect(SliceColor.allCases.count == Theme.sliceColors.count)
        #expect(SliceColor.allCases.count == Theme.sliceAccents.count)
    }

    @Test func 項目リストから引く色は色の項目だけ選んだ色になる() {
        let items = [
            Item(label: "A"),
            Item(label: "B", appearance: .color(.purple)),
            Item(label: "C", appearance: .emoji("🍣")),
            Item(label: "D"),
        ]
        for index in items.indices where index != 1 {
            #expect(Theme.sliceColor(in: items, at: index) == Theme.sliceColor(at: index, count: items.count), "\(index)")
            #expect(Theme.sliceAccent(in: items, at: index) == Theme.sliceAccent(at: index, count: items.count), "\(index)")
        }
        #expect(Theme.sliceColor(in: items, at: 1) == Theme.sliceColors[SliceColor.purple.paletteIndex])
        #expect(Theme.sliceAccent(in: items, at: 1) == Theme.sliceAccents[SliceColor.purple.paletteIndex])
    }

    @Test func 項目リストから引く色は件数で継ぎ目をずらす() {
        let items = ItemLabel.makeItems((0..<11).map { "\($0)" })
        #expect(Theme.sliceColor(in: items, at: 10) == Theme.sliceColor(at: 10, count: 11))
        #expect(Theme.sliceColor(in: items, at: 10) != Theme.sliceColor(in: items, at: 0))
    }
}
