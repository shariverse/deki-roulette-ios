import SwiftUI

/// 項目の色と絵文字の編集。項目リストの見出し行のメニューから開くシートで、全項目を並べ、行を押すと 1 項目の編集に進む。
/// 渡すのは項目（id・ラベル・見た目）だけで、指定・印は受け取らない（ここでは印を出さない）。
struct ItemAppearanceEditor: View {
    let items: [Item]
    let onChange: (UUID, ItemAppearance) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item.id) {
                            ItemAppearanceRow(item: item, color: Theme.sliceAccent(in: items, at: index))
                        }
                        .listRowBackground(Theme.ink800)
                    }
                } footer: {
                    Text(L10n.appearanceEditorFooter)
                        .foregroundStyle(Theme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink900.ignoresSafeArea())
            .navigationTitle(L10n.appearanceEditorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                ItemAppearanceDetail(
                    item: items.first { $0.id == id },
                    onChange: { onChange(id, $0) }
                )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.close) { dismiss() }
                        .foregroundStyle(Theme.ivory)
                }
            }
            .toolbarBackground(Theme.ink800, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

/// 一覧の 1 行。色見本・絵文字・ラベルと、今の見た目の名前。
private struct ItemAppearanceRow: View {
    let item: Item
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            if case .emoji(let emoji) = item.appearance {
                Text(String(emoji))
                    .accessibilityHidden(true)
            }
            Text(item.label)
                .font(.subheadline)
                .foregroundStyle(Theme.ivory)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(L10n.appearanceDescription(item.appearance))
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 1 項目の編集。10 色から選ぶか、絵文字を 1 文字入力するか、自動に戻す。
private struct ItemAppearanceDetail: View {
    /// 編集中に一覧から消えたとき（ありえないが）は nil。
    let item: Item?
    let onChange: (ItemAppearance) -> Void

    @State private var emojiText = ""
    /// 直前の入力が絵文字 1 文字として受け付けられなかった。
    @State private var rejected = false
    @FocusState private var emojiFocused: Bool
    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 36

    private var appearance: ItemAppearance { item?.appearance ?? .auto }

    /// 見た目が絵文字のときの絵文字。入力欄の表示と突き合わせる。
    private var currentEmoji: String {
        if case .emoji(let emoji) = appearance { return String(emoji) }
        return ""
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: swatchSize + 12), spacing: 12)], spacing: 12) {
                    ForEach(SliceColor.allCases, id: \.self) { color in
                        colorButton(color)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Theme.ink800)
            } header: {
                Text(L10n.appearanceColorSection)
                    .foregroundStyle(Theme.muted)
            }

            Section {
                TextField(L10n.appearanceEmojiPlaceholder, text: $emojiText)
                    .focused($emojiFocused)
                    .foregroundStyle(Theme.ivory)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .listRowBackground(Theme.ink800)
                    .onChange(of: emojiText) { _, text in handleEmojiInput(text) }
            } header: {
                Text(L10n.appearanceEmojiSection)
                    .foregroundStyle(Theme.muted)
            } footer: {
                Text(rejected ? L10n.appearanceEmojiInvalid : L10n.appearanceEmojiFooter)
                    .foregroundStyle(Theme.muted)
            }

            Section {
                Button(L10n.appearanceReset) {
                    rejected = false
                    onChange(.auto)
                    emojiText = ""
                }
                .foregroundStyle(appearance == .auto ? Theme.muted : Theme.ivory)
                .disabled(appearance == .auto)
                .listRowBackground(Theme.ink800)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ink900.ignoresSafeArea())
        .navigationTitle(item?.label ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { emojiText = currentEmoji }
    }

    private func colorButton(_ color: SliceColor) -> some View {
        let selected = appearance == .color(color)
        return Button {
            rejected = false
            emojiFocused = false
            onChange(.color(color))
            emojiText = ""
        } label: {
            ZStack {
                // 盤面と同じ塗り。外観に依らず固定なので、地との境目に細い枠を付ける
                Circle().fill(Theme.sliceColors[color.paletteIndex])
                Circle().strokeBorder(Theme.ink600, lineWidth: 1)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: swatchSize * 0.4, weight: .bold))
                        .foregroundStyle(Theme.onSlice)
                }
            }
            .frame(width: swatchSize, height: swatchSize)
            .padding(4)
            .overlay(Circle().strokeBorder(selected ? Theme.ivory : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.colorName(color))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 入力欄の変化。絵文字 1 文字なら見た目にし（2 文字以上は先頭だけ残す）、絵文字でなければ前の値に戻して注意を出す。
    /// 空にしたら、絵文字の項目は自動に戻す。
    private func handleEmojiInput(_ text: String) {
        // 見た目と同じ表示に戻した（または戻った）だけの変化は何もしない
        guard text != currentEmoji else { return }
        if text.isEmpty {
            rejected = false
            onChange(.auto)
            return
        }
        guard let emoji = EmojiInput.normalize(text) else {
            rejected = true
            emojiText = currentEmoji
            return
        }
        rejected = false
        onChange(.emoji(emoji))
        if String(emoji) != text { emojiText = String(emoji) }
    }
}

#Preview {
    ItemAppearanceEditor(
        items: [
            Item(label: "ラーメン"),
            Item(label: "カレー", appearance: .color(.blue)),
            Item(label: "寿司", appearance: .emoji("🍣")),
        ],
        onChange: { _, _ in }
    )
    .fontDesign(.rounded)
}
