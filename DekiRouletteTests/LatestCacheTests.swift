import Testing
@testable import DekiRoulette

struct LatestCacheTests {
    @Test func 同じ鍵では作り直さない() {
        let cache = LatestCache<String, Int>()
        #expect(cache.value(for: "a") { 1 } == 1)
        #expect(cache.value(for: "a") { 2 } == 1)
        #expect(cache.makeCount == 1)
    }

    @Test func 鍵が変わると作り直して前の値は捨てる() {
        let cache = LatestCache<String, Int>()
        #expect(cache.value(for: "a") { 1 } == 1)
        #expect(cache.value(for: "b") { 2 } == 2)
        // 前の鍵に戻っても 1 件しか持たないので作り直す
        #expect(cache.value(for: "a") { 3 } == 3)
        #expect(cache.makeCount == 3)
    }

    @Test func 作れなかったことも覚えて繰り返さない() {
        let cache = LatestCache<Int, String>()
        #expect(cache.value(for: 1) { nil } == nil)
        #expect(cache.value(for: 1) { "x" } == nil)
        #expect(cache.makeCount == 1)
    }

    @Test func 捨てると同じ鍵でも作り直す() {
        let cache = LatestCache<String, Int>()
        #expect(cache.value(for: "a") { 1 } == 1)
        cache.clear()
        #expect(cache.value(for: "a") { 2 } == 2)
        #expect(cache.makeCount == 2)
    }
}
