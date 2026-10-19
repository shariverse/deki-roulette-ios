import Foundation

/// スピンに付ける演出の組み合わせ。設定の「ルーレットの詳細設定」で選び、`Config.spinEffectStyleKey` に保存する。
/// 保存値は `rawValue` なので、名前を変えるときは保存済みの値が読めなくなる（既定に戻る）ことに注意する。
/// 仕様は `docs/SPEC.md` の §5.5。どのスタイルも指定（`targetId`）の有無では変えない。
enum SpinEffectStyle: String, CaseIterable, Sendable {
    /// 何も付けない。今の見た目・動き・音のまま。
    case none
    /// 外周の電飾と共通の演出。
    case lights
    /// 光の尾・残像と共通の演出。
    case trails
    /// 火花・紙吹雪と共通の演出。
    case confetti
    /// 電飾・光の尾・火花と紙吹雪の 3 系統すべてと共通の演出。
    case all

    /// 未設定のときの値。
    static let `default` = SpinEffectStyle.none

    /// 付ける演出。「なし」は何も付けず、それ以外は 3 系統のうち選んだもの（全部入りは 3 つとも）と、どのスタイルにも付ける
    /// 共通の演出（焦らし・停止の演出・演出の効果音）を付ける。
    var effects: SpinEffects {
        guard self != .none else { return .none }
        return SpinEffects(
            lights: self == .lights || self == .all,
            trails: self == .trails || self == .all,
            particles: self == .confetti || self == .all,
            tease: true, stopEffects: true, sounds: true
        )
    }
}
