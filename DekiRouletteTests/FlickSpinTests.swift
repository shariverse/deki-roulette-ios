import CoreGraphics
import Foundation
import Testing
@testable import DekiRoulette

struct FlickSpinTests {
    private let center = CGPoint(x: 160, y: 160)

    /// 中心から `radius` の円周上を、`from` 度から `degreesPerSecond` で `duration` 秒動いた記録。60Hz で刻む。
    /// 角度は 3 時を 0 度、画面上の時計回りを正とする。
    private func arc(
        radius: CGFloat = 100, from start: Double = -90, degreesPerSecond: Double, duration: TimeInterval, startTime: TimeInterval = 0
    ) -> [FlickSpin.Sample] {
        let steps = Int((duration * 60).rounded())
        return (0...steps).map { step in
            let time = Double(step) / 60
            let angle = (start + degreesPerSecond * time) * .pi / 180
            return FlickSpin.Sample(
                time: startTime + time,
                location: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            )
        }
    }

    // MARK: 角速度

    @Test func 時計回りに回すと正になる() {
        let velocity = FlickSpin.angularVelocity(samples: arc(degreesPerSecond: 600, duration: 0.2), center: center)
        #expect(abs(velocity - 600) < 1)
    }

    @Test func 反時計回りに回すと負になる() {
        let velocity = FlickSpin.angularVelocity(samples: arc(degreesPerSecond: -600, duration: 0.2), center: center)
        #expect(abs(velocity + 600) < 1)
    }

    @Test func 直前の窓の動きだけを見る() {
        // ゆっくり回してから最後の 0.1 秒だけ速く払う
        let slow = arc(degreesPerSecond: 60, duration: 0.5)
        let fast = arc(from: -90 + 30, degreesPerSecond: 900, duration: Config.flickSampleWindow, startTime: 0.5 + 1.0 / 60)
        let velocity = FlickSpin.angularVelocity(samples: slow + fast, center: center)
        #expect(velocity > 700)
    }

    @Test func 離す直前に少し止めても勢いを残す() {
        // 速く払ったあと 50ms 止めてから離す。離した瞬間の速度は 0 だが、窓の平均で閾値を越える
        var samples = arc(degreesPerSecond: 900, duration: 0.2)
        let last = samples[samples.count - 1]
        samples.append(FlickSpin.Sample(time: last.time + 0.05, location: last.location))
        let velocity = FlickSpin.angularVelocity(samples: samples, center: center)
        #expect(FlickSpin.fullSpins(angularVelocity: velocity) != nil)
    }

    @Test func 止めたまま離すと回さない() {
        var samples = arc(degreesPerSecond: 900, duration: 0.2)
        let last = samples[samples.count - 1]
        // 窓より長く止めてから離す
        samples.append(FlickSpin.Sample(time: last.time + Config.flickSampleWindow + 1.0 / 60, location: last.location))
        #expect(FlickSpin.angularVelocity(samples: samples, center: center) == 0)
    }

    @Test func 窓をまたぐ区間は使わない() {
        // 速く払ったあと、止めた位置の記録が無いまま窓より長く経ってから離す
        var samples = arc(degreesPerSecond: 900, duration: 0.2)
        let last = samples[samples.count - 1]
        let stopped = CGPoint(x: center.x + 100 * cos(.pi / 180 * 120), y: center.y + 100 * sin(.pi / 180 * 120))
        samples.append(FlickSpin.Sample(time: last.time + Config.flickSampleWindow * 1.5, location: stopped))
        #expect(FlickSpin.angularVelocity(samples: samples, center: center) == 0)
    }

    @Test func 中心付近で止めてから離すと回さない() {
        // 速く回したあと中心付近へ指を入れ、窓より長く置いてから離す
        var samples = arc(degreesPerSecond: 900, duration: 0.2)
        let last = samples[samples.count - 1]
        samples.append(FlickSpin.Sample(time: last.time + 1.0 / 60, location: center))
        samples.append(FlickSpin.Sample(time: last.time + 1.0 / 60 + Config.flickSampleWindow * 1.2, location: center))
        #expect(FlickSpin.angularVelocity(samples: samples, center: center) == 0)
    }

    @Test func 直線の払いでも中心のまわりの成分を拾う() {
        // 盤面上側を右へまっすぐ 1500pt/秒
        let samples = (0...12).map { step in
            FlickSpin.Sample(time: Double(step) / 60, location: CGPoint(x: 70 + 25 * CGFloat(step), y: 60))
        }
        let velocity = FlickSpin.angularVelocity(samples: samples, center: center)
        #expect(velocity > Config.flickMinAngularVelocity)
    }

    @Test func 半径方向の動きは角速度にならない() {
        let samples = (0...6).map { step in
            FlickSpin.Sample(time: Double(step) / 60, location: CGPoint(x: 200 + 20 * CGFloat(step), y: 160))
        }
        #expect(abs(FlickSpin.angularVelocity(samples: samples, center: center)) < 1e-9)
    }

    @Test func 九時をまたいでも一周分跳ねない() {
        // atan2 が ±180 度で折り返す位置（9 時）を時計回りにまたぐ
        let velocity = FlickSpin.angularVelocity(samples: arc(from: 160, degreesPerSecond: 600, duration: 0.1), center: center)
        #expect(abs(velocity - 600) < 1)
    }

    @Test func 中心付近の点は使わない() {
        let inside = Config.flickDeadZoneRadius - 1
        let samples = arc(radius: inside, degreesPerSecond: 3000, duration: 0.1)
        #expect(FlickSpin.angularVelocity(samples: samples, center: center) == 0)
    }

    @Test func 中心付近を挟んだ前後の点をつながない() {
        // 9 時 → 中心 → 3 時と払う。中心の点を除いて左右をつなぐと半周回ったことになる
        let samples = [
            FlickSpin.Sample(time: 0, location: CGPoint(x: center.x - 100, y: center.y)),
            FlickSpin.Sample(time: 0.05, location: center),
            FlickSpin.Sample(time: 0.1, location: CGPoint(x: center.x + 100, y: center.y)),
        ]
        #expect(FlickSpin.angularVelocity(samples: samples, center: center) == 0)
    }

    @Test func 記録が1点以下なら0() {
        #expect(FlickSpin.angularVelocity(samples: [], center: center) == 0)
        #expect(FlickSpin.angularVelocity(samples: Array(arc(degreesPerSecond: 600, duration: 0.1).prefix(1)), center: center) == 0)
    }

    // MARK: ドラッグ中の角速度

    @Test func ドラッグ中の角速度は回している速さ() {
        let samples = arc(degreesPerSecond: -480, duration: 0.5)
        for now in [0.2, 0.3, 0.5] {
            let velocity = FlickSpin.angularVelocity(samples: samples, center: center, at: now)
            #expect(abs(velocity + 480) < 1)
        }
    }

    @Test func 最後の点の時刻では離したときの角速度と同じ() throws {
        let samples = arc(degreesPerSecond: 700, duration: 0.3)
        let last = try #require(samples.last)
        let during = FlickSpin.angularVelocity(samples: samples, center: center, at: last.time)
        let release = FlickSpin.angularVelocity(samples: samples, center: center)
        #expect(abs(during - release) < 1e-9)
    }

    @Test func 指を止めると窓の長さで0に落ちる() throws {
        let samples = arc(degreesPerSecond: 600, duration: 0.3)
        let last = try #require(samples.last).time
        let moving = FlickSpin.angularVelocity(samples: samples, center: center, at: last)
        let pausing = FlickSpin.angularVelocity(samples: samples, center: center, at: last + Config.flickSampleWindow / 2)
        #expect(pausing > 0)
        #expect(pausing < moving)
        #expect(FlickSpin.angularVelocity(samples: samples, center: center, at: last + Config.flickSampleWindow + 0.01) == 0)
    }

    @Test func 記録より前の時刻なら0() {
        let samples = arc(degreesPerSecond: 600, duration: 0.3, startTime: 10)
        #expect(FlickSpin.angularVelocity(samples: samples, center: center, at: 9) == 0)
        #expect(FlickSpin.angularVelocity(samples: samples, center: center, at: 10) == 0)
    }

    // MARK: 記録

    @Test @MainActor func 間が空いたら前の記録を捨てる() {
        let buffer = FlickSampleBuffer()
        buffer.append(FlickSpin.Sample(time: 0, location: CGPoint(x: 260, y: 160)))
        buffer.append(FlickSpin.Sample(time: 1, location: CGPoint(x: 160, y: 60)))
        #expect(buffer.samples.count == 1)
    }

    @Test @MainActor func 窓の2倍より古い点は捨てる() throws {
        let buffer = FlickSampleBuffer()
        for sample in arc(degreesPerSecond: 600, duration: 1) { buffer.append(sample) }
        let first = try #require(buffer.samples.first)
        let last = try #require(buffer.samples.last)
        #expect(last.time - first.time <= Config.flickSampleWindow * 2 + 1e-9)
    }

    // MARK: 周回数

    @Test func 閾値未満では回さない() {
        #expect(FlickSpin.fullSpins(angularVelocity: 0) == nil)
        #expect(FlickSpin.fullSpins(angularVelocity: Config.flickMinAngularVelocity - 1) == nil)
        #expect(FlickSpin.fullSpins(angularVelocity: -(Config.flickMinAngularVelocity - 1)) == nil)
    }

    @Test func 閾値ちょうどで最小の周回数になる() {
        #expect(FlickSpin.fullSpins(angularVelocity: Config.flickMinAngularVelocity) == Config.fullSpinRange.lowerBound)
    }

    @Test func 上限以上は最大の周回数で頭打ちになる() {
        #expect(FlickSpin.fullSpins(angularVelocity: Config.flickMaxAngularVelocity) == Config.fullSpinRange.upperBound)
        #expect(FlickSpin.fullSpins(angularVelocity: Config.flickMaxAngularVelocity * 10) == Config.fullSpinRange.upperBound)
    }

    @Test func 反時計回りのフリックでも速さだけを見る() {
        for speed in stride(from: Config.flickMinAngularVelocity, through: Config.flickMaxAngularVelocity, by: 100) {
            #expect(FlickSpin.fullSpins(angularVelocity: speed) == FlickSpin.fullSpins(angularVelocity: -speed))
        }
    }

    @Test func 速いほど周回数は減らない() throws {
        var previous = Config.fullSpinRange.lowerBound
        for speed in stride(from: Config.flickMinAngularVelocity, through: Config.flickMaxAngularVelocity + 500, by: 10) {
            let spins = try #require(FlickSpin.fullSpins(angularVelocity: speed))
            #expect(Config.fullSpinRange.contains(spins))
            #expect(spins >= previous)
            previous = spins
        }
    }

    // MARK: 初速

    /// 曲線 `easing` で `distance` 度を `duration` 秒かけて回すときの、回り始めの角速度（度/秒）。
    private func initialSpeed(_ easing: CubicBezierCurve, distance: Double, duration: TimeInterval) -> Double {
        let dt = 1e-5
        return easing.progress(atTime: dt) * distance / (dt * duration)
    }

    @Test func 盤面は指を離した瞬間の速さで回り出す() {
        for velocity in [Config.flickMinAngularVelocity, 600, 1200, -900] {
            let distance = 4.0 * 360 + 135
            let easing = FlickSpin.easing(angularVelocity: velocity, distance: distance, duration: Config.spinDuration)
            let speed = initialSpeed(easing, distance: distance, duration: Config.spinDuration)
            #expect(abs(speed - abs(velocity)) / abs(velocity) < 0.01)
        }
    }

    @Test func 初速は向きに依らず速さで決める() {
        let distance = 6.0 * 360 + 40
        #expect(
            FlickSpin.easing(angularVelocity: 800, distance: distance, duration: Config.spinDuration)
                == FlickSpin.easing(angularVelocity: -800, distance: distance, duration: Config.spinDuration)
        )
    }

    @Test func 初速を変えても止まり方と長さの前提は同じ() {
        let easing = FlickSpin.easing(angularVelocity: 1000, distance: 2000, duration: Config.spinDuration)
        // 始点の傾き以外は基準の曲線のまま。終わりの減速の形と、時刻 1 で止まることは変わらない
        #expect(easing.x1 == Config.spinEasing.x1)
        #expect(easing.x2 == Config.spinEasing.x2)
        #expect(easing.y2 == Config.spinEasing.y2)
        #expect(easing.progress(atTime: 1) == 1)
    }

    @Test func 速すぎるフリックは曲線が保てる初速で頭打ちになる() {
        let easing = FlickSpin.easing(angularVelocity: 100_000, distance: 1500, duration: Config.spinDuration)
        #expect(easing.y1 == 1)
    }

    @Test func 初速を変えた曲線も単調に進む() {
        for velocity in stride(from: Config.flickMinAngularVelocity, through: 6000, by: 240) {
            let easing = FlickSpin.easing(angularVelocity: velocity, distance: 4 * 360 + 10, duration: Config.spinDuration)
            var previous = 0.0
            for step in 1...200 {
                let progress = easing.progress(atTime: Double(step) / 200)
                #expect(progress >= previous)
                previous = progress
            }
            #expect(abs(previous - 1) < 1e-9)
        }
    }

    // MARK: 指を離したとき

    @Test func 閾値ちょうどから回し閾値未満では回さない() {
        let low = Config.flickMinAngularVelocity
        for velocity in [0, 1, low - 1, low - 0.001, -(low - 1), -(low - 0.001)] {
            #expect(FlickSpin.spin(angularVelocity: velocity) == nil)
        }
        #expect(FlickSpin.spin(angularVelocity: low) == FlickSpin.Spin(fullSpins: Config.fullSpinRange.lowerBound, direction: .clockwise))
        #expect(FlickSpin.spin(angularVelocity: -low) == FlickSpin.Spin(fullSpins: Config.fullSpinRange.lowerBound, direction: .counterclockwise))
    }

    // MARK: 向き

    @Test func 時計回りのフリックは時計回りに回す() {
        let spin = FlickSpin.spin(angularVelocity: Config.flickMinAngularVelocity)
        #expect(spin == FlickSpin.Spin(fullSpins: Config.fullSpinRange.lowerBound, direction: .clockwise))
    }

    @Test func 反時計回りのフリックは反時計回りに回す() {
        let spin = FlickSpin.spin(angularVelocity: -Config.flickMaxAngularVelocity)
        #expect(spin == FlickSpin.Spin(fullSpins: Config.fullSpinRange.upperBound, direction: .counterclockwise))
    }

    @Test func 向きを返しても閾値と周回数は変わらない() {
        #expect(FlickSpin.spin(angularVelocity: 0) == nil)
        #expect(FlickSpin.spin(angularVelocity: Config.flickMinAngularVelocity - 1) == nil)
        #expect(FlickSpin.spin(angularVelocity: -(Config.flickMinAngularVelocity - 1)) == nil)
        for speed in stride(from: Config.flickMinAngularVelocity, through: Config.flickMaxAngularVelocity + 500, by: 10) {
            #expect(FlickSpin.spin(angularVelocity: speed)?.fullSpins == FlickSpin.fullSpins(angularVelocity: speed))
            #expect(FlickSpin.spin(angularVelocity: -speed)?.fullSpins == FlickSpin.fullSpins(angularVelocity: -speed))
            #expect(FlickSpin.spin(angularVelocity: speed)?.direction == .clockwise)
            #expect(FlickSpin.spin(angularVelocity: -speed)?.direction == .counterclockwise)
        }
    }

    @Test func 反時計回りに払った記録から反時計回りの向きが出る() {
        let velocity = FlickSpin.angularVelocity(samples: arc(degreesPerSecond: -900, duration: 0.2), center: center)
        #expect(FlickSpin.spin(angularVelocity: velocity)?.direction == .counterclockwise)
        let clockwise = FlickSpin.angularVelocity(samples: arc(degreesPerSecond: 900, duration: 0.2), center: center)
        #expect(FlickSpin.spin(angularVelocity: clockwise)?.direction == .clockwise)
    }
}
