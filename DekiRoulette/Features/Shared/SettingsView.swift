import SwiftUI

/// ヘッダ右上のアイコンから開く設定。触覚フィードバックと効果音の切替、ルーレットの詳細設定（光彩の色・3D 表示）、
/// 外観（自動・ライト・ダーク。visionOS には出さない）とアプリアイコンの選択、項目の初期化、著作権・ライセンスの項目を置く。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Config.hapticsEnabledKey) private var hapticsEnabled = true
    @AppStorage(Config.soundEnabledKey) private var soundEnabled = true
    // 両画面のモデルは RootView が environment に流している。どちらのタブから開いても両方を戻せる。
    @Environment(RouletteModel.self) private var rouletteModel
    @Environment(OrderModel.self) private var orderModel
    @State private var appIcons = AppIconModel(source: UIApplicationIconSource())

    /// 確認ダイアログを出している対象。
    private enum ResetTarget: Identifiable {
        case roulette
        case order

        var id: Self { self }
    }

    @State private var resetTarget: ResetTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 文言はこの見出しだけ。何に使うかの説明は置かない（長押しの存在を示唆しないため）
                    SettingsToggle(title: L10n.hapticsTitle, isOn: $hapticsEnabled)

                    SettingsSection(title: L10n.soundTitle) {
                        Toggle(L10n.soundToggle, isOn: $soundEnabled)
                            .font(Theme.Typography.font(.subheadline))
                            .foregroundStyle(Theme.ivory)
                            .tint(Theme.ivory)
                        Text(L10n.soundNote)
                            .font(Theme.Typography.font(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                    SettingsLinkRow(title: L10n.rouletteAdvancedTitle) {
                        RouletteAdvancedSettingsView()
                    }
                    // visionOS では外観を当てずにシステムに従うので、項目ごと出さない
                    #if !os(visionOS)
                    SettingsLinkRow(title: L10n.appearanceTitle) {
                        AppearanceSettingsView()
                    }
                    #endif
                    // 代替アイコンに切り替えられない端末では項目ごと出さない
                    if appIcons.isSupported {
                        SettingsLinkRow(title: L10n.appIconTitle) {
                            AppIconSettingsView(model: appIcons)
                        }
                    }
                    SettingsSection(title: L10n.resetItemsTitle) {
                        Text(L10n.resetItemsDescription)
                            .font(Theme.Typography.font(.caption))
                            .foregroundStyle(Theme.muted)
                            .lineSpacing(3)
                        // ルーレットのスピン中は押せなくする（順番決めのタブから開いたときに、回っている盤面の項目を戻さない）
                        resetButton(L10n.resetItemsRoulette, target: .roulette, disabled: rouletteModel.spinning)
                        resetButton(L10n.resetItemsOrder, target: .order, disabled: false)
                    }
                    SettingsSection(title: L10n.copyrightTitle) {
                        Text(L10n.copyrightOwner)
                            .font(Theme.Typography.font(.subheadline))
                            .foregroundStyle(Theme.ivory)
                            .lineSpacing(3)
                        Text(L10n.copyright)
                            .font(Theme.Typography.font(.caption))
                            .foregroundStyle(Theme.muted)
                        Text(L10n.trademarkNotice)
                            .font(Theme.Typography.font(.caption))
                            .foregroundStyle(Theme.muted)
                            .lineSpacing(3)
                    }
                    SettingsLinkRow(title: L10n.licensesTitle) {
                        LicensesView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Theme.ink900.ignoresSafeArea())
            .appNavigationTitle(L10n.settingsTitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.close) { dismiss() }
                        .foregroundStyle(Theme.ivory)
                        .font(Theme.Typography.barButton)
                }
            }
            .toolbarBackground(Theme.ink800, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .confirmationDialog(
                L10n.resetItemsConfirm(screenName(resetTarget)),
                isPresented: Binding(
                    get: { resetTarget != nil },
                    set: { if !$0 { resetTarget = nil } }
                ),
                titleVisibility: .visible,
                presenting: resetTarget
            ) { target in
                Button(L10n.resetItemsAction, role: .destructive) { reset(target) }
            } message: { _ in
                Text(L10n.resetItemsMessage)
            }
        }
    }

    private func resetButton(_ title: String, target: ResetTarget, disabled: Bool) -> some View {
        Button {
            resetTarget = target
        } label: {
            HStack {
                Text(title)
                    .font(Theme.Typography.font(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.ivory)
                Spacer(minLength: 0)
                Image(systemName: "arrow.counterclockwise")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.ink700, in: .rect(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        // 文字と記号の色は固定なので、無効のときは薄くして押せないことを見せる
        .opacity(disabled ? 0.45 : 1)
    }

    private func screenName(_ target: ResetTarget?) -> String {
        switch target {
        case .roulette, nil: L10n.rouletteNavLabel
        case .order: L10n.orderNavLabel
        }
    }

    private func reset(_ target: ResetTarget) {
        switch target {
        case .roulette: rouletteModel.resetItems()
        case .order: orderModel.resetItems()
        }
    }
}

/// 設定から進む「ルーレットの詳細設定」。止まったスライスの光彩の色、スピンの演出（全体と演出ごとの ON/OFF）、3D 表示の ON/OFF と傾きの基準を選ぶ。
private struct RouletteAdvancedSettingsView: View {
    @AppStorage(Config.glowStyleKey) private var glowStyle = GlowStyle.default
    private let spinEffects = SpinEffectsSetting()
    @AppStorage(Config.wheel3DEnabledKey) private var wheel3DEnabled = false
    @AppStorage(Config.tiltReferenceKey) private var tiltReference = TiltReference.default

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection(title: L10n.glowStyleTitle) {
                    ForEach(GlowStyle.allCases, id: \.self) { style in
                        SettingsChoiceRow(title: L10n.glowStyleName(style), selected: glowStyle == style) {
                            glowStyle = style
                        }
                    }
                }
                SettingsSection(title: L10n.spinEffectsTitle) {
                    Toggle(L10n.spinEffectsEnabled, isOn: spinEffects.enabledBinding)
                        .font(Theme.Typography.font(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.ivory)
                        .tint(Theme.ivory)
                    Divider()
                        .overlay(Theme.ink700)
                    // 全体が OFF の間も個別の選択は残し、選べないことだけを見せる（傾きの基準と同じ）
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(SpinEffectItem.allCases, id: \.self) { item in
                            Toggle(L10n.spinEffectName(item), isOn: spinEffects.binding(for: item))
                                .font(Theme.Typography.font(.subheadline))
                                .foregroundStyle(Theme.ivory)
                                .tint(Theme.ivory)
                        }
                        Text(L10n.spinEffectsSoundNote)
                            .font(Theme.Typography.font(.caption))
                            .foregroundStyle(Theme.muted)
                    }
                    .disabled(!spinEffects.enabled)
                    .opacity(spinEffects.enabled ? 1 : 0.5)
                }
                SettingsToggle(title: L10n.wheel3DTitle, isOn: $wheel3DEnabled)
                // 傾きの基準は 3D 表示のときだけ効く。OFF の間も選んだ値は残し、選べないことだけを見せる
                SettingsSection(title: L10n.tiltReferenceTitle) {
                    ForEach(TiltReference.allCases, id: \.self) { reference in
                        SettingsChoiceRow(title: L10n.tiltReferenceName(reference), selected: tiltReference == reference) {
                            tiltReference = reference
                        }
                    }
                }
                .disabled(!wheel3DEnabled)
                .opacity(wheel3DEnabled ? 1 : 0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Theme.ink900.ignoresSafeArea())
        .appNavigationTitle(L10n.rouletteAdvancedTitle)
        .toolbarBackground(Theme.ink800, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// 設定から進む「外観」。自動（端末の外観に従う）・ライト・ダークから選び、押したらその場で `Config.appearanceModeKey` に書く。
/// アプリの根（`DekiRouletteApp`）が同じキーを読んで当てるので、開いているこのシートとその下の画面もその場で切り替わる。
private struct AppearanceSettingsView: View {
    @AppStorage(Config.appearanceModeKey) private var appearanceMode = AppearanceMode.default

    var body: some View {
        ScrollView {
            SettingsCard {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    SettingsChoiceRow(title: L10n.appearanceModeName(mode), selected: appearanceMode == mode) {
                        appearanceMode = mode
                    }
                }
                Text(L10n.appearanceNote)
                    .font(Theme.Typography.font(.caption))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Theme.ink900.ignoresSafeArea())
        .appNavigationTitle(L10n.appearanceTitle)
        .toolbarBackground(Theme.ink800, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// 設定から進む「アプリアイコン」。既定のアイコンと代替アイコンをグリッドに並べ、選んだものに切り替える。
/// 選択中の表示は `AppIconModel`（`alternateIconName`）に従う。切り替えると iOS が確認のアラートを出す（消せない）。
private struct AppIconSettingsView: View {
    @Bindable var model: AppIconModel

    /// 列の幅の下限。iPhone の縦では 3 列、横幅のある画面ではそれより多く並ぶ。
    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            SettingsCard {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppIconChoice.allCases, id: \.self) { choice in
                        AppIconCell(choice: choice, selected: model.current == choice) {
                            Task { await model.select(choice) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Theme.ink900.ignoresSafeArea())
        .appNavigationTitle(L10n.appIconTitle)
        .toolbarBackground(Theme.ink800, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { model.refresh() }
        .alert(L10n.appIconFailedTitle, isPresented: $model.failed) {
            Button(L10n.close, role: .cancel) {}
        } message: {
            Text(L10n.appIconFailedMessage)
        }
    }
}

/// 設定から進む「ライセンス」。同梱したもの（`Licenses.all`）を並べ、行から全文に進む。指定・印は受け取らない。
private struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.licensesDescription)
                    .font(Theme.Typography.font(.caption))
                    .foregroundStyle(Theme.muted)
                ForEach(Licenses.all) { entry in
                    LicenseRow(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Theme.ink900.ignoresSafeArea())
        .appNavigationTitle(L10n.licensesTitle)
        .toolbarBackground(Theme.ink800, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// ライセンスの一覧の 1 行。名前とライセンスの名前を並べ、全文の画面に進む（`SettingsLinkRow` と同じ枠）。
private struct LicenseRow: View {
    let entry: LicenseEntry

    var body: some View {
        NavigationLink {
            LicenseDetailView(entry: entry)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                        .font(Theme.Typography.font(.callout, weight: .bold))
                        .foregroundStyle(Theme.ivory)
                    Text(entry.licenseName)
                        .font(Theme.Typography.font(.caption))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(Theme.ink800, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.ink700, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 1 件のライセンスの全文。名前・著作権・ライセンスの名前と、バンドルの全文を原文の語句のまま出す（訳さない）。全文は選んでコピーできる。
private struct LicenseDetailView: View {
    let entry: LicenseEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard {
                    Text(entry.name)
                        .font(Theme.Typography.font(.callout, weight: .bold))
                        .foregroundStyle(Theme.ivory)
                        .accessibilityAddTraits(.isHeader)
                    Text(entry.copyright)
                        .font(Theme.Typography.font(.caption))
                        .foregroundStyle(Theme.muted)
                    Text(entry.licenseName)
                        .font(Theme.Typography.font(.caption))
                        .foregroundStyle(Theme.muted)
                }
                if let text = entry.text() {
                    // 原文の固定の改行のまま折り返すと行がばらばらに切れるので、段落ごとに組み直して画面の幅で折り返す（語句は変えない）
                    SettingsCard {
                        ForEach(Array(LicenseText.paragraphs(text).enumerated()), id: \.offset) { _, paragraph in
                            if LicenseText.isRule(paragraph) {
                                // 区切りの線は折り返さず、幅に収まるよう縮める（線の文字は原文のまま）
                                Text(paragraph)
                                    .font(Theme.Typography.font(.caption))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.3)
                            } else {
                                Text(paragraph)
                                    .font(Theme.Typography.font(.caption))
                                    .foregroundStyle(Theme.ivory)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Theme.ink900.ignoresSafeArea())
        .appNavigationTitle(entry.name)
        .toolbarBackground(Theme.ink800, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// アプリアイコンの候補 1 つ。見本の画像と名前を縦に並べ、選ばれているものは画像を輪で囲む。
/// 読み上げは `SettingsChoiceRow` と同じく、名前（`Text`）と選択中かどうか（`.isSelected`）だけにする。
private struct AppIconCell: View {
    let choice: AppIconChoice
    let selected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// 見本の一辺。`scripts/make-icon.swift` の `previewPoints` と同じにする（見本の画像はこの大きさの @2x・@3x）。
    private let iconSize: CGFloat = 64
    /// 見本の角の丸み。iOS のアイコンの形（一辺の約 22%）に合わせる。
    private var iconCornerRadius: CGFloat { iconSize * 0.2237 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(choice.previewImageName)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    // 明るい地の見本が枠の明るい背景に溶けないよう、細い縁を付ける
                    .overlay {
                        RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
                            .strokeBorder(Theme.ink700, lineWidth: 1)
                    }
                    .padding(4)
                    .overlay {
                        RoundedRectangle(cornerRadius: iconCornerRadius + 4, style: .continuous)
                            .strokeBorder(Theme.ivory, lineWidth: 3)
                            .opacity(selected ? 1 : 0)
                    }
                    .accessibilityHidden(true)
                Text(L10n.appIconName(choice))
                    .font(Theme.Typography.font(.caption, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? Theme.ivory : Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(TypeLayout.labelLineLimit(for: typeSize))
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 設定の選択肢 1 行。選ばれている行にだけチェックを出す。
private struct SettingsChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.Typography.font(.subheadline))
                    .foregroundStyle(Theme.ivory)
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.ivory)
                    .opacity(selected ? 1 : 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 設定から別の画面へ進む 1 行。枠の中に見出しと山かっこを並べる。
private struct SettingsLinkRow<Destination: View>: View {
    let title: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(title)
                    .font(Theme.Typography.font(.callout, weight: .bold))
                    .foregroundStyle(Theme.ivory)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(Theme.ink800, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.ink700, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 設定の ON/OFF 1 項目。枠の中に見出しとスイッチを並べる。
private struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(Theme.Typography.font(.callout, weight: .bold))
                .foregroundStyle(Theme.ivory)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Theme.ink800, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.ink700, lineWidth: 1)
        }
    }
}

/// 設定の 1 項目。見出しと、枠で囲んだ中身。
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.Typography.font(.callout, weight: .bold))
                .foregroundStyle(Theme.ivory)
                .accessibilityAddTraits(.isHeader)

            SettingsCard(content: content)
        }
    }
}

/// 設定の枠。中身を縦に並べて囲む。
private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Theme.ink800, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.ink700, lineWidth: 1)
        }
    }
}

#Preview {
    SettingsView()
        .environment(RouletteModel(items: ItemLabel.makeItems(L10n.defaultItems)))
        .environment(OrderModel(items: ItemLabel.makeItems(L10n.orderDefaultItems)))
        .appTypography()
}
