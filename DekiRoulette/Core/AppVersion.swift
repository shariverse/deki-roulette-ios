import Foundation

/// 設定シートの末尾に出すバージョンとビルド番号。Info.plist の `CFBundleShortVersionString` と `CFBundleVersion` を
/// 加工せずに使う（ビルドの種類で出し分けない）。文言の型は `L10n` から渡し、ここでは組み立てだけを担う。
struct AppVersion: Equatable {
    /// `CFBundleShortVersionString`（「1.1.0」）。無い・文字列でない・空なら nil。
    let version: String?
    /// `CFBundleVersion`（「24」）。無い・文字列でない・空なら nil。
    let build: String?

    /// どちらも無ければ nil（行を出さない）。
    init?(version: String?, build: String?) {
        let version = Self.normalized(version)
        let build = Self.normalized(build)
        guard version != nil || build != nil else { return nil }
        self.version = version
        self.build = build
    }

    /// Info.plist の辞書（`Bundle.infoDictionary`）から読む。辞書が無い・どちらの値も無ければ nil。
    init?(infoDictionary: [String: Any]?) {
        self.init(
            version: infoDictionary?["CFBundleShortVersionString"] as? String,
            build: infoDictionary?["CFBundleVersion"] as? String
        )
    }

    /// 表示の文字列。両方あれば型（`%1$@` にバージョン、`%2$@` にビルド）に入れ、片方しか無ければその値だけにする。
    func display(template: String) -> String {
        format(both: template, versionOnly: "%@", buildOnly: "%@")
    }

    /// 読み上げのラベル（「バージョン 1.1.0、ビルド 24」）。片方しか無ければ、その値の型だけを使う。
    func accessibilityLabel(both: String, versionOnly: String, buildOnly: String) -> String {
        format(both: both, versionOnly: versionOnly, buildOnly: buildOnly)
    }

    private func format(both: String, versionOnly: String, buildOnly: String) -> String {
        // 値は引数として渡すので、値に `%` が含まれていても書式として読まない
        switch (version, build) {
        case let (version?, build?): String(format: both, locale: nil, version, build)
        case let (version?, nil): String(format: versionOnly, locale: nil, version)
        case let (nil, build?): String(format: buildOnly, locale: nil, build)
        // init で弾いているので来ない
        case (nil, nil): ""
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
