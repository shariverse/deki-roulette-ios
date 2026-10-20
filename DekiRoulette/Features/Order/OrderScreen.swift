import SwiftUI

struct OrderScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    let model: OrderModel
    @AppStorage(Config.hapticsEnabledKey) private var hapticsEnabled = true
    /// 共有シートに本文と一緒に渡す結果の画像。結果ごとに 1 回だけ描く（`shareImageKey` の変化で `.task` が描き直す）。
    @State private var shareImage: UIImage?

    var body: some View {
        PageFrame(
            title: L10n.orderTitle,
            tagline: L10n.orderTagline,
            busy: model.revealing,
            useCases: L10n.orderUseCases
        ) {
            Text(L10n.orderHelpBasic)
            HelpHeading(text: L10n.orderHelpAimTitle)
            Text(L10n.orderHelpAim)
            Text(L10n.orderHelpAimStealth)
            Text(L10n.orderHelpAimRandom)
        } content: {
            AdaptiveStack(horizontal: regular, alignment: .center, spacing: Theme.Layout.columnSpacing) {
                resultSection
                ItemListView(
                    items: model.items,
                    marks: model.marks,
                    busy: model.revealing,
                    concealMarks: model.revealing || model.ordered != nil,
                    atCapacity: model.atCapacity,
                    onAdd: { model.addItems($0) },
                    onRemove: { model.removeItem(id: $0) },
                    onRemoveAll: { model.removeAll() },
                    onRestore: { model.restore($0, at: $1) },
                    onLongPress: { model.cycleMark(id: $0) },
                    onLoad: { model.replaceItems($0) },
                    onSetAppearance: { model.setAppearance($1, for: $0) }
                )
                .frame(maxWidth: regular ? Theme.Layout.listWidthRegular : .infinity)
            }
        }
        // 触覚: 行が 1 件現れるごとの刻みと、全件そろった手応え。設定で OFF にできる
        .sensoryFeedback(trigger: model.revealTick) { _, _ in
            hapticsEnabled ? .selection : nil
        }
        .sensoryFeedback(trigger: model.revealing) { wasRevealing, revealing in
            hapticsEnabled && wasRevealing && !revealing ? .success : nil
        }
        // 演出が終わって結果が出ているときに 1 回だけ共有画像を描く。演出中・結果が無いときは描かず、前の画像も捨てる。
        // 渡すのは並べ替え後のラベルと見た目だけ（先頭・末尾の指定や印は渡さない）
        .task(id: shareImageKey) {
            guard shareImageKey != nil, let ordered = model.ordered else {
                shareImage = nil
                return
            }
            shareImage = ShareImageRenderer.order(labels: ordered.map(\.label), appearances: ordered.map(\.appearance))
        }
    }

    /// 共有画像を描き直す鍵。演出が終わって結果が出ている間だけ値を持ち、並べ替えるたび（`resultId`）に変わる（結果の表示の `.id` と同じ）。
    /// 結果を出したまま項目の見た目を変えたときも描き直す（結果の表示は出し直さない）。
    private var shareImageKey: ShareImageKey? {
        guard let ordered = model.ordered, !model.revealing else { return nil }
        return ShareImageKey(resultId: model.resultId, appearances: ordered.map(\.appearance))
    }

    private struct ShareImageKey: Hashable {
        let resultId: UUID
        let appearances: [ItemAppearance]
    }

    private var regular: Bool { sizeClass == .regular }

    private var resultSection: some View {
        VStack(spacing: 24) {
            OrderResultView(
                ordered: model.ordered,
                resultId: model.resultId,
                revealing: model.revealing,
                reducedMotion: reduceMotion
            )

            PrimaryActionButton(
                title: model.revealing ? L10n.orderShuffling : L10n.orderShuffle,
                busy: model.revealing,
                enabled: model.canShuffle,
                action: { model.shuffleItems(reducedMotion: reduceMotion) }
            )

            ZStack {
                // 演出が終わって結果が出ている間だけ出す。結果が変わると作り直す
                if let ordered = model.ordered, !model.revealing {
                    let text = ResultText.order(ordered.map(\.label))
                    ResultActions(shareText: ResultText.share(text, appName: L10n.appName), shareImage: shareImage)
                        .id(model.resultId)
                }
            }
            // 共有ボタンの有無で上のボタンが動かないよう高さを固定する。大きい文字では最小高さだけ残す
            .frame(
                minHeight: Theme.Layout.resultActionsHeight,
                maxHeight: TypeLayout.growsFixedAreas(for: typeSize) ? nil : Theme.Layout.resultActionsHeight
            )
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    OrderScreen(model: OrderModel(items: ItemLabel.makeItems(L10n.orderDefaultItems)))
        .environment(SavedListsModel(lists: []))
}

#Preview("AX5") {
    OrderScreen(model: OrderModel(items: ItemLabel.makeItems(L10n.orderDefaultItems)))
        .dynamicTypeSize(.accessibility5)
}
