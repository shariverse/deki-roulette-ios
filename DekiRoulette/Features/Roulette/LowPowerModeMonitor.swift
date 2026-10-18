import Combine
import Foundation
import Observation

/// 低電力モードが ON かを追いかける。速さに連動する演出が描く量を減らすのに使う（光の尾・残像は `WheelTrails.ghostCount(lowPower:)`）。
/// 変化は `NSProcessInfoPowerStateDidChange` で知らされ（どのスレッドから来るか決まっていない）、値は毎回読み直す。
@MainActor
@Observable
final class LowPowerModeMonitor {
    private(set) var isEnabled: Bool

    @ObservationIgnored private let read: @Sendable () -> Bool
    @ObservationIgnored private var subscription: AnyCancellable?

    /// - Parameters:
    ///   - notificationCenter: 変化の通知を受け取る先。テストでは専用のインスタンスを渡す。
    ///   - read: 今の値の取得元。既定は `ProcessInfo.processInfo.isLowPowerModeEnabled`。
    init(
        notificationCenter: NotificationCenter = .default,
        read: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.read = read
        isEnabled = read()
        subscription = notificationCenter.publisher(for: .NSProcessInfoPowerStateDidChange)
            .map { _ in () }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
    }

    /// 取得元の値を読み直す。
    func refresh() {
        isEnabled = read()
    }
}
