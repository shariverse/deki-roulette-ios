import Foundation
import Testing
@testable import DekiRoulette

private struct FakeIconError: Error {}

@MainActor
private final class FakeIconSource: AppIconSource {
    var supportsAlternateIcons: Bool
    var alternateIconName: String?
    /// 次の切替を失敗させるか。
    var fails = false
    /// 切替を止めておくか（iOS のアラートを閉じるまで返らない状態）。`resume()` で返す。
    var holds = false
    private(set) var requested: [String?] = []
    private var held: CheckedContinuation<Void, Never>?

    init(supportsAlternateIcons: Bool = true, alternateIconName: String? = nil) {
        self.supportsAlternateIcons = supportsAlternateIcons
        self.alternateIconName = alternateIconName
    }

    func setAlternateIconName(_ name: String?) async throws {
        requested.append(name)
        if holds {
            await withCheckedContinuation { held = $0 }
        }
        if fails { throw FakeIconError() }
        alternateIconName = name
    }

    func resume() {
        held?.resume()
        held = nil
    }
}

@MainActor
struct AppIconModelTests {
    @Test func 選択中の表示は今のアイコンの名前から決める() {
        #expect(AppIconModel(source: FakeIconSource(alternateIconName: nil)).current == .standard)
        #expect(AppIconModel(source: FakeIconSource(alternateIconName: "AppIcon-Neon")).current == .neon)
        #expect(AppIconModel(source: FakeIconSource(alternateIconName: "AppIcon-Casino")).current == nil)
    }

    @Test func 選ぶと代替アイコンの名前で切り替える() async {
        let source = FakeIconSource()
        let model = AppIconModel(source: source)

        await model.select(.target)
        #expect(source.requested == ["AppIcon-Target"])
        #expect(model.current == .target)

        await model.select(.standard)
        #expect(source.requested == ["AppIcon-Target", nil])
        #expect(model.current == .standard)
        #expect(model.failed == false)
    }

    @Test func 失敗したら今のアイコンに戻して知らせる() async {
        let source = FakeIconSource(alternateIconName: "AppIcon-Neon")
        source.fails = true
        let model = AppIconModel(source: source)

        await model.select(.pastel)
        #expect(source.requested == ["AppIcon-Pastel"])
        #expect(model.current == .neon)
        #expect(model.failed == true)
    }

    @Test func 選択中のアイコンを選んでも切り替えない() async {
        let source = FakeIconSource(alternateIconName: "AppIcon-Spinner")
        let model = AppIconModel(source: source)
        await model.select(.spinner)
        #expect(source.requested.isEmpty)
    }

    @Test func 切り替えられない端末では切り替えない() async {
        let source = FakeIconSource(supportsAlternateIcons: false)
        let model = AppIconModel(source: source)
        #expect(model.isSupported == false)
        await model.select(.neon)
        #expect(source.requested.isEmpty)
        #expect(model.current == .standard)
    }

    /// 一覧に無い名前（消した代替アイコンなど）を選んでいた利用者も、選び直せる。
    @Test func どれも選ばれていない状態から選べる() async {
        let source = FakeIconSource(alternateIconName: "AppIcon-Casino")
        let model = AppIconModel(source: source)
        await model.select(.neon)
        #expect(source.requested == ["AppIcon-Neon"])
        #expect(model.current == .neon)
    }

    @Test func どれも選ばれていない状態で失敗したらそのまま戻す() async {
        let source = FakeIconSource(alternateIconName: "AppIcon-Casino")
        source.fails = true
        let model = AppIconModel(source: source)
        await model.select(.neon)
        #expect(model.current == nil)
        #expect(model.failed == true)
    }

    /// iOS のアラートを閉じるまで切替は終わらない。その間も選択の表示は選んだものにし、次の選択は受け付けない。
    /// 待ち合わせが外れたときに止まり続けないよう、時間を区切る。
    @Test(.timeLimit(.minutes(1)))
    func 切り替えの途中は選択を先に変えて次を受け付けない() async {
        let source = FakeIconSource()
        source.holds = true
        let model = AppIconModel(source: source)

        let first = Task { await model.select(.neon) }
        while source.requested.isEmpty { await Task.yield() }
        #expect(model.current == .neon)

        await model.select(.pastel)
        #expect(source.requested == ["AppIcon-Neon"])
        #expect(model.current == .neon)

        source.holds = false
        source.resume()
        await first.value
        #expect(model.current == .neon)
        await model.select(.pastel)
        #expect(source.requested == ["AppIcon-Neon", "AppIcon-Pastel"])
    }

    @Test func 読み直すと今のアイコンに合わせる() {
        let source = FakeIconSource()
        let model = AppIconModel(source: source)
        source.alternateIconName = "AppIcon-Target"
        model.refresh()
        #expect(model.current == .target)
    }
}
