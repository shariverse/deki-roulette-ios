import Foundation

/// 型を消した乱数生成器。モデルが乱数の取得元を持ち、テストで決まった列（`SeededGenerator`）に差し替えるために使う。
struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    init(_ base: some RandomNumberGenerator) {
        self.base = base
    }

    mutating func next() -> UInt64 {
        base.next()
    }
}
