import SwiftUI

/// 両画面で共通の枠。ヘッダ・本文・フッターの折りたたみ。
struct PageFrame<Content: View, Help: View>: View {
    let title: String
    let tagline: String
    /// 演出中。開いたままの説明を畳む。
    let busy: Bool
    let useCases: String
    /// スピン中の暗転。真の間、中身が `spinSpotlightTarget()` で伝えた盤面だけを残してページを暗い幕で覆う。
    /// 既定は無効（順番決め画面は使わない）。
    var spotlight = false
    /// 真の間、ヘッダの設定ボタンとフッターの折りたたみを無効にする（ルーレットのスピン中。暗い所は触れない）。
    /// `busy` は順番決めの並べ替え中にも立つので流用せず、既定は無効（順番決め画面は今のまま押せる）。
    var locksControls = false
    @ViewBuilder let help: () -> Help
    @ViewBuilder let content: () -> Content

    @State private var helpOpen = false
    @State private var settingsOpen = false
    @State private var useCasesOpen = false
    @State private var noticeOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 設定ボタンの円。中のアイコンが `.body` で伸縮するので、円も同じ比率で伸ばす。
    @ScaledMetric(relativeTo: .body) private var settingsButtonSize: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 40)
                content()
                footer
                    .padding(.top, 56)
            }
            .padding(.horizontal, Theme.Layout.pageHorizontalPadding)
            .padding(.vertical, 24)
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
        .sheet(isPresented: $settingsOpen) { SettingsView() }
        // 開始した瞬間に畳む。人前で回すときに開きっぱなしを踏まないための保険
        .onChange(of: busy) { _, isBusy in
            if isBusy { helpOpen = false }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                // 既定サイズでは従来の 34pt と同じ。Dynamic Type に追従させるためテキストスタイルで指定する
                Text(title)
                    .font(Theme.Typography.font(.largeTitle, weight: .black))
                    .tracking(-1)
                    .foregroundStyle(Theme.ivory)
                    .accessibilityAddTraits(.isHeader)
                Text(tagline)
                    .font(Theme.Typography.font(.subheadline))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            settingsButton
        }
    }

    private var settingsButton: some View {
        Button {
            settingsOpen = true
        } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.muted)
                .frame(width: settingsButtonSize, height: settingsButtonSize)
                .background(Circle().fill(Theme.ink800))
                .overlay(Circle().strokeBorder(Theme.ink700))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(locksControls)
        .accessibilityLabel(L10n.settingsTitle)
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
