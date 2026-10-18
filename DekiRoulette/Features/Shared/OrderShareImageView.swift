import SwiftUI

/// 共有シートに渡す順番決めの結果画像。一辺 `side` の正方形に、順位の行（カード）を上から並べ、アプリ名（`L10n.appName` の文字だけ）を下に置く。
/// 寸法は `ShareImageLayout.order(side:)`、地と文字はルーレットの画像（`RouletteShareImageView`）と同じ固定色（`Theme.shareBackground` / `shareInk`）。
/// 行は `ResultText.order` と同じ「1. ラベル」の並びで、1 位は画面（`OrderResultView`）と同じ `gold`、他は `muted` 系。
/// 行の色のトークンは外観で変わるが、`ShareImageRenderer` がダークに固定して焼くので画像は端末の外観に依らない。
/// 行数が上限を超えるときは上限より 1 つ少ない件数を並べ、最後の行を「ほか M 件」にする（`Order.rows(count:)`）。長いラベルは `labelLimit` で省略する。
///
/// 絵文字の項目は「1. 🍣 ラベル」の形にする（`WheelLabel.display` で絵文字ぶん 1 文字短く省略する）。
///
/// 入力は並べ替え後のラベルと見た目の配列だけで、先頭・末尾の指定や印を受け取る口は持たない（SPEC §6.5・§7.3）。
struct OrderShareImageView: View {
    /// 並べ替え後のラベル（1 位から順）。
    let labels: [String]
    /// `labels` と同じ並びの見た目。足りない分は自動として扱う。
    var appearances: [ItemAppearance] = []
    /// 画像の一辺（描画の単位。`ShareImageRenderer` が `scale` 1 で焼くので px と一致する）。
    var side = ShareImageLayout.defaultSide

    /// 行の角丸（行の高さに対する割合）。画面の行（高さ約 40pt に角丸 12pt）と同じ比率。
    private static let cornerRatio = 0.3
    /// 行の枠線の太さ（一辺に対する割合）。1080px で 2px。
    private static let borderRatio = 1.0 / 540

    var body: some View {
        let layout = ShareImageLayout.order(side: side)
        let count = labels.count
        let rows = layout.rows(count: count)
        ZStack {
            Theme.shareBackground

            ForEach(0..<rows.shown, id: \.self) { index in
                row(rank: index + 1, text: WheelLabel.display(labels[index], appearance: appearance(at: index), limit: layout.labelLimit), layout: layout)
                    .position(x: layout.rowsLeft + layout.rowWidth / 2, y: layout.rowTop(index: index, count: count) + layout.rowHeight / 2)
            }
            if rows.omitted > 0 {
                row(rank: nil, text: L10n.shareOrderOthers(rows.omitted), layout: layout)
                    .position(x: layout.rowsLeft + layout.rowWidth / 2, y: layout.rowTop(index: rows.shown, count: count) + layout.rowHeight / 2)
            }

            Text(L10n.appName)
                .font(.system(size: ShareImageLayout.brandFontSize(side: side), weight: .bold))
                .foregroundStyle(Theme.shareInk)
                .lineLimit(1)
                .position(x: side / 2, y: ShareImageLayout.brandCenterY(side: side))
        }
        .frame(width: side, height: side)
    }

    private func appearance(at index: Int) -> ItemAppearance {
        appearances.indices.contains(index) ? appearances[index] : .auto
    }

    /// 順位の行。`rank` が nil のときは省略した件数の行（順位の欄は空、文字は `muted`）。
    private func row(rank: Int?, text: String, layout: ShareImageLayout.Order) -> some View {
        let top = rank == 1
        let radius = layout.rowHeight * Self.cornerRatio
        return HStack(spacing: layout.rankGap) {
            Text(rank.map { "\($0)." } ?? "")
                .font(.system(size: layout.fontSize, weight: .black).monospacedDigit())
                .foregroundStyle(top ? Theme.gold : Theme.muted)
                .frame(width: layout.rankWidth, alignment: .trailing)
            Text(text)
                .font(.system(size: layout.fontSize, weight: .bold))
                .foregroundStyle(top ? Theme.gold : rank == nil ? Theme.muted : Theme.ivory)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, layout.rowPadding)
        .frame(width: layout.rowWidth, height: layout.rowHeight)
        .background(top ? Theme.gold.opacity(0.1) : Theme.ink800, in: .rect(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(top ? Theme.gold.opacity(0.6) : Theme.ink700, lineWidth: layout.side * Self.borderRatio)
        )
    }
}

extension ShareImageRenderer {
    /// 順番決めの結果画像。`labels` は並べ替え後のラベル（1 位から順）、`appearances` は同じ並びの見た目。
    static func order(
        labels: [String], appearances: [ItemAppearance] = [], side: Double = ShareImageLayout.defaultSide
    ) -> UIImage? {
        render(OrderShareImageView(labels: labels, appearances: appearances, side: side), side: side)
    }
}

#Preview("4 件") {
    OrderShareImageView(labels: ["A チーム", "B チーム", "C チーム", "D チーム"])
        .scaleEffect(0.3)
        .frame(width: 324, height: 324)
}

#Preview("24 件") {
    OrderShareImageView(labels: (1...24).map { "項目\($0)" })
        .scaleEffect(0.3)
        .frame(width: 324, height: 324)
}
