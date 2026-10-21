//
//  AppStoreScreenshotTests.swift
//  DekiRouletteUITests
//

import XCTest

/// App Store 用スクリーンショットを撮る。主要な画面を 4 枚残す。
///
/// ふだんのテストでは流さない。`scripts/app-store-screenshots.sh` が環境変数 `APP_STORE_SCREENSHOTS=1`
/// （xcodebuild には `TEST_RUNNER_APP_STORE_SCREENSHOTS=1` で渡す）を付けて、表示サイズ・言語ごとに流す。
/// 言語は `APP_STORE_LANGUAGE`（`-AppleLanguages` の値）と `APP_STORE_LOCALE`（`-AppleLocale` の値）で受け取る。
/// 文言は言語で変わるので、要素はアクセシビリティ ID と、タブの並びの位置で探す。
/// 前回の実行で残った項目リスト（UserDefaults）が写らないよう、スクリプトが起動のたびにアプリを消してから流す。
///
/// 撮り方はプラットフォームで違う。
/// - iOS は XCTest の添付（`XCUIScreen.main.screenshot()`）で撮り、スクリプトが `xcresulttool` で書き出す
/// - visionOS は XCTest の手動スクリーンショットが使えない（`Manual screenshots are not supported.` で 1×1 の絵になる）ため、
///   スクリプト（ホスト）に合図のファイルを書いて、`xcrun simctl io ... screenshot` で撮ってもらう
final class AppStoreScreenshotTests: XCTestCase {
    /// 結果が出ている間だけ出る「結果を共有」ボタン。スピンや並べ替えが終わったこと（＝結果が出たこと）を待つのに使う。
    private enum ResultSignal {
        static let roulette = "roulette.result.share"
        static let order = "order.result.share"
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["APP_STORE_SCREENSHOTS"] == "1",
            "App Store 用スクリーンショットは scripts/app-store-screenshots.sh で撮る"
        )
        continueAfterFailure = false
    }

    /// 撮る画面は 01-ルーレット → 02-結果 → 03-順番決め → 04-並べ替え結果。
    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let app = launch()

        // 1. ルーレット（起動直後のタブ）
        let spin = app.buttons["roulette.spin"]
        XCTAssertTrue(spin.waitForExistence(timeout: 30), "スピンのボタンが見つからない")
        capture("01-ルーレット")

        // 2. 回した結果。スピン中は出ない「結果を共有」が出るまで待つ（内側の状態を見なくて済む）
        spin.tap()
        if !app.buttons[ResultSignal.roulette].waitForExistence(timeout: 20) {
            // 1 回目のタップが届かなかったときの保険（スピン中に押しても無効なので、二度押しは無害）
            spin.tap()
            XCTAssertTrue(
                app.buttons[ResultSignal.roulette].waitForExistence(timeout: 60),
                "スピンの結果が出ない\n\(app.debugDescription)"
            )
        }
        capture("02-結果")

        // 3. 順番決め
        let orderTab = orderTab(in: app)
        XCTAssertTrue(orderTab.waitForExistence(timeout: 30), "順番決めのタブが見つからない\n\(app.debugDescription)")
        orderTab.tap()
        let shuffle = app.buttons["order.shuffle"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 30), "並べ替えのボタンが見つからない")
        capture("03-順番決め")

        // 4. 並べ替えた結果。演出中は出ない「結果を共有」が出るまで待つ
        shuffle.tap()
        if !app.buttons[ResultSignal.order].waitForExistence(timeout: 20) {
            shuffle.tap()
            XCTAssertTrue(
                app.buttons[ResultSignal.order].waitForExistence(timeout: 60),
                "並べ替えの結果が出ない"
            )
        }
        capture("04-並べ替え結果")
    }

    // MARK: - 起動と画面の操作

    /// 言語と地域を渡して起動する（アプリの文言がその言語になる）。
    @MainActor
    private func launch() -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        let language = environment["APP_STORE_LANGUAGE"] ?? "ja"
        let locale = environment["APP_STORE_LOCALE"] ?? "ja_JP"
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        app.launch()
        return app
    }

    /// 順番決めのタブ。iPhone はタブバー、iPad は上部のタブ（identifier に SF Symbol 名が入る）、
    /// visionOS は左端の縦型バー。並びの位置か、文言（言語で変わる）で探す。
    @MainActor
    private func orderTab(in app: XCUIApplication) -> XCUIElement {
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            return tabBar.buttons.element(boundBy: 1)
        }
        let bySymbol = app.buttons["list.number"].firstMatch
        if bySymbol.exists {
            return bySymbol
        }
        // visionOS の縦型バーはボタンとは限らない（ラジオボタン・セル・文字だけのこともある）ので、順に試す
        let predicate = NSPredicate(format: "label IN %@", ["順番決め", "Random order"])
        for query in [app.buttons, app.radioButtons, app.cells, app.staticTexts] {
            let element = query.matching(predicate).firstMatch
            if element.exists {
                return element
            }
        }
        return app.buttons.matching(predicate).firstMatch
    }

    // MARK: - 撮影

    /// 描画が追いつくのを待って撮る。
    @MainActor
    private func capture(_ name: String) {
        #if os(visionOS)
        captureOnHost(name)
        #else
        captureAsAttachment(name)
        #endif
    }

    #if os(visionOS)
    /// ホスト（scripts/app-store-screenshots.sh）に撮ってもらう。Documents に合図のファイルを置き、
    /// ホストが `simctl` で撮ってファイルを消すまで待つ。演出（結果の帯や光）が落ち着くのを少し待ってから合図する。
    @MainActor
    private func captureOnHost(_ name: String) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let request = directory.appendingPathComponent("capture-\(name).request")
        try? FileManager.default.removeItem(at: request)
        do {
            try Data().write(to: request)
        } catch {
            XCTFail("撮影の合図（\(request.lastPathComponent)）を書けない: \(error)")
            return
        }
        // ホストは 0.3 秒ごとに合図を見ているので、これだけあれば十分（短くして、失敗したら早くやり直す）
        let deadline = Date(timeIntervalSinceNow: 60)
        while FileManager.default.fileExists(atPath: request.path) {
            if Date() > deadline {
                XCTFail("ホストが \(name) を撮らないまま時間切れ")
                return
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }
    }
    #else
    /// 描画が追いつくのを待って撮る。結果の帯の光のように動き続ける画面もあるので、
    /// 同じ絵が続いたら即、続かなくても最後の 1 枚を使う（そのためにテストは失敗させない）。
    @MainActor
    private func captureAsAttachment(_ name: String) {
        var shot = XCUIScreen.main.screenshot()
        for _ in 0..<6 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            let next = XCUIScreen.main.screenshot()
            if next.pngRepresentation == shot.pngRepresentation {
                shot = next
                break
            }
            shot = next
        }
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif
}
