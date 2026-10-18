import Testing
@testable import DekiRoulette

struct CubicBezierCurveTests {
    private let spin = Config.spinEasing
    private let linear = CubicBezierCurve(0.25, 0.25, 0.75, 0.75)

    @Test func 端点は0と1() {
        #expect(abs(spin.progress(atTime: 0)) < 1e-9)
        #expect(abs(spin.progress(atTime: 1) - 1) < 1e-9)
        #expect(abs(spin.time(atProgress: 0)) < 1e-9)
        #expect(abs(spin.time(atProgress: 1) - 1) < 1e-9)
    }

    @Test func 対角線上の制御点なら恒等写像() {
        for step in 0...20 {
            let t = Double(step) / 20
            #expect(abs(linear.progress(atTime: t) - t) < 1e-6)
            #expect(abs(linear.time(atProgress: t) - t) < 1e-6)
        }
    }

    @Test func スピンの曲線は前半で大きく進んで減速する() {
        // 半分の時刻で 9 割以上進んでいる（cubic-bezier(0.15, 0.85, 0.3, 1) は強いイーズアウト）
        #expect(spin.progress(atTime: 0.5) > 0.9)
        // 序盤の傾きは終盤より大きい
        let early = spin.progress(atTime: 0.1) - spin.progress(atTime: 0)
        let late = spin.progress(atTime: 1) - spin.progress(atTime: 0.9)
        #expect(early > late * 10)
    }

    @Test func 傾きは進み具合の数値微分と一致する() {
        let step = 1e-6
        for curve in [spin, linear, FlickCoast.easing, CubicBezierCurve(0.15, 0.4, 0.3, 1)] {
            for index in 1..<50 {
                let t = Double(index) / 50
                let numeric = (curve.progress(atTime: t + step) - curve.progress(atTime: t - step)) / (2 * step)
                #expect(abs(curve.slope(atTime: t) - numeric) < 1e-4 * max(curve.slope(atTime: t), 1))
            }
        }
    }

    @Test func 端の傾きは制御点の向き() {
        // 始点は y1 / x1、終点は (1 - y2) / (1 - x2)
        #expect(abs(spin.slope(atTime: 0) - spin.y1 / spin.x1) < 1e-9)
        #expect(abs(spin.slope(atTime: 1)) < 1e-9)
        #expect(abs(FlickCoast.easing.slope(atTime: 0) - 2) < 1e-9)
        #expect(abs(linear.slope(atTime: 0.5) - 1) < 1e-9)
        // 範囲外の時刻は端に収める
        #expect(abs(spin.slope(atTime: -1) - spin.slope(atTime: 0)) < 1e-9)
        #expect(abs(spin.slope(atTime: 2) - spin.slope(atTime: 1)) < 1e-9)
    }

    @Test func 端で接線が縦になる曲線でも傾きは有限() {
        let curve = CubicBezierCurve(0, 0.5, 1, 0.5)
        #expect(curve.slope(atTime: 0).isFinite)
        #expect(curve.slope(atTime: 1).isFinite)
    }

    @Test func 進み具合は時刻に対して単調増加() {
        var previous = -1.0
        for step in 0...100 {
            let value = spin.progress(atTime: Double(step) / 100)
            #expect(value >= previous)
            previous = value
        }
    }

    @Test func 時刻と進み具合は互いに逆関数() {
        for step in 1..<20 {
            let t = Double(step) / 20
            #expect(abs(spin.time(atProgress: spin.progress(atTime: t)) - t) < 1e-6)
        }
    }

    @Test func 範囲外の入力は端に丸める() {
        #expect(abs(spin.progress(atTime: -0.5)) < 1e-9)
        #expect(abs(spin.progress(atTime: 1.5) - 1) < 1e-9)
    }
}
