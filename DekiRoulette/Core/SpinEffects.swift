import Foundation

/// スピンに付ける演出の ON / OFF（`docs/SPEC.md` の §5.5）。演出ごとに 1 つずつフラグを持ち、2D・3D の盤面・焦らし・効果音は
/// このフラグだけを見て出し分ける。どのフラグも指定（`targetId`）の有無では変えない。
/// 設定の「ルーレットの詳細設定」の「スピンの演出」で、全体の ON / OFF と演出ごとのトグル（`SpinEffectItem`）から選ぶ。
struct SpinEffects: Hashable, Sendable {
    /// 外周の電飾と背景の光の脈動。
    var lights: Bool
    /// 光の尾と盤面の残像。
    var trails: Bool
    /// 針の先の火花と停止の瞬間の紙吹雪。
    var particles: Bool
    /// 止まり際の焦らし。
    var tease: Bool
    /// 停止の演出（停止の瞬間のフラッシュ・針を大きく弾く・結果の帯の登場演出・結果表示中の光彩の余韻）。
    var stopEffects: Bool
    /// 演出の効果音（スピン中のうなり・停止時の決まり音）。設定の「効果音」が ON のときだけ鳴る。
    var sounds: Bool

    /// 何も付けない。今の見た目・動き・音のまま。
    static let none = SpinEffects(
        lights: false, trails: false, particles: false, tease: false, stopEffects: false, sounds: false
    )

    /// すべて付ける。
    static let all = SpinEffects(
        lights: true, trails: true, particles: true, tease: true, stopEffects: true, sounds: true
    )

    /// 未設定のときの値（すべて ON）。
    static let `default` = SpinEffects.all

    /// 設定で選んだ演出。全体（`enabled`）が OFF なら、個別の選択（`selected`）に依らず何も付けない（`.none`）。
    /// 全体を OFF にしても個別の選択は保存したまま残し、ON に戻したらその選択で付ける。
    static func effective(enabled: Bool, selected: SpinEffects) -> SpinEffects {
        enabled ? selected : .none
    }

    /// 指で盤面を動かしている間の動き（`WheelDragMotion`）を記録するか。速さに連動する演出（電飾・光の尾と残像・火花）の
    /// どれかを出すときだけで、どれも出さないときは記録しない。2D と 3D の盤面が同じ値を `WheelDragArea` に渡す。
    var tracksDragMotion: Bool { lights || trails || particles }
}

/// 「スピンの演出」の個別のトグル。設定画面の並び順で、`UserDefaults` のキー（`Config.spinEffectKey(_:)`）の元にもなる。
/// 保存値は `rawValue` なので、名前を変えると保存済みの選択が読めなくなる（既定の ON に戻る）。
enum SpinEffectItem: String, CaseIterable, Sendable {
    case lights
    case trails
    case particles
    case tease
    case stopEffects
    case sounds

    /// `SpinEffects` のうち、このトグルが受け持つフラグ。
    var keyPath: WritableKeyPath<SpinEffects, Bool> {
        switch self {
        case .lights: \.lights
        case .trails: \.trails
        case .particles: \.particles
        case .tease: \.tease
        case .stopEffects: \.stopEffects
        case .sounds: \.sounds
        }
    }
}
