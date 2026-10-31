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

    @Test func 画面の座標の枠は幕の原点を引いて穴にする() throws {
        // 幕は NavigationStack の外（安全領域を含む）に重ねるので、原点は画面の左上に近い。盤面はスクロールした本文の中
        let frame = CGRect(x: 41, y: 250, width: 320, height: 320)
        let hole = try #require(SpinSpotlight.hole(inGlobal: frame, layerOrigin: CGPoint(x: 0, y: 0)))
        #expect(hole == SpinSpotlight.hole(in: frame))
        // 幕の原点がずれていれば（iPad の分割表示などで窓が画面の左上に無い）その分を引く
        let shifted = try #require(SpinSpotlight.hole(inGlobal: frame, layerOrigin: CGPoint(x: 20, y: -30)))
        #expect(shifted.center == CGPoint(x: 181, y: 440))
        #expect(shifted.radius == 160)
    }

    @Test func スクロールした分だけ穴が盤面に付いていく() throws {
        let origin = CGPoint.zero
        let top = try #require(SpinSpotlight.hole(inGlobal: CGRect(x: 41, y: 250, width: 320, height: 320), layerOrigin: origin))
        // 本文を 200pt 上へスクロールした。盤面の上半分がナビゲーションバーの下に潜っても穴は盤面の中心に残る
        let scrolled = try #require(SpinSpotlight.hole(inGlobal: CGRect(x: 41, y: 50, width: 320, height: 320), layerOrigin: origin))
        #expect(scrolled.center.y == top.center.y - 200)
        #expect(scrolled.center.x == top.center.x)
    }

    @Test func 画面の座標でも大きさの無い枠には穴を抜かない() {
        #expect(SpinSpotlight.hole(inGlobal: CGRect(x: 10, y: 10, width: 0, height: 320), layerOrigin: .zero) == nil)
    }

    @Test func グラデーションの中心は幕の範囲に対する穴の中心の割合() throws {
        // 幕は原点が左上の画面の大きさ
        let rect = CGRect(x: 0, y: 0, width: 402, height: 874)
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
