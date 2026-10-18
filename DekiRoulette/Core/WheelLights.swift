import Foundation

/// 2D の盤面の外周に並べる電飾（`docs/SPEC.md` の §5.5）の、時刻と回転角 → 電球ごとの明るさ。
/// 電球は回らない層に `Config.wheelLightCount` 個、12 時から時計回りに等間隔に並べる（添字 0 が 12 時）。
/// 入力は盤面の角度・演出の強さ・停止からの経過時間だけで、項目・指定（`targetId`）・印・止まったスライスは受け取らない。
enum WheelLights {
    /// 点いた光の並びの間隔（何個おきに明るいか）。
    static let litStride = 3

    // MARK: 明るさ（0...1。描画で電球の色の不透明度にする）

    /// 光の並びの間の電球（流れている最中も含めて常に弱く点ける）。
    static let baseLevel = 0.3
    /// 光の並びの電球の明るさ。止まっている（強さ 0）ときはこれで、強さに比例して `litPeakLevel` まで上げる。
    static let litLevel = 0.6
    static let litPeakLevel = 1.0
    /// 動きを減らす設定で点けたままにする明るさ（全灯で一定）。
    static let stillLevel = 0.6
    /// 停止の瞬間の点滅の暗いとき・明るいとき。明るさを抑えるため、明るいときも 1 にしない。
    static let blinkLowLevel = 0.25
    static let blinkHighLevel = 0.85
    /// 結果表示中の脈動の明るいとき（暗いときは `blinkLowLevel` で、点滅の終わりからそのままつながる）。
    static let afterglowHighLevel = 0.7

    /// 停止の瞬間の点滅の長さ（秒）。明るいところから始めて `Config.wheelLightBlinkCount` 回目の明るいところのあと、
    /// 半周期で暗いところに下りて終える（0.6 秒 × 1.5 = 0.9 秒）。過ぎたら結果表示中の脈動に移る。
    static var blinkDuration: TimeInterval { Config.wheelLightBlinkPeriod * (Double(Config.wheelLightBlinkCount) - 0.5) }

    /// 電飾の場面。
    enum Scene: Equatable, Sendable {
        /// 動きを減らす設定。全灯を一定の明るさで点けたまま動かさない。
        case still
        /// 待機中・回転中・指で動かしている間。盤面の累積回転角（度）から光の並びの位置を決め、強さ（0...1）で明るさとにじみを上げる。
        /// 待機中は角度が変わらず強さが 0 なので、弱く点けたまま流れない。
        case running(angle: Double, intensity: Double)
        /// 結果表示中。停止からの経過時間（秒）で、全灯の点滅から脈動に移る。
        case stopped(elapsed: TimeInterval)
    }

    /// 1 個の電球の見え方。
    struct Bulb: Equatable, Sendable {
        /// 明るさ（0...1）。
        var brightness: Double
        /// にじみ（光のぼかし）の強さ（0...1）。
        var glow: Double
    }

    /// 電球 `index` を置く盤面上の角度（度、12 時を 0 として時計回り）。
    static func angle(index: Int, count: Int = Config.wheelLightCount) -> Double {
        guard count > 0 else { return 0 }
        return Double(index) * 360 / Double(count)
    }

    /// 画面の状態から場面を決める。`stoppedElapsed` は結果を出している間だけ停止からの経過時間を渡す（結果が無い・指で動かして強調を解いたら nil）。
    static func scene(reduceMotion: Bool, angle: Double, intensity: Double, stoppedElapsed: TimeInterval?) -> Scene {
        if reduceMotion { return .still }
        if let stoppedElapsed { return .stopped(elapsed: stoppedElapsed) }
        return .running(angle: angle, intensity: min(max(intensity, 0), 1))
    }

    /// 描き直しの最短間隔（秒）。nil なら毎フレーム。盤面が自分で回っている間と停止の点滅の間は毎フレーム、
    /// 点滅が終わって脈動だけになったら `Config.effectPulseFrameInterval` に落として負荷を下げる（ゆっくりした脈動なので段差は見えない）。
    /// `stoppedElapsed` は結果を出している間の停止からの経過（秒）。
    static func frameInterval(moving: Bool, stoppedElapsed: TimeInterval?) -> TimeInterval? {
        guard !moving, let stoppedElapsed, stoppedElapsed >= blinkDuration else { return nil }
        return Config.effectPulseFrameInterval
    }

    /// 毎フレーム描き直す必要があるか（`TimelineView` を止める条件の反対）。動きを減らす設定では描き直さない。
    /// 盤面が自分で回っている間と、結果表示中（点滅と脈動）だけ描き直す。待機中・止まり切った惰性・指で動かしている間は
    /// 角度が変わったときに親の描き直しで足りるので止める。
    static func animates(reduceMotion: Bool, moving: Bool, showingResult: Bool) -> Bool {
        !reduceMotion && (moving || showingResult)
    }

    /// 光の並びの位置（電球の個数の単位）。盤面の累積回転角に比例するので、角速度に比例して流れ、減速に合わせてテンポが落ち、止まれば止まる。
    /// 時計回り（角度が増える）なら増え、並びは添字の大きい方（時計回り）へ流れる。
    static func phase(angle: Double, count: Int = Config.wheelLightCount) -> Double {
        guard count > 0, angle.isFinite else { return 0 }
        return angle * Config.wheelLightFlowFactor / (360 / Double(count))
    }

    /// 光の並びを流す角度。ふつうは盤面の累積回転角と同じだけ進めるが、1 回に進める量を、並びが 1 フレームに
    /// `Config.wheelLightMaxFlowPerFrame` 個（電球の個数）を超えないように抑える。速く回すと並びは盤面より遅れて流れ、
    /// 上限を下回る速さに落ちたら盤面と同じだけ進む（止まれば止まる）。並びの位置は `phase(angle:)` にこの角度を渡す。
    /// 1 回に進める量は、前に進めてからの経過時間 × `Config.effectReferenceFrameInterval` あたりの上限と、1 回あたりの上限の小さい方。
    /// 同じフレームに 2 回描き直されても（親の描き直しと `TimelineView`）合わせて上限に収まる。
    /// 盤面の角度の差だけを足すので、描き直しの回数に依らず、遅れが無ければ盤面の角度と同じになる。
    struct Flow: Equatable, Sendable {
        /// 流す角度（度）。まだ一度も進めていなければ nil。
        private(set) var angle: Double?
        private var boardAngle = 0.0
        private var time: TimeInterval = 0

        init() {}

        /// 盤面の累積回転角が時刻 `time`（秒）に `boardAngle` になった。流す角度を進めて返す。
        /// 最初の 1 回は盤面の角度そのものから始める。
        mutating func advance(to boardAngle: Double, at time: TimeInterval, count: Int = Config.wheelLightCount) -> Double {
            guard let current = angle, boardAngle.isFinite, time.isFinite else {
                let start = boardAngle.isFinite ? boardAngle : 0
                angle = start
                self.boardAngle = start
                self.time = time
                return start
            }
            let limit = WheelLights.maxFlowAngle(elapsed: time - self.time, count: count)
            let next = current + min(max(boardAngle - self.boardAngle, -limit), limit)
            angle = next
            self.boardAngle = boardAngle
            self.time = max(time, self.time)
            return next
        }
    }

    /// 経過時間 `elapsed`（秒）の間に光の並びを流してよい角度（盤面の角度の度）。並びが進む電球の個数で
    /// `Config.wheelLightMaxFlowPerFrame` 個を 1 フレーム（`Config.effectReferenceFrameInterval`）あたりの上限とし、
    /// 経過時間に比例させて、1 回には 1 フレーム分までにする。時間が戻ったら 0。
    static func maxFlowAngle(elapsed: TimeInterval, count: Int = Config.wheelLightCount) -> Double {
        guard count > 0, elapsed > 0 else { return 0 }
        let frames = min(elapsed / Config.effectReferenceFrameInterval, 1)
        let bulbs = Config.wheelLightMaxFlowPerFrame * frames
        return bulbs * (360 / Double(count)) / Config.wheelLightFlowFactor
    }

    /// 電球 `index` が光の並びにどれだけ重なっているか（0...1）。並びの位置ちょうどで 1、隣との中間で 0.5 ずつに分け、
    /// `litStride` 個おきに繰り返す（並びが動くと隣の電球へ滑らかに移る）。
    static func chase(index: Int, phase: Double) -> Double {
        let stride = Double(litStride)
        let offset = (Double(index) - phase).truncatingRemainder(dividingBy: stride)
        let wrapped = offset < 0 ? offset + stride : offset
        let distance = min(wrapped, stride - wrapped)
        return max(0, 1 - distance)
    }

    /// 停止の瞬間の全灯の点滅の明るさ。明るいところから始めて `Config.wheelLightBlinkCount` 回明るくし、暗いところで終える。
    /// 1 回目の明るいところは停止の瞬間で、画面のフラッシュ（`WheelStopEffects.flashOpacity`）と重ねて 1 回の明滅に数える
    /// （フラッシュと点滅を合わせても 1 秒の間の明滅は 2 回まで）。点滅の長さを過ぎたら nil（脈動に移る）。始まる前（0 未満）は明るいとき。
    static func stopBlink(at elapsed: TimeInterval) -> Double? {
        guard elapsed < blinkDuration else { return nil }
        let t = max(elapsed, 0)
        let wave = 0.5 + 0.5 * cos(2 * .pi * t / Config.wheelLightBlinkPeriod)
        return blinkLowLevel + (blinkHighLevel - blinkLowLevel) * wave
    }

    /// 点滅のあとの脈動の明るさ。`elapsed` は点滅が終わってからの秒で、暗いとき（点滅の終わりと同じ明るさ）から
    /// 周期 `Config.wheelLightAfterglowPeriod` でゆっくり明るくなって戻るのを繰り返す。
    static func afterglow(at elapsed: TimeInterval) -> Double {
        let t = max(elapsed, 0)
        let wave = 0.5 - 0.5 * cos(2 * .pi * t / Config.wheelLightAfterglowPeriod)
        return blinkLowLevel + (afterglowHighLevel - blinkLowLevel) * wave
    }

    /// 結果表示中の全灯の明るさ。停止から `blinkDuration` までは点滅、そのあとは脈動。
    static func stopped(at elapsed: TimeInterval) -> Double {
        stopBlink(at: elapsed) ?? afterglow(at: elapsed - blinkDuration)
    }

    /// 電球 `index` の見え方。
    static func bulb(index: Int, count: Int = Config.wheelLightCount, scene: Scene) -> Bulb {
        switch scene {
        case .still:
            return Bulb(brightness: stillLevel, glow: 0)
        case let .running(angle, intensity):
            let lit = chase(index: index, phase: phase(angle: angle, count: count))
            let peak = litLevel + (litPeakLevel - litLevel) * intensity
            return Bulb(brightness: baseLevel + (peak - baseLevel) * lit, glow: lit * intensity)
        case let .stopped(elapsed):
            let brightness = stopped(at: elapsed)
            let glow = (brightness - blinkLowLevel) / (blinkHighLevel - blinkLowLevel)
            return Bulb(brightness: brightness, glow: min(max(glow, 0), 1))
        }
    }
}
