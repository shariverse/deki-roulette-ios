import SwiftUI

/// 順位付きの結果。1 件ずつ現れる遅延をここで掛ける。
struct OrderResultView: View {
    let ordered: [Item]?
    let resultId: UUID
    let revealing: Bool
    let reducedMotion: Bool

    @Environment(\.dynamicTypeSize) private var typeSize
    /// 順位の欄。2 桁の数字が入る幅を、文字と同じ比率で伸ばす。
    @ScaledMetric(relativeTo: .subheadline) private var rankWidth: CGFloat = 20

    var body: some View {
        Group {
            if let ordered {
                VStack(spacing: 6) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, item in
                        row(rank: index + 1, item: item)
                            // 1 件ずつ遅らせて出す。全部そろうまで先の順位が読めないようにする。
                            .revealOnAppear(
                                delay: RevealTiming.delay(index: index, reducedMotion: reducedMotion),
                                reducedMotion: reducedMotion
                            )
                    }
                }
                // 結果が変わるたびに行を作り直して演出をやり直す
                .id(resultId)
                .accessibilityLabel(L10n.orderResultTitle)
            } else {
                Text(revealing ? L10n.orderShuffling : L10n.orderResultPlaceholder)
                    .font(Theme.Typography.font(.caption))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Theme.ink600, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
            }
        }
        .frame(maxWidth: 384)
    }

    private func row(rank: Int, item: Item) -> some View {
        let top = rank == 1
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(Theme.Typography.font(.subheadline, weight: .black).monospacedDigit())
                .foregroundStyle(top ? Theme.gold : Theme.muted)
                .frame(width: rankWidth, alignment: .trailing)
                .accessibilityLabel(L10n.orderRankAccessibilityLabel(rank))
            // 絵文字の項目はラベルの前に絵文字を置く（項目リストの行と同じ。読み上げはラベルだけ）
            if case .emoji(let emoji) = item.appearance {
                Text(String(emoji))
                    .font(Theme.Typography.font(.subheadline))
                    .accessibilityHidden(true)
            }
            Text(item.label)
                .font(Theme.Typography.font(.subheadline, weight: .bold))
                .foregroundStyle(top ? Theme.gold : Theme.ivory)
                .lineLimit(TypeLayout.labelLineLimit(for: typeSize))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(top ? Theme.gold.opacity(0.1) : Theme.ink800, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(top ? Theme.gold.opacity(0.6) : Theme.ink700, lineWidth: 1)
        )
    }
}

#Preview("Result") {
    OrderResultView(
        ordered: ItemLabel.makeItems(["A チーム", "B チーム", "C チーム", "D チーム"]),
        resultId: UUID(),
        revealing: false,
        reducedMotion: false
    )
    .padding()
    .background(Theme.ink900)
}

#Preview("Placeholder") {
    OrderResultView(ordered: nil, resultId: UUID(), revealing: false, reducedMotion: false)
        .padding()
        .background(Theme.ink900)
}

#Preview("Result AX5") {
    OrderResultView(
        ordered: ItemLabel.makeItems(["A チーム", "B チーム", "C チーム", "D チーム"]),
        resultId: UUID(),
        revealing: false,
        reducedMotion: false
    )
    .padding()
    .background(Theme.ink900)
    .dynamicTypeSize(.accessibility5)
}
