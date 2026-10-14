import Foundation

/// アプリアイコンの切替の窓口。実体は `UIApplication` だが、切替のたびに iOS のアラートが出て
/// テストでは呼べないので差し替える。
@MainActor
protocol AppIconSource: AnyObject {
    /// 代替アイコンに切り替えられる端末か。
    var supportsAlternateIcons: Bool { get }
    /// 今のアイコンの名前。既定のアイコンのときは nil。
    var alternateIconName: String? { get }
    /// アイコンを切り替える。nil で既定のアイコンに戻す。
    func setAlternateIconName(_ name: String?) async throws
}
