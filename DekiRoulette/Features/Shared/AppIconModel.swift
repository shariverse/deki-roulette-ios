import Observation
import UIKit

/// 設定の「アプリアイコン」の選択。選択中の表示は `alternateIconName` から決め、`UserDefaults` には持たない
/// （選んだアイコンはシステムが覚える）。切替そのものは `AppIconSource` に任せる。
@MainActor
@Observable
final class AppIconModel {
    /// 代替アイコンに切り替えられる端末か。偽なら設定に項目を出さない。
    let isSupported: Bool
    /// 選択中のアイコン。一覧に無い名前のときは nil（どれも選ばれていない）。
    private(set) var current: AppIconChoice?
    /// 切り替えに失敗したか。設定画面はこれでアラートを出し、閉じたら false に戻す。
    var failed = false

    private let source: any AppIconSource
    /// 切り替えの途中か。iOS の「アイコンを変更しました」のアラートを閉じるまで終わらないので、その間の選択は受け付けない。
    @ObservationIgnored private var changing = false

    init(source: any AppIconSource) {
        self.source = source
        isSupported = source.supportsAlternateIcons
        current = AppIconChoice(alternateIconName: source.alternateIconName)
    }

    /// 今のアイコンを読み直す。
    func refresh() {
        current = AppIconChoice(alternateIconName: source.alternateIconName)
    }

    /// 選んだアイコンに切り替える。切替は iOS のアラートを閉じるまで終わらないので選択の表示は先に変え、
    /// 失敗したら `failed` を立てて今のアイコンに戻す。
    func select(_ choice: AppIconChoice) async {
        guard isSupported, !changing, choice != current else { return }
        changing = true
        defer { changing = false }
        current = choice
        do {
            try await source.setAlternateIconName(choice.alternateIconName)
        } catch {
            failed = true
        }
        refresh()
    }
}

/// `UIApplication` を窓口にする。visionOS には代替アイコンの API が無いので、非対応として振る舞う
/// （`supportsAlternateIcons` が偽になり、設定の「アプリアイコン」の項目が出ない）。
@MainActor
final class UIApplicationIconSource: AppIconSource {
    var supportsAlternateIcons: Bool {
        #if os(visionOS)
        false
        #else
        UIApplication.shared.supportsAlternateIcons
        #endif
    }

    var alternateIconName: String? {
        #if os(visionOS)
        nil
        #else
        UIApplication.shared.alternateIconName
        #endif
    }

    func setAlternateIconName(_ name: String?) async throws {
        #if os(visionOS)
        // `supportsAlternateIcons` が偽なので呼ばれない
        #else
        try await UIApplication.shared.setAlternateIconName(name)
        #endif
    }
}
