import Foundation
import Testing
@testable import DekiRoulette

struct ResultBandTests {
    @Test func 基準の直径では基準の文字サイズになる() {
        #expect(ResultBand.fontSize(diameter: WheelLabel.referenceDiameter) == ResultBand.baseFontSize)
        #expect((26...30).contains(ResultBand.baseFontSize))
    }

    @Test func 文字サイズと幅と位置は直径に比例する() {
        #expect(ResultBand.fontSize(diameter: 480) == ResultBand.baseFontSize * 1.5)
        #expect(ResultBand.maxWidth(diameter: 480) == 480 * ResultBand.maxWidthRatio)
        #expect(ResultBand.centerOffset(diameter: 480) == ResultBand.centerOffset(diameter: 320) * 1.5)
        #expect(abs(ResultBand.height(diameter: 480) - ResultBand.height(diameter: 320) * 1.5) < 1e-9)
    }

    @Test(arguments: [120.0, 200, 320, 480])
    func 帯は中心より下に置きハブと重ならない(diameter: Double) {
        let top = ResultBand.centerOffset(diameter: diameter) - ResultBand.height(diameter: diameter) / 2
        #expect(top > ResultBand.hubRadius(diameter: diameter))
    }

    @Test(arguments: [120.0, 200, 320, 480])
    func 帯はスライスの円に収まる(diameter: Double) {
        // 帯はカプセル。いちばん外に出るのは下側の両端の半円
        let height = ResultBand.height(diameter: diameter)
        let halfStraight = ResultBand.maxWidth(diameter: diameter) / 2 - height / 2
        let farthest = hypot(halfStraight, ResultBand.centerOffset(diameter: diameter)) + height / 2
        #expect(farthest < ResultBand.sliceRadius(diameter: diameter))
    }

    @Test(arguments: [120.0, 200, 320, 480])
    func 登場のばねで行き過ぎても帯はスライスの円に収まる(diameter: Double) {
        let scale = ResultBand.popInPeakScale
        #expect(scale > 1 && scale < 1.1)
        // 帯の中心で拡大するので、中心の位置は変わらず幅と高さだけ大きくなる
        let height = ResultBand.height(diameter: diameter) * scale
        let halfStraight = ResultBand.maxWidth(diameter: diameter) * scale / 2 - height / 2
        let farthest = hypot(halfStraight, ResultBand.centerOffset(diameter: diameter)) + height / 2
        #expect(farthest < ResultBand.sliceRadius(diameter: diameter))
        // 上の端もハブに重ならない
        #expect(ResultBand.centerOffset(diameter: diameter) - height / 2 > ResultBand.hubRadius(diameter: diameter))
    }

    @Test func 登場は小さい大きさから始める() {
        #expect(ResultBand.popInStartScale > 0 && ResultBand.popInStartScale < 1)
        #expect(ResultBand.popInBounce > 0 && ResultBand.popInBounce < 1)
    }

    @Test func 帯は盤面のラベルより大きい文字で出す() {
        for count in 1...Config.maxItems {
            #expect(ResultBand.fontSize(diameter: 320) > WheelLabel.fontSize(count: count, diameter: 320))
        }
    }

    @Test func 負の直径は0として扱う() {
        #expect(ResultBand.fontSize(diameter: -10) == 0)
        #expect(ResultBand.maxWidth(diameter: -10) == 0)
        #expect(ResultBand.centerOffset(diameter: -10) == 0)
        #expect(ResultBand.height(diameter: -10) == 0)
        #expect(ResultBand.sliceRadius(diameter: -10) == 0)
    }
}
