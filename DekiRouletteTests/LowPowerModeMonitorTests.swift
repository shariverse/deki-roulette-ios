import Foundation
import Testing
@testable import DekiRoulette

@MainActor
struct LowPowerModeMonitorTests {
    /// テストから書き換える低電力モードの値。
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var current: Bool {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    @Test func 作ったときの値を読む() {
        let flag = Flag()
        flag.current = true
        let monitor = LowPowerModeMonitor(notificationCenter: NotificationCenter()) { flag.current }
        #expect(monitor.isEnabled)
    }

    @Test func 読み直すと今の値になる() {
        let flag = Flag()
        let monitor = LowPowerModeMonitor(notificationCenter: NotificationCenter()) { flag.current }
        #expect(!monitor.isEnabled)
        flag.current = true
        monitor.refresh()
        #expect(monitor.isEnabled)
    }

    @Test func 変化の通知で読み直す() async {
        let flag = Flag()
        let center = NotificationCenter()
        let monitor = LowPowerModeMonitor(notificationCenter: center) { flag.current }
        flag.current = true
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        // 通知はメインの RunLoop に移してから読み直す
        for _ in 0..<100 where !monitor.isEnabled {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.isEnabled)
    }
}
