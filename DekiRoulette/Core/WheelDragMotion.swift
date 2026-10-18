import CoreGraphics
import Foundation

/// 指で盤面を動かしている間の動き。速さに連動する演出（電飾の流れ・光の尾・残像・火花）が、盤面が自分で回る動き（`TimedSpinMotion`）の
/// 代わりに毎フレーム引く。補間中の角度と違い、ドラッグ中の角度は View の state（`WheelDragArea` の `dragRotation`）なので、
/// 指が動くたびに位置と追従で回した角度を記録し、角速度は指を離したときのフリック（`FlickSpin.angularVelocity(samples:center:at:)`）と同じく
/// 直前 `Config.flickSampleWindow` 秒に中心のまわりを回った角度から求め、`SpinEffectIntensity.smoothed` でならす。
///
/// 時刻はすべて演出の時計（`RouletteModel.now` = `systemUptime` の秒）。ドラッグの指の時刻（`DragGesture.Value.time` = `Date` の秒）は
/// `clockOffset(effectNow:gestureNow:)` で求めたずれを足してから渡す（`FlickSampleBuffer` は `Date` の秒のまま）。
/// 角度・時刻・指の位置だけを持ち、項目・指定・印は持たない。
struct WheelDragMotion: Equatable, Sendable {
    /// 指の位置の記録 1 つ。
    struct Point: Equatable, Sendable {
        /// 演出の時計の秒。
        var time: TimeInterval
        var location: CGPoint
        /// ドラッグを始めてから追従で回した角度の累計（度、画面上の時計回りが正）。
        var angle: Double
        /// この時刻の平滑した角速度（度/秒）。記録したときに前の点から求めて持つ（後から点を捨てても変わらない）。
        var velocity: Double
    }

    /// 盤面の中心（指の位置と同じ座標）。
    let center: CGPoint
    /// 最初の点の時刻（演出の時計の秒）。火花の生まれうる時刻はここから区切る。
    let start: TimeInterval
    /// 時刻順の点。`Config.dragEffectHistory` より古いものは捨てる。空にはしない。
    private(set) var points: [Point]

    /// 最初の点でドラッグを始める。始めた瞬間は止まっている（角速度 0）。
    init(center: CGPoint, time: TimeInterval, location: CGPoint, angle: Double) {
        self.center = center
        start = time
        points = [Point(time: time, location: location, angle: angle, velocity: 0)]
    }

    /// 演出の時計とドラッグの指の時計のずれ（秒）。ドラッグを始めたときに、両方の時計の今の時刻から 1 回だけ求め、
    /// 指の時刻に足して演出の時計にする（`DragGesture.Value.time` は指が動いた時刻なので、描いた時刻より正確）。
    static func clockOffset(effectNow: TimeInterval, gestureNow: TimeInterval) -> TimeInterval {
        effectNow - gestureNow
    }

    /// 指が `location` に動いた（時刻 `time` は演出の時計の秒、`angle` はそこまでに追従で回した角度の累計）。
    /// 時刻が前の点より前なら前の点の時刻にそろえる。
    mutating func append(time: TimeInterval, location: CGPoint, angle: Double) {
        let previous = points[points.count - 1]
        let time = max(time, previous.time)
        var point = Point(time: time, location: location, angle: angle, velocity: 0)
        points.append(point)
        let raw = rawAngularVelocity(at: time)
        // 前の点から間が空いた（止まり切った）なら止まったところから寄せ直す
        let base = time - previous.time < Config.dragEffectSettleTime ? previous.velocity : 0
        point.velocity = SpinEffectIntensity.smoothed(base, toward: raw, elapsed: time - previous.time)
        points[points.count - 1] = point
        // 演出が引くのは直近（火花の寿命 + 窓）までなので、余裕を持たせて古いものを捨てる。最後の点は残す
        let keepFrom = time - Config.dragEffectHistory
        if let index = points.firstIndex(where: { $0.time >= keepFrom }), index > 0 {
            points.removeFirst(index)
        }
    }

    /// 最後の点の時刻。
    var lastTime: TimeInterval { points[points.count - 1].time }

    /// 時刻 `now` の追従で回した角度（度）。点の間は線形に補い、最初の点より前は最初の点、最後の点より後は最後の点の角度。
    /// 残像は今の角度とこの角度の差でずらす。
    func angle(now: TimeInterval) -> Double {
        guard let next = points.firstIndex(where: { $0.time > now }) else { return points[points.count - 1].angle }
        guard next > 0 else { return points[0].angle }
        let a = points[next - 1], b = points[next]
        let span = b.time - a.time
        guard span > 0 else { return b.angle }
        return a.angle + (b.angle - a.angle) * (now - a.time) / span
    }

    /// 時刻 `now` までの `Config.flickSampleWindow` 秒に中心のまわりを回った角度から求めた角速度（度/秒、平滑する前）。
    /// `now` より後の点は使わない。指を止めると窓の長さをかけて 0 に落ちる。
    func rawAngularVelocity(at now: TimeInterval) -> Double {
        let windowStart = now - Config.flickSampleWindow
        let samples = points
            .filter { $0.time >= windowStart && $0.time <= now }
            .map { FlickSpin.Sample(time: $0.time, location: $0.location) }
        return FlickSpin.angularVelocity(samples: samples, center: center, at: now)
    }

    /// 時刻 `now` の平滑した角速度（度/秒、画面上の時計回りが正）。`now` 以前の最後の点の値から、`now` の平滑する前の値へ
    /// その経過時間ぶん寄せる（`now` より後の点は使わないので、過ぎた時刻の値は後から点が増えても変わらない）。
    /// 最初の点より前と、最後に点を記録してから `Config.dragEffectSettleTime` 以上たったら 0（止まり切った）。
    func angularVelocity(now: TimeInterval) -> Double {
        guard let index = points.lastIndex(where: { $0.time <= now }) else { return 0 }
        let point = points[index]
        guard now - point.time < Config.dragEffectSettleTime else { return 0 }
        return SpinEffectIntensity.smoothed(point.velocity, toward: rawAngularVelocity(at: now), elapsed: now - point.time)
    }

    /// 時刻 `now` の演出の強さ（0...1）。
    func intensity(now: TimeInterval) -> Double {
        SpinEffectIntensity.intensity(angularVelocity: angularVelocity(now: now))
    }

    /// 時刻 `now` に演出がまだ動いているか。最後に指が動いてから `Config.dragEffectSettleTime` の間（角速度が 0 へ落ち切る・
    /// 最後に生まれた火花が消えるまで）。指を離したあとも、離した動きの残りはこの間だけ描く。
    func isMoving(now: TimeInterval) -> Bool {
        now < lastTime + Config.dragEffectSettleTime
    }

    /// 時刻 `now` から演出が止まり切るまでの残りの秒。止まっていれば 0。
    func remaining(now: TimeInterval) -> TimeInterval {
        max(lastTime + Config.dragEffectSettleTime - now, 0)
    }
}

/// 速さに連動する演出が毎フレーム引く盤面の動き。盤面が自分で回る動き（スピン・惰性）か、指で動かしている動き。
/// 項目・指定・印は持たない。
enum WheelEffectMotion: Equatable, Sendable {
    case spin(TimedSpinMotion)
    case drag(WheelDragMotion)

    /// 時刻 `now` に演出が引く動き。盤面が自分で回っている間はその動き、そうでなく指で動かした動きが残っていればそれ、
    /// どちらでもなければ止まり切った惰性（角度だけ引く）。どれも無ければ nil。
    /// ただし、スピン・惰性が指の動きの最後の点より後に始まったら（指を離して惰性・スピンに移った）、止まり切ったあとも
    /// そちらを引く（短い惰性が止まり切ったあとに、それより前の指の動きの残りへ戻らない）。
    /// ドラッグを始めると惰性は止まる（`RouletteModel.stopCoast`）ので、ふつうは同時に動いていない。
    static func current(spin: TimedSpinMotion?, drag: WheelDragMotion?, now: TimeInterval) -> WheelEffectMotion? {
        if let spin, spin.isMoving(now: now) { return .spin(spin) }
        if let drag, drag.isMoving(now: now), !(spin.map { $0.start >= drag.lastTime } ?? false) { return .drag(drag) }
        return spin.map(WheelEffectMotion.spin)
    }

    /// 時刻 `now` に `effect` がまだ動いていて、毎フレーム描き直す必要があるか。`settled` は View が止まり切ったと記録した動き
    /// （止まり切った惰性・指の動きは親が描き直さないので、View が残り時間だけ待って記録し、描き直させる）で、同じなら止まっているとみなす。
    static func isMoving(_ effect: WheelEffectMotion?, settled: WheelEffectMotion?, now: TimeInterval) -> Bool {
        guard let effect, effect != settled else { return false }
        return effect.isMoving(now: now)
    }

    /// 時刻 `now` の角度（度）。スピン・惰性は累積回転角、ドラッグは追従で回した角度の累計。残像のずらし（差）に使う。
    func angle(now: TimeInterval) -> Double {
        switch self {
        case let .spin(motion): motion.angle(now: now)
        case let .drag(motion): motion.angle(now: now)
        }
    }

    /// 時刻 `now` に盤面に見えている角度（度）。スピン・惰性は動きの角度に追従の角度を足したもの、
    /// ドラッグは `rotation + dragRotation`（盤面の `rotationEffect` と同じ）。
    func displayedAngle(now: TimeInterval, rotation: Double, dragRotation: Double) -> Double {
        switch self {
        case let .spin(motion): motion.angle(now: now) + dragRotation
        case .drag: rotation + dragRotation
        }
    }

    /// 時刻 `now` の角速度（度/秒、画面上の時計回りが正）。
    func angularVelocity(now: TimeInterval) -> Double {
        switch self {
        case let .spin(motion): motion.angularVelocity(now: now)
        case let .drag(motion): motion.angularVelocity(now: now)
        }
    }

    /// 時刻 `now` の演出の強さ（0...1）。
    func intensity(now: TimeInterval) -> Double {
        switch self {
        case let .spin(motion): motion.intensity(now: now)
        case let .drag(motion): motion.intensity(now: now)
        }
    }

    /// 時刻 `now` に演出がまだ動いているか（毎フレーム描き直す必要があるか）。
    func isMoving(now: TimeInterval) -> Bool {
        switch self {
        case let .spin(motion): motion.isMoving(now: now)
        case let .drag(motion): motion.isMoving(now: now)
        }
    }

    /// 時刻 `now` から止まり切るまでの残りの秒。
    func remaining(now: TimeInterval) -> TimeInterval {
        switch self {
        case let .spin(motion): motion.remaining(now: now)
        case let .drag(motion): motion.remaining(now: now)
        }
    }
}
