import SwiftUI

/// 保存したリストの管理。名前の変更と削除だけを置く（読み込みは項目リストのメニューから）。
struct SavedListsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SavedListsModel.self) private var savedLists

    @State private var renaming: SavedList?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if savedLists.lists.isEmpty {
                    emptyHint
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ink900.ignoresSafeArea())
            .appNavigationTitle(L10n.savedListsTitle)
            .toolbar {
                if !savedLists.lists.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                            .foregroundStyle(Theme.ivory)
                            .font(Theme.Typography.barButton)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.close) { dismiss() }
                        .foregroundStyle(Theme.ivory)
                        .font(Theme.Typography.barButton)
                }
            }
            .toolbarBackground(Theme.ink800, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert(
                L10n.renameListTitle,
                isPresented: Binding(
                    get: { renaming != nil },
                    set: { if !$0 { renaming = nil } }
                ),
                presenting: renaming
            ) { list in
                TextField(L10n.saveListNamePlaceholder, text: $newName)
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.rename) { savedLists.rename(id: list.id, to: newName) }
                    .disabled(SavedListName.normalize(newName).isEmpty)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(savedLists.lists) { list in
                row(list)
                    .listRowBackground(Theme.ink900)
                    .listRowSeparatorTint(Theme.ink700)
            }
            .onDelete { offsets in
                for id in offsets.map({ savedLists.lists[$0].id }) {
                    savedLists.delete(id: id)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ list: SavedList) -> some View {
        Button {
            newName = list.name
            renaming = list
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(Theme.Typography.font(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.ivory)
                        .lineLimit(1)
                    Text(L10n.savedListItemCount(list.items.count))
                        .font(Theme.Typography.font(.caption))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink400)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.renameListAccessibilityLabel(list.name))
    }

    private var emptyHint: some View {
        Text(L10n.savedListsEmptyHint)
            .font(Theme.Typography.font(.subheadline))
            .foregroundStyle(Theme.muted)
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
    }
}

#Preview("Lists") {
    SavedListsView()
        .environment(SavedListsModel(lists: [
            SavedList(name: "ランチ", items: ItemLabel.makeItems(["ラーメン", "カレー", "寿司"])),
            SavedList(name: "チーム", items: ItemLabel.makeItems(["A", "B", "C", "D"])),
        ]))
        .appTypography()
}

#Preview("Empty") {
    SavedListsView()
        .environment(SavedListsModel(lists: []))
        .appTypography()
}
