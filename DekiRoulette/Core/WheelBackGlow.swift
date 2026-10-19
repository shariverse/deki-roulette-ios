import Foundation

/// 背景の光の脈動（`docs/SPEC.md` の §5.5「背景の光の脈動」）。盤面の枠の中、外周の縁の外側に柔らかい光を置き、
/// 回転の速さ（電飾と同じ演出の強さ 0...1）に比例して明るくする。止まっているときは消える。
/// 2D の `WheelBackGlowView` と 3D の盤面が同じ関数・同じ時計（`WheelBackGlowTimeline`）から引く。
/// 入力は演出の強さと動きを減らす設定だけで、項目・指定（`targetId`）・印・止まったスライスは受け取らない。
enum WheelBackGlow {
    /// 演出の強さ（0...1）→ 光の不透明度（0...`Config.wheelBackGlowMaxOpacity`）。強さに比例させ、範囲外は端で止める。
    /// 動きを減らす設定では出さない（0）。
    static func opacity(intensity: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion, !intensity.isNaN else { return 0 }
        return Config.wheelBackGlowMaxOpacity * min(max(intensity, 0), 1)
    }

    /// 毎フレーム描き直すか。盤面が自分で回っている・指で動かしている（止まり切るまで）間だけで、待機中・止まり切ったあと・
    /// 動きを減らす設定では止める（光は消えているので描き直さなくてよい）。
    static func animates(reduceMotion: Bool, moving: Bool) -> Bool {
        !reduceMotion && moving
    }
}
