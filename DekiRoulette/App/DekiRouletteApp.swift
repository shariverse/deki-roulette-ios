import SwiftUI

@main
struct DekiRouletteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// 画面収録・ミラーリングの状態。両画面の `ItemListView` が印を伏せる判断に使う。
    @State private var screenCapture = ScreenCaptureMonitor(source: SystemCaptureSource())
    /// 設定の「外観」で選んだ外観。未設定・読めない値は端末の外観に従う（`AppearanceMode.default`）。
    @AppStorage(Config.appearanceModeKey) private var appearanceMode = AppearanceMode.default

    var body: some Scene {
        WindowGroup {
            RootView()
                .appTypography()
                .appAppearance(appearanceMode)
                .environment(screenCapture)
                // 初期化の時点ではシーンが未接続で読めないので、表示されたら読み直す。
                // 起動前から収録中だと変化の通知が来ないため
                .onAppear { screenCapture.refresh() }
                // visionOS には変化の通知が無いので、アプリに戻ったときにも読み直す
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { screenCapture.refresh() }
                }
        }
    }
}
