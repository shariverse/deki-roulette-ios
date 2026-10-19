import Foundation

/// 2D の盤面の停止の瞬間のフラッシュと、結果表示中の止まったスライスの光彩の余韻（`docs/SPEC.md` の §5.5）の、
/// 停止からの経過時間 → 強さ。停止の演出（`SpinEffects.stopEffects`）が ON のときだけ使う。
/// 入力は停止からの経過時間・演出を出すか・動きを減らす設定だけで、項目・指定（`targetId`）・印・止まったスライスは受け取らない
/// （余韻を付けるスライスは描く側が止まったスライス（`SpinOutcome`）から決め、強さはどのスライスでも同じ）。
enum WheelStopEffects {
    // MARK: フラッシュ

    /// フラッシュのいちばん明るいとき（停止の瞬間）の不透明度。光過敏に配慮して明るさを抑える。
    static let flashPeakOpacity = 0.25

    /// 停止からの経過 `elapsed`（秒）のフラッシュの不透明度。停止の瞬間に `flashPeakOpacity` で光り、
    /// `Config.stopFlashDuration` で 0 まで 2 次の ease-out で消える（1 回だけ）。停止の前・消えたあとは 0。
    static func flashOpacity(at elapsed: TimeInterval) -> Double {
        guard elapsed >= 0, elapsed < Config.stopFlashDuration else { return 0 }
        let remaining = 1 - elapsed / Config.stopFlashDuration
        return flashPeakOpacity * remaining * remaining
    }

    /// フラッシュを描くか。停止の演出が OFF・動きを減らす設定・結果が無いときは描かない。
    static func flashes(enabled: Bool, reduceMotion: Bool, elapsed: TimeInterval?) -> Bool {
        guard enabled, !reduceMotion, let elapsed else { return false }
        return flashOpacity(at: elapsed) > 0
    }

    // MARK: 余韻

    /// 余韻の光彩のいちばん弱いときの倍率（光彩の不透明度に掛ける）。いちばん強いときは 1（今の光彩のまま）。
    static let afterglowLowLevel = 0.4

    /// 余韻の脈動の波（0...1）。周期 `Config.wheelLightAfterglowPeriod` で、電飾の脈動（`WheelLights.afterglow`）と
    /// 同じ位相にする（電飾の点滅が終わる `WheelLights.blinkDuration` で 0、その半周期後に 1）。`elapsed` は停止からの秒。
    static func afterglowWave(at elapsed: TimeInterval) -> Double {
        let t = max(elapsed, 0) - WheelLights.blinkDuration
        return 0.5 - 0.5 * cos(2 * .pi * t / Config.wheelLightAfterglowPeriod)
    }

    /// 停止からの経過 `elapsed`（秒）の光彩の倍率（`afterglowLowLevel`...1）。
    static func afterglowLevel(at elapsed: TimeInterval) -> Double {
        afterglowLowLevel + (1 - afterglowLowLevel) * afterglowWave(at: elapsed)
    }

    /// 光彩を脈打たせるか。停止の演出が OFF・動きを減らす設定・結果が無い（指で動かして強調を解いた・次のスピン・結果が消えた）ときは
    /// 脈打たせない（光彩は今のまま）。
    static func pulses(enabled: Bool, reduceMotion: Bool, showingResult: Bool) -> Bool {
        enabled && !reduceMotion && showingResult
    }

    /// 光彩の倍率。脈打たせないとき（`stoppedElapsed` が nil を含む）は 1 で、今の光彩と同じ。
    static func glowLevel(enabled: Bool, reduceMotion: Bool, stoppedElapsed: TimeInterval?) -> Double {
        guard let stoppedElapsed, pulses(enabled: enabled, reduceMotion: reduceMotion, showingResult: true) else { return 1 }
        return afterglowLevel(at: stoppedElapsed)
    }
}

// MARK: 毎フレームの値

extension WheelStopEffects {
    /// 停止の演出の 1 フレーム。2D の `WheelStopFlashView` と 3D の `Wheel3DScene.stopEffects(_:)` が同じ時計（`RouletteModel.now`）から
    /// 共有の `WheelStopEffectsTimeline` で引く。
    struct Frame: Equatable, Sendable {
        /// フラッシュの不透明度（0 なら描かない）。
        var flashOpacity = 0.0
        /// 止まったスライスの光彩の倍率（1 なら今の光彩のまま）。
        var glowLevel = 1.0

        /// 何も足さない（停止の演出が OFF・動きを減らす設定・結果が無いとき）。
        static let none = Frame()
    }

    /// 時刻 `now` の 1 フレーム。`flashStart` はフラッシュを始めた時刻（停止の瞬間を見たときだけ。指で強調を解いても止めない）、
    /// `afterglowStart` は余韻の基準の時刻（結果を出していて強調している間だけ）。停止の演出が OFF・動きを減らす設定では `none`。
    static func frame(
        enabled: Bool, reduceMotion: Bool, flashStart: TimeInterval?, afterglowStart: TimeInterval?, now: TimeInterval
    ) -> Frame {
        guard enabled, !reduceMotion else { return .none }
        return Frame(
            flashOpacity: flashStart.map { flashOpacity(at: now - $0) } ?? 0,
            glowLevel: glowLevel(enabled: true, reduceMotion: false, stoppedElapsed: afterglowStart.map { now - $0 })
        )
    }

    /// 描き直しの最短間隔。フラッシュが光っている間は毎フレーム（nil）、余韻の脈動だけなら `Config.effectPulseFrameInterval`。
    static func frameInterval(flashing: Bool) -> TimeInterval? {
        flashing ? nil : Config.effectPulseFrameInterval
    }
}

// MARK: 停止の時刻

/// 結果が出た時刻（停止の時刻）の持ち方（`docs/SPEC.md` の §5.5）。2D の `RouletteWheelView` と 3D の `Wheel3DView` が同じ規則で
/// `@State` に持ち、電飾の点滅と脈動・光彩の余韻・フラッシュ・紙吹雪に渡す時刻を同じ関数（`cues`）で引く。
/// 入力は結果が出ているか（止まったスライスの添字の有無）・時刻だけで、指定（`targetId`）・印は受け取らない。
struct WheelStopMoment: Equatable, Sendable {
    /// 結果が出た時刻（`RouletteModel.now` の秒）。結果が無いときは nil。
    private(set) var start: TimeInterval?
    /// 停止の瞬間を画面で見たか。結果を出したまま盤面が画面に出た（2D と 3D を切り替えた・画面に戻った）ときは偽で、
    /// フラッシュと紙吹雪を出さない。
    private(set) var witnessed = false

    /// 盤面が画面に出た。結果を出したままなら、停止の瞬間の点滅とフラッシュを飛ばして脈動から始める
    /// （`WheelLights.blinkDuration` だけ前に止まったことにする）。すでに時刻を持っていれば変えない。
    mutating func appear(showingResult: Bool, now: TimeInterval) {
        guard showingResult, start == nil else { return }
        start = now - WheelLights.blinkDuration
        witnessed = false
    }

    /// 結果が出た・消えた（止まったスライスの添字が変わった）。出たらその時刻を停止の時刻にする。
    mutating func resultChanged(showingResult: Bool, now: TimeInterval) {
        start = showingResult ? now : nil
        witnessed = showingResult
    }

    /// 盤面が演出に渡す値。2D と 3D の盤面が同じ引数でこれを呼ぶ。
    /// - Parameters:
    ///   - highlightedIndex: 止まったスライスの添字（`model.outcome?.index`）。
    ///   - displacedByDrag: 結果が出たあとに指で盤面を動かした（強調を解く）。
    func cues(
        effects: SpinEffects, reduceMotion: Bool, highlightedIndex: Int?, displacedByDrag: Bool
    ) -> WheelStopCues {
        let highlight = displacedByDrag ? nil : highlightedIndex
        // 電飾の点滅と脈動・光彩の余韻は、指で動かして強調を解いたら止める
        let emphasized = highlight != nil ? start : nil
        // フラッシュと紙吹雪は結果が出た瞬間に 1 回だけ始めるので、指で強調を解いても止めない。見ていない停止では出さない
        let burst = highlightedIndex != nil && witnessed && !reduceMotion ? start : nil
        return WheelStopCues(
            highlight: highlight,
            lightsStoppedAt: effects.lights ? emphasized : nil,
            afterglowStart: WheelStopEffects.pulses(
                enabled: effects.stopEffects, reduceMotion: reduceMotion, showingResult: highlight != nil
            ) ? emphasized : nil,
            flashStart: effects.stopEffects ? burst : nil,
            confettiStart: effects.particles ? burst : nil
        )
    }
}

/// 盤面が演出に渡す、強調するスライスと停止の時刻（`WheelStopMoment.cues`）。
struct WheelStopCues: Equatable, Sendable {
    /// 強調するスライス。結果が出たあとに指で動かしたら nil（結果の表示は残る）。
    var highlight: Int?
    /// 電飾の点滅と脈動の基準（`WheelLightsTimeline` の `stoppedAt`）。電飾を出さない・強調を解いたら nil。
    var lightsStoppedAt: TimeInterval?
    /// 光彩の余韻の基準。脈打たせないとき（停止の演出が OFF・動きを減らす設定・強調を解いた）は nil。
    var afterglowStart: TimeInterval?
    /// フラッシュを始めた時刻。停止の演出が OFF・動きを減らす設定・見ていない停止では nil。
    var flashStart: TimeInterval?
    /// 紙吹雪がはじけた時刻。紙吹雪を出さない設定・動きを減らす設定・見ていない停止では nil。
    var confettiStart: TimeInterval?
}
