import CoreGraphics
import Foundation

/// ドラッグ中に盤面を指に追従させる角度の計算。フリックの角速度（`FlickSpin`）と同じ角度の測り方を使う。
enum WheelDrag {
    /// 指が `from` から `to` へ動いたとき、盤面中心 `center` のまわりに盤面を回す角度（度、画面上の時計回りが正）。
    /// 中心から `Config.flickDeadZoneRadius` 未満のところは角度が定まらないので、区間がそこに掛かれば 0（盤面は動かさない）。
    /// 両端が外にあっても、間で中心付近を横切る区間は 0 にする（端だけで見ると半回転して見える）。
    /// 中心付近を通って反対側へ抜けても、抜けた先から改めて追従するだけで盤面は跳ねない。
    static func rotationDelta(from: CGPoint, to: CGPoint, center: CGPoint) -> Double {
        guard distance(from: center, toSegment: from, to) >= Config.flickDeadZoneRadius else { return 0 }
        return normalized(angle(of: to, around: center) - angle(of: from, around: center))
    }

    /// 一辺 `side`（pt）の盤面で、ドラッグとフリックを受ける円の半径（pt）。スライスの円（`WheelGeometry.sliceRadius`）と同じで、
    /// 外周の縁・針の先・縁の外の余白は含めない。2D と 3D（傾けても判定は傾けない円）で同じ値を使う。
    static func hitRadius(side: Double) -> Double {
        WheelGeometry.sliceRadius(diameter: side)
    }

    /// 一辺 `side` の盤面の中心 `center` に対して、触れ始めた点 `point` がドラッグとフリックを受ける円の内側（円周を含む）か。
    /// 判定は触れ始めの位置だけで行い、円の内側で始めたドラッグは指が外へ出ても続く（`WheelDragArea` の `contentShape`）。
    static func contains(_ point: CGPoint, center: CGPoint, side: Double) -> Bool {
        let radius = hitRadius(side: side)
        return radius > 0 && distance(from: center, to: point) <= radius
    }

    /// 盤面の累積角が `from` から `to` へ動いたときに、針がスライスの境目を越えた数（向きに依らず 0 以上）。
    /// 境目は累積角が `360 / count` の倍数に達するところ（`SpinTicks` と同じ）。1 件以下の盤面には境目が無いので 0。
    static func boundaryCrossings(from: Double, to: Double, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let sliceAngle = 360.0 / Double(count)
        return abs(Int((to / sliceAngle).rounded(.down)) - Int((from / sliceAngle).rounded(.down)))
    }

    /// ドラッグ中に境目を越えたときの回転音と触覚の間引き。指を速く動かすと境目が詰まるので、
    /// スピン中と同じ最短間隔（`Config.clickMinInterval` / `Config.hapticMinInterval`）より詰まったものは鳴らさない。
    struct FeedbackThrottle {
        private var lastClick = -Double.infinity
        private var lastHaptic = -Double.infinity

        /// 時刻 `time`（秒）に境目を越えた。回転音と触覚をそれぞれ鳴らすかを返す。
        mutating func cross(at time: TimeInterval) -> (click: Bool, haptic: Bool) {
            let click = time - lastClick >= Config.clickMinInterval
            let haptic = time - lastHaptic >= Config.hapticMinInterval
            if click { lastClick = time }
            if haptic { lastHaptic = time }
            return (click, haptic)
        }
    }

    /// 中心から見た向き（度）。SwiftUI は y 軸が下向きなので、値が増える向きが画面上の時計回りになる。
    static func angle(of point: CGPoint, around center: CGPoint) -> Double {
        atan2(Double(point.y - center.y), Double(point.x - center.x)) * 180 / .pi
    }

    /// 隣り合う 2 点の角度差を -180〜180 度に収める。±180 度をまたいでも 1 周分跳ねないようにする。
    static func normalized(_ delta: Double) -> Double {
        var value = delta.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return value
    }

    static func distance(from a: CGPoint, to b: CGPoint) -> Double {
        hypot(Double(b.x - a.x), Double(b.y - a.y))
    }

    /// 点 `point` から `a`〜`b` の線分までの最短距離。
    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(from: point, to: a) }
        let t = min(max((Double(point.x - a.x) * dx + Double(point.y - a.y) * dy) / lengthSquared, 0), 1)
        return distance(from: point, to: CGPoint(x: Double(a.x) + t * dx, y: Double(a.y) + t * dy))
    }
}
