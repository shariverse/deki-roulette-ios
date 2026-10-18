import Foundation

/// 2D の盤面の停止の瞬間のフラッシュと、結果表示中の止まったスライスの光彩の余韻（`docs/SPEC.md` の §5.5）の、
/// 停止からの経過時間 → 強さ。「スピンの演出」が「なし」以外（`SpinEffectStyle.showsCommonEffects`）のときだけ使う。
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

    /// フラッシュを描くか。演出が「なし」・動きを減らす設定・結果が無いときは描かない。
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

    /// 光彩を脈打たせるか。演出が「なし」・動きを減らす設定・結果が無い（指で動かして強調を解いた・次のスピン・結果が消えた）ときは
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
