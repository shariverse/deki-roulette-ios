import Foundation

/// 直近の 1 件だけを覚えるキャッシュ。共有画像を結果ごとに 1 回だけ描くために使う。
/// 同じ鍵で呼ばれている間は作り直さず、鍵が変わったら作り直して前の値を捨てる。作れなかった（nil）ことも覚えて、
/// 同じ鍵で重い処理を繰り返さない。1 件しか持たないので、結果が変わるたびに古い画像は手放される。
final class LatestCache<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?
    /// `make` を呼んだ回数。テストと計測のために数える。
    private(set) var makeCount = 0

    init() {}

    /// `key` の値。前回と同じ鍵なら覚えている値を返し、違えば `make` で作り直す。
    func value(for key: Key, make: () -> Value?) -> Value? {
        if let stored = self.key, stored == key {
            return value
        }
        makeCount += 1
        value = make()
        self.key = key
        return value
    }

    /// 覚えている値を捨てる。次に呼ばれたら鍵に依らず作り直す。
    func clear() {
        key = nil
        value = nil
    }
}
