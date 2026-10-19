import Foundation

/// 止まり際の焦らしの入り方（`docs/SPEC.md` の §5.5「焦らし」）。最終角（止まる累積角）は変えず、止まる手前の動きだけを変える。
/// 入り方は乱数だけで選び、振れ幅は件数（スライス幅）と最終角の幾何だけから決める。指定（`targetId`）・止まるスライスの添字は受け取らない。
enum SpinTease: String, CaseIterable, Sendable {
    /// ためらい: 止まるスライスに入る境目の手前（止まる角度が境目から遠いときは止まる角度の手前）でほとんど止まりそうになってから、
    /// ゆっくり進んで止まる。
    case hesitate
    /// 戻りかけ: 境目の手前（止まる角度が境目から遠いときは止まる角度の手前）で止まりかけ、一度わずかに戻ってから進んで止まる。
    case rollBack
    /// 行き過ぎ: 止まる角度を少し行き過ぎてから戻って止まる（隣のスライスに入ることがある）。
    case overshoot

    /// 入り方を等確率で選ぶ。乱数は 1 回だけ引く。
    static func random<G: RandomNumberGenerator>(using rng: inout G) -> SpinTease {
        allCases[Int.random(in: 0..<allCases.count, using: &rng)]
    }
}

extension SpinPath {
    /// スピン（ボタン・フリック）の動き。累積角 `from` から `to`（`RouletteMath.nextRotation` が決めたもの）へ回す。
    /// `effects.tease` が偽なら焦らしを入れず、今の `SpinMotion`（`Config.spinDuration`・`spinEasing`。
    /// フリックでは `FlickSpin.easing`）と同じ区間 1 つで、乱数は引かない。
    /// 真なら `SpinTease.random(using:)` で入り方を選んで `teased(_:from:to:count:releaseVelocity:)` にする（長さは入り方に依らず
    /// `Config.spinDuration + Config.spinTeaseDuration`）。`accessibilityReduceMotion` では回さないので、呼び出し側が使わない。
    /// `releaseVelocity` はフリックの指を離した瞬間の角速度（度/秒）。主の区間の初速をそれに合わせる。
    static func spin<G: RandomNumberGenerator>(
        from: Double, to: Double, count: Int, effects: SpinEffects,
        releaseVelocity: Double? = nil, using rng: inout G
    ) -> SpinPath {
        guard effects.tease else {
            return plain(from: from, to: to, duration: Config.spinDuration, releaseVelocity: releaseVelocity)
        }
        let tease = SpinTease.random(using: &rng)
        return teased(tease, from: from, to: to, count: count, releaseVelocity: releaseVelocity)
    }

    static func spin(
        from: Double, to: Double, count: Int, effects: SpinEffects, releaseVelocity: Double? = nil
    ) -> SpinPath {
        var rng = SystemRandomNumberGenerator()
        return spin(from: from, to: to, count: count, effects: effects, releaseVelocity: releaseVelocity, using: &rng)
    }

    /// 入り方 `tease` の焦らしを入れたスピン。区間は次のとおりで、全体は `Config.spinDuration + Config.spinTeaseDuration`。
    ///
    /// 回る向きを正にした角度 u（反時計回りは符号を反転）で、止まる角 u1 の直前の境目（スライス幅の倍数で u1 以下の最大）を B、
    /// 手前の距離を a（`spinTeaseApproach…`）とすると:
    /// - ためらい: 主の区間で h まで → 焦らしの曲線で u1 まで（`spinTeaseDuration`）
    /// - 戻りかけ: 主の区間で h まで → h − r まで戻る（`spinTeaseDuration` の `spinTeaseRollBackShare`）→ u1 まで（残り）
    ///
    /// h（止まりかける角度）は B − a と u1 − c（`spinTeaseCreepMax`）の大きい方。止まる角度が境目の近くなら境目の手前で
    /// 止まりかけ、遠ければ止まる角度の c 手前で止まりかける（焦らしの区間で進む距離を c までに抑える）。
    /// - 行き過ぎ: 主の区間で u1 + o まで → u1 まで戻る（`spinTeaseDuration`）
    ///
    /// 主の区間は `Config.spinDuration` 秒で、曲線は `Config.spinEasing`（フリックでは主の区間の距離で求めた `FlickSpin.easing`。
    /// 回り始めの角度・初速は焦らしの無いスピンと同じ）。焦らしの区間は `Config.spinTeaseEasing` で、つなぎ目は角速度 0 でつながる。
    /// 回る距離が短くて主の区間の行き先が始点より手前になるとき（スライス 1 つ分も回らないスピン。`nextRotation` は 4 周以上回すので
    /// スピンでは起きない）は、焦らしを入れずに同じ長さで `from` から `to` へ 1 本の曲線で回す（`tease` は nil）。
    static func teased(
        _ tease: SpinTease, from: Double, to: Double, count: Int, releaseVelocity: Double? = nil
    ) -> SpinPath {
        let total = Config.spinDuration + Config.spinTeaseDuration
        guard count > 0, to != from else {
            return plain(from: from, to: to, duration: total, releaseVelocity: releaseVelocity)
        }
        let sign: Double = to > from ? 1 : -1
        let start = sign * from
        let stop = sign * to
        let slice = 360.0 / Double(count)
        let boundary = (stop / slice).rounded(.down) * slice
        let approach = min(slice * Config.spinTeaseApproachFraction, Config.spinTeaseApproachMax)
        // ためらい・戻りかけで止まりかける角度。止まる角度が境目から遠い（広いスライスの奥で止まる）ときに境目の手前で止めると、
        // 焦らしの区間で半周近くを加速し直して回ってしまうので、焦らしの区間で進む距離を `spinTeaseCreepMax` までに抑える
        // （そのときは境目を主の区間で越え、止まる角度の手前でためらう）
        let hesitation = max(boundary - approach, stop - Config.spinTeaseCreepMax)

        let mainEnd: Double
        var tail: [(angle: Double, duration: TimeInterval)]
        switch tease {
        case .hesitate:
            mainEnd = hesitation
            tail = [(stop, Config.spinTeaseDuration)]
        case .rollBack:
            mainEnd = hesitation
            let back = min(slice * Config.spinTeaseRollBackFraction, Config.spinTeaseRollBackMax)
            let backDuration = Config.spinTeaseDuration * Config.spinTeaseRollBackShare
            tail = [(mainEnd - back, backDuration), (stop, Config.spinTeaseDuration - backDuration)]
        case .overshoot:
            mainEnd = stop + min(slice * Config.spinTeaseOvershootFraction, Config.spinTeaseOvershootMax)
            tail = [(stop, Config.spinTeaseDuration)]
        }
        guard mainEnd > start else {
            return plain(from: from, to: to, duration: total, releaseVelocity: releaseVelocity)
        }

        let mainEasing = easing(distance: mainEnd - start, duration: Config.spinDuration, releaseVelocity: releaseVelocity)
        var segments = [SpinMotion(from: from, to: sign * mainEnd, duration: Config.spinDuration, easing: mainEasing)]
        var current = mainEnd
        for (angle, duration) in tail {
            segments.append(SpinMotion(
                from: sign * current, to: sign * angle, duration: duration, easing: Config.spinTeaseEasing
            ))
            current = angle
        }
        // 最後の区間の終点は丸めずに `to` そのものにする（符号の反転は正確だが、念のため最終角を書き戻す）
        let last = segments.removeLast()
        segments.append(SpinMotion(from: last.from, to: to, duration: last.duration, easing: last.easing))
        return SpinPath(segments: segments, tease: tease)
    }

    /// 焦らしの無い 1 本の曲線の動き。`releaseVelocity` があれば初速を合わせる（今の `RouletteModel.beginSpin` と同じ）。
    private static func plain(
        from: Double, to: Double, duration: TimeInterval, releaseVelocity: Double?
    ) -> SpinPath {
        SpinPath(SpinMotion(
            from: from, to: to, duration: duration,
            easing: easing(distance: abs(to - from), duration: duration, releaseVelocity: releaseVelocity)
        ))
    }

    private static func easing(distance: Double, duration: TimeInterval, releaseVelocity: Double?) -> CubicBezierCurve {
        guard let releaseVelocity else { return Config.spinEasing }
        return FlickSpin.easing(angularVelocity: releaseVelocity, distance: distance, duration: duration)
    }
}
