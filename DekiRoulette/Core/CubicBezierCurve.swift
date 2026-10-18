import Foundation

/// CSS の `cubic-bezier(x1, y1, x2, y2)` と同じ意味のイージング曲線。x が時刻の割合、y が進み具合で、
/// 端点は (0, 0) と (1, 1) に固定。`Theme.spinAnimation` の `timingCurve` と同じ形なので、
/// `withAnimation` の補間中の角度（observable ではない）をこの曲線から逆算できる。
/// 制御点は x, y とも 0...1 に収まり、両成分が単調増加である前提（CSS と同じ制約）。
struct CubicBezierCurve: Equatable, Sendable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    /// 時刻の割合 `time`（0...1）における進み具合（0...1）。
    func progress(atTime time: Double) -> Double {
        y(at: solve(target: clamp(time), x(at:)))
    }

    /// 進み具合 `progress`（0...1）に初めて達する時刻の割合（0...1）。`progress(atTime:)` の逆関数。
    func time(atProgress progress: Double) -> Double {
        x(at: solve(target: clamp(progress), y(at:)))
    }

    /// 時刻の割合 `time`（0...1）における曲線の傾き（進み具合 ÷ 時刻の割合、dy/dx）。
    /// 回転の角速度は、これに平均の速さ（回る角度 ÷ 長さ）を掛けたものになる。
    /// パラメータ s での接線の比 (dy/ds) ÷ (dx/ds) で求める。dx/ds が 0 になる端（`x1 == 0` の始点、`x2 == 1` の終点）は
    /// 傾きが発散するので、端からわずかに内側のパラメータで測る（演出に使う値を有限に保つ）。
    func slope(atTime time: Double) -> Double {
        var s = solve(target: clamp(time), x(at:))
        if dx(at: s) < 1e-12 {
            s = min(max(s, 1e-6), 1 - 1e-6)
        }
        return dy(at: s) / dx(at: s)
    }

    private func x(at s: Double) -> Double { component(s, x1, x2) }
    private func y(at s: Double) -> Double { component(s, y1, y2) }
    private func dx(at s: Double) -> Double { derivative(s, x1, x2) }
    private func dy(at s: Double) -> Double { derivative(s, y1, y2) }

    /// `component` をパラメータ s で微分した値。
    private func derivative(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * p1 + 6 * u * s * (p2 - p1) + 3 * s * s * (1 - p2)
    }

    /// 端点 0 と 1 を持つ 3 次ベジェの 1 成分をパラメータ s で評価する。
    private func component(_ s: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - s
        return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
    }

    /// 単調増加な成分が `target` になるパラメータ s を二分法で求める。
    /// 端点は丸めで 1 に届かないことがあるので、二分法に掛けずそのまま返す。
    private func solve(target: Double, _ component: (Double) -> Double) -> Double {
        if target <= 0 { return 0 }
        if target >= 1 { return 1 }
        var low = 0.0
        var high = 1.0
        for _ in 0..<48 {
            let mid = (low + high) / 2
            if component(mid) < target {
                low = mid
            } else {
                high = mid
            }
        }
        return (low + high) / 2
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
