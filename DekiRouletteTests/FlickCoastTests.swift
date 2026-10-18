import Foundation
import Testing
@testable import DekiRoulette

struct FlickCoastTests {
    @Test func 止めてから離したら惰性を付けない() {
        #expect(FlickCoast.coast(angularVelocity: 0) == nil)
        #expect(FlickCoast.coast(angularVelocity: 1) == nil)
        #expect(FlickCoast.coast(angularVelocity: -1) == nil)
        let below = Config.flickCoastMinAngle / Config.flickCoastFactor * 0.99
        #expect(FlickCoast.coast(angularVelocity: below) == nil)
        #expect(FlickCoast.coast(angularVelocity: Config.flickCoastMinAngle / Config.flickCoastFactor) != nil)
    }

    @Test func 速く離すほど遠くまで回る() throws {
        var previous = 0.0
        for velocity in stride(from: 20.0, to: Config.flickMinAngularVelocity, by: 20) {
            let coast = try #require(FlickCoast.coast(angularVelocity: velocity))
            #expect(abs(coast.distance - velocity * Config.flickCoastFactor) < 1e-9)
            #expect(coast.distance > previous)
            previous = coast.distance
        }
    }

    @Test func 閾値の手前でも数十度に収まる() throws {
        let coast = try #require(FlickCoast.coast(angularVelocity: Config.flickMinAngularVelocity - 1))
        #expect(coast.distance > 10)
        #expect(coast.distance <= Config.flickCoastMaxAngle)
        #expect(coast.duration > 0)
        #expect(coast.duration < 1)
    }

    @Test func 回る角度は上限で抑える() throws {
        let coast = try #require(FlickCoast.coast(angularVelocity: 5000))
        #expect(abs(coast.distance - Config.flickCoastMaxAngle) < 1e-9)
    }

    @Test func 向きは角速度の符号() throws {
        let clockwise = try #require(FlickCoast.coast(angularVelocity: 120))
        let counter = try #require(FlickCoast.coast(angularVelocity: -120))
        #expect(clockwise.distance > 0)
        #expect(abs(counter.distance + clockwise.distance) < 1e-9)
        #expect(abs(counter.duration - clockwise.duration) < 1e-9)
    }

    @Test func 初速は離した角速度につながる() throws {
        for velocity in [30.0, 100, -180, 239, 5000] {
            let coast = try #require(FlickCoast.coast(angularVelocity: velocity))
            // 曲線の始点の傾き × 平均の速さ = 初速
            let start = coast.easing.y1 / coast.easing.x1 * abs(coast.distance) / coast.duration
            #expect(abs(start - abs(velocity)) < 1e-6)
            // 動き始めの短い間の速さも離した速さに近い
            let instant = coast.duration * 0.001
            let early = abs(coast.angle(after: instant)) / instant
            #expect(abs(early - abs(velocity)) / abs(velocity) < 0.02)
        }
    }

    @Test func 途中の角度は単調に進み終点で止まる() throws {
        let coast = try #require(FlickCoast.coast(angularVelocity: -200))
        #expect(coast.angle(after: 0) == 0)
        var previous = 0.0
        for step in 1...20 {
            let angle = coast.angle(after: coast.duration * Double(step) / 20)
            #expect(angle <= previous)
            previous = angle
        }
        #expect(abs(coast.angle(after: coast.duration) - coast.distance) < 1e-9)
        #expect(abs(coast.angle(after: coast.duration + 1) - coast.distance) < 1e-9)
    }

    @Test func 終わりは減速して止まる() throws {
        let coast = try #require(FlickCoast.coast(angularVelocity: 200))
        let end = coast.duration
        let last = coast.angle(after: end) - coast.angle(after: end - 0.01)
        let first = coast.angle(after: 0.01)
        #expect(last < first * 0.1)
    }
}
