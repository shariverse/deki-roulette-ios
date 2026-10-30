import SwiftUI
import UIKit

/// アプリの外観（ライト・ダーク）をどう決めるか。設定の「外観」で選び、`Config.appearanceModeKey` に保存する。
/// 保存値は `rawValue` なので、名前を変えるときは保存済みの値が読めなくなる（既定に戻る）ことに注意する。
/// 起動画面（`LaunchBackground`）と共有画像（ダーク固定）には当てない。visionOS では当てずにシステムに従う。
enum AppearanceMode: String, CaseIterable, Sendable {
    /// 端末の外観の設定に従う。
    case system
    /// 端末の設定に依らずライト。
    case light
    /// 端末の設定に依らずダーク。
    case dark

    /// 未設定のときの値。今までどおり端末の外観に従う。
    static let `default` = AppearanceMode.system

    /// 保存値から読む。未設定・読めない値は既定（`system`）として読む（`@AppStorage` の RawRepresentable の読み方と同じ）。
    init(storedValue: String?) {
        self = storedValue.flatMap(AppearanceMode.init(rawValue:)) ?? .default
    }

    /// SwiftUI に渡す外観。`system` は nil（上書きしない）。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// UIKit のウィンドウに当てる外観。`system` は `.unspecified`（上書きを外して端末の外観に戻す）。
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}
