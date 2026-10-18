import Combine
import Observation
import UIKit

/// 画面がキャプチャされているかを追いかけて View に配る。`Environment` で両画面へ渡す。
/// キャプチャ中は印を伏せる（`ItemListView`）。判定そのものは `ScreenCaptureSource` に任せる。
@MainActor
@Observable
final class ScreenCaptureMonitor {
    private(set) var isCaptured: Bool

    private let source: any ScreenCaptureSource
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private var sceneRegistrations: [UIWindowScene: any UITraitChangeRegistration] = [:]

    /// 変化を知らせる通知名。visionOS には `UIScreen` が無く通知も無いので nil
    /// （nil のときは、表示・アクティブ復帰・シーンの trait 変化で `refresh()` を呼んで読み直す）。
    private static let captureDidChangeNotification: Notification.Name? = {
        #if os(visionOS)
        nil
        #else
        UIScreen.capturedDidChangeNotification
        #endif
    }()

    /// - Parameters:
    ///   - source: キャプチャ状態の取得元。
    ///   - notificationCenter: 変化の通知を受け取る先。テストでは専用のインスタンスを渡す。
    ///   - notificationName: 変化を知らせる通知名。既定は `UIScreen.capturedDidChangeNotification`。
    init(
        source: any ScreenCaptureSource,
        notificationCenter: NotificationCenter = .default,
        notificationName: Notification.Name? = ScreenCaptureMonitor.captureDidChangeNotification
    ) {
        self.source = source
        self.isCaptured = source.isCaptured
        // 通知は取得元が変わったことだけを知らせるので、値は毎回読み直す
        if let notificationName {
            subscription = notificationCenter.publisher(for: notificationName)
                .map { _ in () }
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.refresh() }
        }
    }

    /// 取得元の値を読み直す。通知を待たずに同期したいときにも使う。
    func refresh() {
        isCaptured = source.isCaptured
        observeScenesIfNeeded()
    }

    /// visionOS には変化の通知が無いので、接続中のシーンの trait（`UITraitSceneCaptureState`）を購読する。
    /// シーンは起動直後にはまだ無いので、`refresh()` のたびに未登録のシーンを探して登録する。
    private func observeScenesIfNeeded() {
        #if os(visionOS)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        where sceneRegistrations[scene] == nil {
            sceneRegistrations[scene] = scene.registerForTraitChanges([UITraitSceneCaptureState.self]) {
                [weak self] (_: UIWindowScene, _) in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        #endif
    }
}

/// 実際の取得元。どれか 1 つでもキャプチャされていれば「キャプチャ中」とみなす。
/// `UIScreen.isCaptured` は `UITraitCollection.sceneCaptureState` へ移行する方向だが、
/// 画面単位（ミラーリングも含む）の判定を変えないため、iOS では今までどおり `UIScreen` から読む。
@MainActor
final class SystemCaptureSource: ScreenCaptureSource {
    var isCaptured: Bool {
        #if os(visionOS)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.traitCollection.sceneCaptureState == .active }
        #else
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .contains { $0.isCaptured }
        #endif
    }
}
