import Foundation

/// 停止時の決まり音（`Resources/Sounds/chime.wav`。`scripts/make-chime-sound.swift` で合成）を鳴らすかの判定。
/// 仕様は `docs/SPEC.md` の §5.5「効果音」。指定（`targetId`）・印・結果のラベルは受け取らない（どの結果でも同じ規則で鳴らす）。
/// 動きを減らす設定でも鳴らすので、その有無も受け取らない。
enum StopChime {
    /// 盤面が止まった動き。
    enum Stop: Sendable {
        /// 抽選したスピン（ボタン・フリック）が止まって結果が出た。保険のタイマーで完了した場合も含む。
        case spin
        /// 勢いの足りないフリックのあとの惰性が止まった（抽選しない）。
        case coast
    }

    /// 演出の効果音（`SpinEffects.sounds`）と設定の「効果音」が両方 ON で、抽選したスピンが止まったときだけ鳴らす。
    static func plays(effects: SpinEffects, soundEnabled: Bool, stop: Stop) -> Bool {
        guard effects.sounds, soundEnabled else { return false }
        return switch stop {
        case .spin: true
        case .coast: false
        }
    }
}
