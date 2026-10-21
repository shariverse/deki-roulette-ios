import CoreGraphics
import Foundation
import Testing
@testable import DekiRoulette

struct WheelBackGlowTests {
    @Test func 不透明度は強さに比例する() {
        #expect(WheelBackGlow.opacity(intensity: 0, reduceMotion: false) == 0)
        #expect(abs(WheelBackGlow.opacity(intensity: 1, reduceMotion: false) - Config.wheelBackGlowMaxOpacity) < 1e-9)
        #expect(abs(WheelBackGlow.opacity(intensity: 0.5, reduceMotion: false) - Config.wheelBackGlowMaxOpacity / 2) < 1e-9)
        // 範囲外は端で止める
        #expect(abs(WheelBackGlow.opacity(intensity: 3, reduceMotion: false) - Config.wheelBackGlowMaxOpacity) < 1e-9)
        #expect(WheelBackGlow.opacity(intensity: -1, reduceMotion: false) == 0)
        #expect(WheelBackGlow.opacity(intensity: .nan, reduceMotion: false) == 0)
    }

    @Test func 動きを減らす設定では出さない() {
        for intensity in [0, 0.3, 1] {
            #expect(WheelBackGlow.opacity(intensity: intensity, reduceMotion: true) == 0)
        }
        #expect(!WheelBackGlow.animates(reduceMotion: true, moving: true))
    }

    @Test func 動いている間だけ描き直す() {
        #expect(WheelBackGlow.animates(reduceMotion: false, moving: true))
        #expect(!WheelBackGlow.animates(reduceMotion: false, moving: false))
    }

    /// スピンの序盤は明るく、減速につれて暗くなり、止まったら消える（焦らしの区間は強さが小さいのでほとんど光らない）。
    @Test func スピンの速さに合わせて明るくなり止まると消える() {
        var rng = SeededGenerator(seed: 3)
        let to = RouletteMath.nextRotation(current: 0, targetIndex: 1, count: 6, direction: .clockwise, using: &rng)
        let path = SpinPath.spin(from: 0, to: to, count: 6, effects: .all, using: &rng)
        let opacity = { (time: TimeInterval) in WheelBackGlow.opacity(intensity: path.intensity(at: time), reduceMotion: false) }
        #expect(opacity(0.3) > Config.wheelBackGlowMaxOpacity * 0.9)
        #expect(opacity(3.5) < opacity(0.3))
        #expect(opacity(path.duration - 0.1) < Config.wheelBackGlowMaxOpacity * 0.06)
        #expect(opacity(path.duration + 0.5) == 0)
    }

    /// 光の環は外周の縁の外周から盤面の枠までで、盤面の面には重ならず枠を越えない。
    @Test(arguments: [CGFloat(160), 320, 480])
    func 光の環は縁の外周から盤面の枠まで(diameter: CGFloat) {
        let inner = Double(Theme.BackGlow.innerRadius(diameter: diameter))
        let outer = Double(Theme.BackGlow.outerRadius(diameter: diameter))
        let scale = Double(diameter) / WheelLabel.referenceDiameter
        let rim = WheelGeometry.sliceRadius(diameter: Double(diameter)) + Double(Theme.Wheel3D.rimWidth) * scale
        #expect(abs(inner - rim) < 1e-9)
        #expect(abs(outer - Double(diameter) / 2) < 1e-9)
        #expect(inner < outer)
    }
}
