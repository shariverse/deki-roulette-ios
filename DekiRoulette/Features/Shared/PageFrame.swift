import SwiftUI

/// 両画面で共通の枠。ナビゲーションバー（大きいタイトル・タグライン・設定ボタン）・本文・フッターの折りたたみ。
/// 題名と設定ボタンはバーに載せ、スクロールしても上部に残す（大きいタイトルはスクロールで縮む）。
struct PageFrame<Content: View, Help: View>: View {
    let title: String
    let tagline: String
    /// 演出中。開いたままの説明を畳む。
    let busy: Bool
    let useCases: String
    /// スピン中の暗転。真の間、中身が `spinSpotlightTarget()` で伝えた盤面だけを残してページを暗い幕で覆う。
    /// 既定は無効（順番決め画面は使わない）。
    var spotlight = false
    /// 真の間、バーの設定ボタンとフッターの折りたたみを無効にする（ルーレットのスピン中。暗い所は触れない）。
    /// `busy` は順番決めの並べ替え中にも立つので流用せず、既定は無効（順番決め画面は今のまま押せる）。
    var locksControls = false
    @ViewBuilder let help: () -> Help
    @ViewBuilder let content: () -> Content

    @State private var helpOpen = false
    @State private var settingsOpen = false
    @State private var useCasesOpen = false
    @State private var noticeOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 大きいタイトルが縮むのはスタックの根の `ScrollView` のスクロールに連動するため、`ScrollView` を根に置く
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !Self.taglineInBar {
                        taglineText
                            .padding(.bottom, 32)
                    }
                    content()
                    footer
                        .padding(.top, 56)
                }
                .padding(.horizontal, Theme.Layout.pageHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: Theme.Layout.pageMaxWidth)
                .frame(maxWidth: .infinity)
                // 幕は中身と同じ座標に 1 枚だけ重ねるので、スクロールしても穴が盤面に付いていく
                .overlayPreferenceValue(SpinSpotlightAnchorKey.self) { anchor in
                    if let anchor {
                        GeometryReader { proxy in
                            SpinScrim(contentSize: proxy.size, hole: SpinSpotlight.hole(in: proxy[anchor]))
                                .opacity(SpinSpotlight.opacity(spinning: spotlight))
                                .animation(reduceMotion ? nil : Theme.spinDimAnimation, value: spotlight)
                        }
                    }
                }
            }
            // visionOS にはソフトウェアキーボードが無いので付けない
            #if !os(visionOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .background(Theme.ink900.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .modifier(PageTitleBar(title: title, tagline: tagline))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    settingsButton
                }
            }
        }
        .sheet(isPresented: $settingsOpen) { SettingsView() }
        // 開始した瞬間に畳む。人前で回すときに開きっぱなしを踏まないための保険
        .onChange(of: busy) { _, isBusy in
            if isBusy { helpOpen = false }
        }
    }

    /// タグラインをバー（題名の下のサブタイトル）に載せるか。iOS 26 以上だけで、iOS 17〜18 と visionOS は本文の先頭に置いてスクロールで流す。
    /// 出し分けの条件はここ 1 か所に置く（`PageTitleBar` もこの値を見る）。
    static var taglineInBar: Bool {
        #if os(visionOS)
        false
        #else
        if #available(iOS 26, *) { true } else { false }
        #endif
    }

    private var taglineText: some View {
        Text(tagline)
            .font(Theme.Typography.pageTagline)
            .foregroundStyle(Theme.muted)
    }

    /// 標準のツールバーのボタン。iOS 26 は Liquid Glass の地が付くので、円の地は自前で描かない。
    private var settingsButton: some View {
        Button {
            settingsOpen = true
        } label: {
            Image(systemName: "gearshape")
        }
        .disabled(locksControls)
        .accessibilityLabel(L10n.settingsTitle)
        // visionOS のツールバーのボタンは tint で地を塗るので、アプリの根の `ivory` の tint を外してシステムのガラスのボタンにする
        #if os(visionOS)
        .tint(nil)
        #endif
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 20) {
            Divider().overlay(Theme.ink700)

            // 開いている折りたたみはそのまま出し、開け閉めだけを止める
            FooterDisclosure(title: L10n.helpTitle, isExpanded: $helpOpen) {
                help()
            }
            .disabled(locksControls)
            FooterDisclosure(title: L10n.useCasesTitle, isExpanded: $useCasesOpen) {
                Text(useCases)
            }
            .disabled(locksControls)
            FooterDisclosure(title: L10n.noticeTitle, isExpanded: $noticeOpen) {
                Text(L10n.notice)
            }
            .disabled(locksControls)
        }
        .font(Theme.Typography.font(.subheadline))
        .foregroundStyle(Theme.muted)
    }
}

private struct FooterDisclosure<Body: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let body_: () -> Body

    init(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Body) {
        self.title = title
        self._isExpanded = isExpanded
        self.body_ = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                        .font(Theme.Typography.font(.callout, weight: .bold))
                        .foregroundStyle(Theme.ivory)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isExpanded ? [.isButton, .isSelected] : .isButton)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    body_()
                }
                .lineSpacing(3)
                .padding(.leading, 20)
            }
        }
    }
}

/// フッターの説明文で使う小見出し。
struct HelpHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typography.font(.subheadline, weight: .bold))
            .foregroundStyle(Theme.ivory)
            .padding(.top, 6)
    }
}

/// 両画面のバーの題名とタグラインを同梱の書体で出す（iOS 26 以上）。
/// iOS 26 の SwiftUI の `navigationTitle` の文字は UIKit の外観の API でも同梱の書体にならないので、同じ題名を toolbar の置き場所の `Text` で出す。
/// `navigationTitle` は読み上げの画面名と、置き場所の無い iOS 17〜18（`RootView.init` の外観で寄せる）・visionOS（システムの書体）に使う。
/// 縮んだ題名（`.title` / `.subtitle`）の置き場所は大きいタイトルが出ている間も消えないので、縮み切ったときだけ見せる（`LargeTitleCollapse`）。
private struct PageTitleBar: ViewModifier {
    let title: String
    let tagline: String

    @State private var collapse = LargeTitleCollapse()
    @State private var largeTitleHeight: CGFloat = 0
    @State private var inlineShown = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if os(visionOS)
        content
        #else
        if #available(iOS 26, *) {
            content
                .toolbar {
                    ToolbarItem(placement: .largeTitle) {
                        Text(title)
                            .font(Theme.Typography.pageLargeTitle)
                            .tracking(Theme.Typography.pageTitleTracking)
                            .foregroundStyle(Theme.ivory)
                            .accessibilityAddTraits(.isHeader)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { largeTitleHeight = $0 }
                    }
                    ToolbarItem(placement: .title) {
                        Text(title)
                            .font(Theme.Typography.pageInlineTitle)
                            .foregroundStyle(Theme.ivory)
                            .lineLimit(1)
                            .inlineTitleVisibility(inlineShown)
                    }
                    ToolbarItem(placement: .largeSubtitle) {
                        Text(tagline)
                            .font(Theme.Typography.pageTagline)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ToolbarItem(placement: .subtitle) {
                        Text(tagline)
                            .font(Theme.Typography.pageInlineTagline)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .inlineTitleVisibility(inlineShown)
                    }
                }
                .onScrollGeometryChange(for: TitleScrollSample.self) { geometry in
                    TitleScrollSample(
                        offsetY: geometry.contentOffset.y,
                        insetTop: geometry.contentInsets.top,
                        containerWidth: geometry.containerSize.width
                    )
                } action: { _, sample in
                    collapse.record(insetTop: sample.insetTop, containerWidth: sample.containerWidth)
                    let shown = collapse.showsInlineTitle(
                        offsetY: sample.offsetY,
                        insetTop: sample.insetTop,
                        largeTitleHeight: largeTitleHeight
                    )
                    guard shown != inlineShown else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { inlineShown = shown }
                }
                // バーの地は塗らず（`toolbarBackground` を付けると大きいタイトルの置き場所が消える・途中の位置でバーが白く覆われる）、
                // 縁の効果をはっきりした方にして、縮んだ題名の下を流れる本文と文字を分ける
                .scrollEdgeEffectStyle(.hard, for: .top)
                // 文字の大きさが変わると展開時のバーの高さが変わるので測り直す
                .onChange(of: typeSize) { collapse.reset() }
        } else {
            content
        }
        #endif
    }
}

/// `PageTitleBar` が読むスクロールの幾何。
private struct TitleScrollSample: Equatable {
    let offsetY: CGFloat
    let insetTop: CGFloat
    let containerWidth: CGFloat
}

private extension View {
    /// 縮んだ題名の置き場所の `Text`。大きいタイトルが出ている間は透明にする。
    /// 読み上げからも外すよう指定するが、Simulator の読み上げの木では置き場所の中の `accessibilityHidden` が効かず要素が残る（実機の VoiceOver で確かめる）。
    func inlineTitleVisibility(_ shown: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .accessibilityHidden(!shown)
    }
}
