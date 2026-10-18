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

    /// 外周の電飾を出すか。
    var showsLights: Bool { self == .lights || self == .all }

    /// 光の尾と盤面の残像を出すか。
    var showsTrails: Bool { self == .trails || self == .all }

    /// 針の先の火花と停止の瞬間の紙吹雪を出すか。
    var showsParticles: Bool { self == .confetti || self == .all }

    /// 「なし」以外のどのスタイルにも付ける演出（背景の光の脈動・止まり際の焦らし・針を大きく弾く・停止の瞬間のフラッシュ・
    /// 結果の帯の登場演出・結果表示中の余韻・効果音）を出すか。
    var showsCommonEffects: Bool { self != .none }
}
