import SwiftUI

/// ルーレットと順番決めの 2 画面をタブで切り替える。Web 版のページ間リンクに対応する。
struct RootView: View {
    private enum Tab: Hashable {
        case roulette
        case order
    }

    @State private var selection: Tab = .roulette

    // 両画面のモデルはここで持つ。設定シートから両方の項目を初期状態に戻せるよう environment にも流す。
    @State private var rouletteModel = RouletteModel(store: ItemStore(key: .roulette) { L10n.defaultItems })
    @State private var orderModel = OrderModel(store: ItemStore(key: .order) { L10n.orderDefaultItems })
    /// 名前を付けて保存したリスト。両画面で 1 つを共有する。
    @State private var savedLists = SavedListsModel(store: SavedListStore())

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.ink800)
        // タブの項目の文字も同梱の書体にする（システムの既定と同じ 10pt の medium。タブバーの文字は Dynamic Type で拡大しない）
        let tabTitle: [NSAttributedString.Key: Any] = [.font: Theme.Typography.uiFont(size: 10, weight: .medium)]
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = tabTitle
            layout.selected.titleTextAttributes = tabTitle
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        Self.applyNavigationTitleAppearance()
    }

    /// iOS 17〜18 の両画面の題名（ナビゲーションバー）を同梱の書体に寄せる。地はシステムの既定のまま
    /// （先頭の大きいタイトルの間は透明、スクロールしたらぼかしの地）で、`PageFrame` は塗らない。
    /// iOS 26 以上の SwiftUI の題名にはこの属性が効かないので当てず（`PageFrame` が toolbar の置き場所に `Text` を置く）、
    /// visionOS はシステムの書体のまま。シートは `toolbarBackground` の地と `.principal` の題名で上書きしているので変わらない。
    private static func applyNavigationTitleAppearance() {
        #if !os(visionOS)
        guard #unavailable(iOS 26) else { return }
        func appearance(transparent: Bool) -> UINavigationBarAppearance {
            let appearance = UINavigationBarAppearance()
            if transparent {
                appearance.configureWithTransparentBackground()
            } else {
                appearance.configureWithDefaultBackground()
            }
            appearance.largeTitleTextAttributes = Theme.Typography.navigationLargeTitleAttributes()
            appearance.titleTextAttributes = Theme.Typography.navigationInlineTitleAttributes()
            return appearance
        }
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance(transparent: false)
        bar.compactAppearance = appearance(transparent: false)
        bar.scrollEdgeAppearance = appearance(transparent: true)
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            RouletteScreen(model: rouletteModel)
                .tabItem { Label(L10n.rouletteNavLabel, systemImage: "circle.circle") }
                .tag(Tab.roulette)
            OrderScreen(model: orderModel)
                .tabItem { Label(L10n.orderNavLabel, systemImage: "list.number") }
                .tag(Tab.order)
        }
        .tint(Theme.ivory)
        .environment(rouletteModel)
        .environment(orderModel)
        .environment(savedLists)
    }
}

#Preview {
    RootView()
        .appTypography()
}
