import CoreGraphics
import SwiftUI
import Testing
@testable import DekiRoulette

/// 盤面のドラッグとフリックを受ける円（スライスの円）の判定。
struct WheelDragHitTests {
    /// 中心から `radius` の距離で、3 時を 0 度・画面上の時計回りを正とする角度 `degrees` の点。
    private func point(_ degrees: Double, radius: Double, center: CGPoint) -> CGPoint {
        let rad = degrees * .pi / 180
        return CGPoint(x: Double(center.x) + radius * cos(rad), y: Double(center.y) + radius * sin(rad))
    }

    @Test(arguments: [Double(Theme.Layout.wheelMaxWidthCompact), Double(Theme.Layout.wheelMaxWidthRegular)])
    func 判定の半径はスライスの円と同じ(side: Double) {
        #expect(WheelDrag.hitRadius(side: side) == WheelGeometry.sliceRadius(diameter: side))
        // 基準直径（320pt）で 144pt、regular の上限（480pt）で 216pt。縁（スライスの円の外 5〜11pt）は含めない
        let scale = side / WheelLabel.referenceDiameter
        #expect(abs(WheelDrag.hitRadius(side: side) - (side / 2 - 16 * scale)) < 1e-9)
    }

    @Test(arguments: [Double(Theme.Layout.wheelMaxWidthCompact), Double(Theme.Layout.wheelMaxWidthRegular)])
    func 円周ちょうどと少し内は受け少し外は受けない(side: Double) {
        let center = CGPoint(x: side / 2, y: side / 2)
        let radius = WheelDrag.hitRadius(side: side)
        for degrees in stride(from: 0.0, to: 360, by: 30) {
            #expect(WheelDrag.contains(point(degrees, radius: radius, center: center), center: center, side: side))
            #expect(WheelDrag.contains(point(degrees, radius: radius - 0.5, center: center), center: center, side: side))
            #expect(!WheelDrag.contains(point(degrees, radius: radius + 0.5, center: center), center: center, side: side))
        }
    }

    @Test(arguments: [Double(Theme.Layout.wheelMaxWidthCompact), Double(Theme.Layout.wheelMaxWidthRegular)])
    func 縁の環と四隅は受けない(side: Double) {
        let center = CGPoint(x: side / 2, y: side / 2)
        let scale = side / WheelLabel.referenceDiameter
        let slice = WheelGeometry.sliceRadius(diameter: side)
        // 外周の縁（wheelRim の環と wheelEdge の線）はスライスの円の外 5〜11pt（基準直径で）
        for offset in [5.0, 8, 11] {
            #expect(!WheelDrag.contains(point(-90, radius: slice + offset * scale, center: center), center: center, side: side))
            #expect(!WheelDrag.contains(point(45, radius: slice + offset * scale, center: center), center: center, side: side))
        }
        // 12 時の針の先（枠の上端の中央）
        #expect(!WheelDrag.contains(CGPoint(x: side / 2, y: 2), center: center, side: side))
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0), CGPoint(x: 0, y: side), CGPoint(x: side, y: side)]
        for corner in corners {
            #expect(!WheelDrag.contains(corner, center: center, side: side))
            // 四隅から少し内側（円の外の余白）も受けない
            let inset = CGPoint(x: corner.x == 0 ? 20 : side - 20, y: corner.y == 0 ? 20 : side - 20)
            #expect(!WheelDrag.contains(inset, center: center, side: side))
        }
    }

    @Test func ハブの中と中心は受ける() {
        let side = Double(Theme.Layout.wheelMaxWidthCompact)
        let center = CGPoint(x: side / 2, y: side / 2)
        #expect(WheelDrag.contains(center, center: center, side: side))
        // ハブは直径 38pt。デッドゾーンの中でもドラッグは始まる（追従しないのは `rotationDelta` の側）
        #expect(WheelDrag.contains(point(30, radius: 18, center: center), center: center, side: side))
        #expect(WheelDrag.contains(point(200, radius: Config.flickDeadZoneRadius / 2, center: center), center: center, side: side))
    }

    @Test func 大きさが0の盤面ではどこも受けない() {
        #expect(WheelDrag.hitRadius(side: 0) == 0)
        #expect(!WheelDrag.contains(.zero, center: .zero, side: 0))
        #expect(!WheelDrag.contains(CGPoint(x: 1, y: 1), center: .zero, side: 0))
        #expect(WheelHitShape().path(in: .zero).isEmpty)
    }

    @Test(arguments: [
        CGSize(width: Theme.Layout.wheelMaxWidthCompact, height: Theme.Layout.wheelMaxWidthCompact),
        CGSize(width: Theme.Layout.wheelMaxWidthRegular, height: Theme.Layout.wheelMaxWidthRegular),
        CGSize(width: 360, height: 300),
    ])
    func 当たり判定の形は判定の関数と同じ円(size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        let side = Double(min(size.width, size.height))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let path = WheelHitShape().path(in: rect)
        let radius = WheelDrag.hitRadius(side: side)
        for degrees in stride(from: 0.0, to: 360, by: 15) {
            for distance in [0.0, 19, radius - 1, radius + 1, radius + 11 * side / WheelLabel.referenceDiameter] {
                let p = point(degrees, radius: distance, center: center)
                #expect(path.contains(p) == WheelDrag.contains(p, center: center, side: side))
            }
        }
        // 盤面の描画と同じく、枠の中央を中心に一辺 min(width, height) の盤面として描く
        #expect(!path.contains(CGPoint(x: 1, y: 1)))
        #expect(!path.contains(CGPoint(x: rect.maxX - 1, y: rect.maxY - 1)))
    }
}
