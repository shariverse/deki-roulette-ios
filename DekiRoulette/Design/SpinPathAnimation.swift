import SwiftUI

/// 区間をつないだ動き（`SpinPath`）で補間するアニメーション。止まり際の焦らしは角度が戻る（行き過ぎでは止まる角度を越える）ので
/// 1 本の `timingCurve` では表せず、経過時間ごとに `SpinPath.progress(at:)` の割合で値の差を縮める。
/// 2D の `rotationEffect` と 3D の `Wheel3DSurface.animatableData` は同じトランザクションでこれを受けるので、同じ時刻に同じ角度になる。
/// 回転音・触覚の時刻（`SpinPath.boundaryCrossings`）と電飾が引く角度（`TimedSpinMotion`）も同じ区間の列から求める。
struct SpinPathAnimation: CustomAnimation {
    let path: SpinPath

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < path.duration else { return nil }
        return value.scaled(by: path.progress(at: time))
    }
}
