import Foundation

/// 設定の「アプリアイコン」で選べるアイコン。並びはグリッドの順で、先頭が既定のアイコン。
/// `rawValue` はアイコンの名前（`DekiRoulette/Resources/<名前>.icon`）。代替アイコンの名前は `project.yml` の
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` と `scripts/make-icon.swift` の `alternateIcons` と同じにする。
/// 選んだアイコンはシステムが `UIApplication.alternateIconName` に名前で覚えるので、リリースしたら名前を変えない。
enum AppIconChoice: String, CaseIterable, Sendable {
    /// 既定のアイコン（盤面の絵）。
    case standard = "AppIcon"
    case neon = "AppIcon-Neon"
    case pastel = "AppIcon-Pastel"
    case spinner = "AppIcon-Spinner"
    case target = "AppIcon-Target"

    /// `setAlternateIconName(_:)` に渡す名前。既定のアイコンは nil。
    var alternateIconName: String? {
        self == .standard ? nil : rawValue
    }

    /// グリッドに出す見本の画像（`Assets.xcassets` の imageset）。アイコンそのものは `UIImage(named:)` で読めないので、
    /// `scripts/make-icon.swift` が `ictool` で書き出した画像を使う。
    var previewImageName: String {
        rawValue + "-Preview"
    }

    /// `UIApplication.alternateIconName` から今のアイコンを決める。nil は既定のアイコン。
    /// 一覧に無い名前（消した代替アイコンなど）のときは nil を返し、どれも選ばれていない扱いにする。
    init?(alternateIconName: String?) {
        guard let alternateIconName else {
            self = .standard
            return
        }
        guard let choice = AppIconChoice(rawValue: alternateIconName), choice != .standard else { return nil }
        self = choice
    }
}
