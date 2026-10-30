import CoreGraphics
import Testing
@testable import DekiRoulette

/// スピン中にページを暗くする幕の判定と、盤面の位置に抜く穴の幾何。
struct SpinSpotlightTests {
    @Test func スピン中だけ幕を掛ける() {
        #expect(SpinSpotlight.opacity(spinning: true) == 1)
        // 待機中・結果表示中・指で動かしている間・惰性はどれも `spinning` が立たない
        #expect(SpinSpotlight.opacity(spinning: false) == 0)
    }

    @Test func 正方形の枠は中央に内接円を抜く() throws {
        let hole = try #require(SpinSpotlight.hole(in: CGRect(x: 20, y: 140, width: 320, height: 320)))
        #expect(hole.center == CGPoint(x: 180, y: 300))
        #expect(hole.radius == 160)
        // 縁は外へ直径の割合だけぼかす（基準直径で約 13pt）
        #expect(abs(hole.feather - 320 * Config.spinSpotlightFeatherRatio) < 1e-9)
        #expect(abs(hole.outerRadius - (160 + 12.8)) < 1e-9)
    }

    @Test func 横長の枠は高さを直径にする() throws {
        let hole = try #require(SpinSpotlight.hole(in: CGRect(x: 0, y: 0, width: 480, height: 300)))
        #expect(hole.center == CGPoint(x: 240, y: 150))
        #expect(hole.radius == 150)
        #expect(abs(hole.feather - 300 * Config.spinSpotlightFeatherRatio) < 1e-9)
    }

    @Test func 縦長の枠は幅を直径にする() throws {
        let hole = try #require(SpinSpotlight.hole(in: CGRect(x: 10, y: 30, width: 200, height: 360)))
        #expect(hole.center == CGPoint(x: 110, y: 210))
        #expect(hole.radius == 100)
    }

    @Test(arguments: [
        CGRect(x: 10, y: 10, width: 0, height: 0),
        CGRect(x: 10, y: 10, width: 320, height: 0),
        CGRect(x: 10, y: 10, width: 0, height: 320),
        CGRect.null,
    ])
    func 大きさの無い枠には穴を抜かない(frame: CGRect) {
        #expect(SpinSpotlight.hole(in: frame) == nil)
    }

    @Test func 幕は中身より四方へ広く覆う() {
        let size = CGSize(width: 393, height: 1400)
        let rect = SpinSpotlight.scrimRect(contentSize: size)
        let bleed = Config.spinScrimBleed
        #expect(rect == CGRect(x: -bleed, y: -bleed, width: 393 + bleed * 2, height: 1400 + bleed * 2))
        // いちばん高い iPad の画面（約 1376pt）より広くはみ出し、中身が短くても見える範囲を覆う
        #expect(bleed > 1376)
        #expect(rect.contains(CGRect(origin: .zero, size: size)))
    }

    @Test func グラデーションの中心は幕の範囲に対する穴の中心の割合() throws {
        let size = CGSize(width: 400, height: 1000)
        let rect = SpinSpotlight.scrimRect(contentSize: size)
        let hole = try #require(SpinSpotlight.hole(in: CGRect(x: 40, y: 150, width: 320, height: 320)))
        let unit = SpinSpotlight.unitCenter(of: hole, in: rect)
        // 割合を幕の範囲に戻すと穴の中心になる
        #expect(abs(rect.minX + unit.x * rect.width - hole.center.x) < 1e-9)
        #expect(abs(rect.minY + unit.y * rect.height - hole.center.y) < 1e-9)
        #expect(unit.x > 0 && unit.x < 1 && unit.y > 0 && unit.y < 1)
        // 大きさの無い範囲では中央
        #expect(SpinSpotlight.unitCenter(of: hole, in: .zero) == CGPoint(x: 0.5, y: 0.5))
    }
}
