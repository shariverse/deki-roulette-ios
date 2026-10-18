import Foundation

/// 区間（`SpinMotion`）をつないだ盤面の動き。止まり際の焦らし（`SpinTease`）では時刻 → 累積角が単調でない（戻る）ので、
/// 1 本の曲線では表せず、区間ごとに単調な曲線をつなぐ。区間は時刻順で、前の区間の `to` が次の区間の `from` になる。
/// 焦らしの無いスピンは区間 1 つ（今の `SpinMotion` と同じ角度）。
///
/// 2D・3D の盤面・回転音・触覚が同じ時刻に同じ角度になるよう、描画（`TimelineView` で `angle(at:)` を引く・区間ごとの補間）と
/// 境目を越える時刻（`boundaryCrossings(count:minInterval:)`）はどちらもこの区間の列から求める。項目・指定・印は持たない。
struct SpinPath: Hashable, Sendable {
    /// 時刻順の区間。空にはしない。
    let segments: [SpinMotion]
    /// 入れた焦らしの入り方。焦らしの無い動きは nil。
    let tease: SpinTease?

    init(segments: [SpinMotion], tease: SpinTease? = nil) {
        precondition(!segments.isEmpty)
        self.segments = segments
        self.tease = tease
    }

    /// 区間 1 つの動き（焦らしなし）。
    init(_ motion: SpinMotion) {
        self.init(segments: [motion])
    }

    /// まだ回していないときの動き。`Config.spinDuration` 秒・`Config.spinEasing` の、回らない区間 1 つ。
    static let idle = SpinPath(SpinMotion(from: 0, to: 0, duration: Config.spinDuration, easing: Config.spinEasing))

    /// 回り始めの累積回転角（度）。
    var from: Double { segments[0].from }

    /// 止まる累積回転角（度）。最後の区間の `to`。
    var to: Double { segments[segments.count - 1].to }

    /// 全体の長さ（秒）。区間の長さの和。
    var duration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }

    /// 完了の保険のタイマーの長さ（秒）。全体の長さの 0.6 秒後（`Config.spinFallback` と同じ余裕）。
    /// 焦らしの有無（`tease`）ではなく長さから決めるので、焦らしを入れられずに 1 本の曲線になったスピンでも取り違えない。
    var fallback: TimeInterval { duration + (Config.spinFallback - Config.spinDuration) }

    /// 各区間が始まる時刻（開始からの秒）。`segments` と同じ並び。
    var startTimes: [TimeInterval] {
        var times: [TimeInterval] = []
        var start: TimeInterval = 0
        for segment in segments {
            times.append(start)
            start += segment.duration
        }
        return times
    }

    /// 開始から `elapsed` 秒後の累積回転角（度）。始まる前は `from`、長さを過ぎたら `to` で止める。
    /// 区間のつなぎ目では後の区間の始点（前の区間の終点と同じ角度）を返す。
    func angle(at elapsed: TimeInterval) -> Double {
        if elapsed <= 0 { return from }
        var start: TimeInterval = 0
        for segment in segments {
            if elapsed < start + segment.duration {
                return segment.angle(at: elapsed - start)
            }
            start += segment.duration
        }
        return to
    }

    /// 開始から `elapsed` 秒後の進み具合。`(angle(at:) - from) / (to - from)` で、始点で 0、止まったら 1。
    /// 焦らしでは途中で戻ったり（行き過ぎでは）1 を超えたりする。SwiftUI の補間（`SpinPathAnimation`）が、
    /// 補間する値の差をこの割合で縮めて今の値にする。回らない動き（`to == from`）は常に 1。
    func progress(at elapsed: TimeInterval) -> Double {
        guard to != from else { return 1 }
        return (angle(at: elapsed) - from) / (to - from)
    }

    /// 開始から `elapsed` 秒後の角速度（度/秒、累積回転角が増える向きが正）。範囲外は 0。
    /// 焦らしの区間は始点・終点の傾きが 0 の曲線なので、つなぎ目ではどちらの区間で測っても 0 になる。
    func angularVelocity(at elapsed: TimeInterval) -> Double {
        guard elapsed >= 0, elapsed <= duration else { return 0 }
        var start: TimeInterval = 0
        for segment in segments {
            if elapsed <= start + segment.duration {
                return segment.angularVelocity(at: elapsed - start)
            }
            start += segment.duration
        }
        return 0
    }

    /// 開始から `elapsed` 秒後の演出の強さ（0...1）。
    func intensity(at elapsed: TimeInterval) -> Double {
        SpinEffectIntensity.intensity(angularVelocity: angularVelocity(at: elapsed))
    }

    /// 針の下のスライス（件数 `count`）が切り替わる時刻（開始からの秒）を昇順で返す。区間ごとに単調な曲線を
    /// `SpinTicks.boundaryCrossings` と同じ逆算で数えてつなぐので、戻る向きに越えた境目も数える。
    /// 直前に残した時刻から `minInterval` 未満しか離れていないものは、区間をまたいで全体で間引く。
    /// 区間 1 つなら `SpinTicks.boundaryCrossings` / `HapticSchedule.boundaryCrossings` と同じ結果。
    func boundaryCrossings(count: Int, minInterval: TimeInterval) -> [TimeInterval] {
        var times: [TimeInterval] = []
        var lastKept = -Double.infinity
        var start: TimeInterval = 0
        for segment in segments {
            let crossings = SpinTicks.boundaryCrossings(
                from: segment.from, to: segment.to, count: count,
                duration: segment.duration, easing: segment.easing, minInterval: 0
            )
            for crossing in crossings {
                let time = start + crossing
                guard time - lastKept >= minInterval else { continue }
                times.append(time)
                lastKept = time
            }
            start += segment.duration
        }
        return times
    }
}

extension SpinTicks {
    /// 区分の動き（焦らしを含むスピン）で回転音を鳴らす時刻。`SpinPath.boundaryCrossings(count:minInterval:)` と同じ。
    static func boundaryCrossings(along path: SpinPath, count: Int, minInterval: TimeInterval) -> [TimeInterval] {
        path.boundaryCrossings(count: count, minInterval: minInterval)
    }
}

extension HapticSchedule {
    /// 区分の動き（焦らしを含むスピン）で触覚を刻む時刻。`SpinPath.boundaryCrossings(count:minInterval:)` と同じ。
    static func boundaryCrossings(along path: SpinPath, count: Int, minInterval: TimeInterval) -> [TimeInterval] {
        path.boundaryCrossings(count: count, minInterval: minInterval)
    }
}
