import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 結果の下に置く幅広の「結果を共有」。押すとメニューで共有先（画像付きの共有シート・X・LINE）を選ばせる。
/// 両画面で同じ見た目・同じ高さ（`Theme.Layout.resultActionsHeight`）にする。
/// 押しただけではメニューが出るだけでアプリを離れない（X・LINE の小さなボタンを誤って押していたため、1 つにまとめた）。
/// 本文だけを写したいときは共有シートの「コピー」を使う（専用のコピーボタンは置かない）。
/// `shareImage` があれば共有シートに本文と一緒に結果の画像（`ShareImageFile`）を渡し、無ければ本文だけを渡す。
/// X・LINE は本文だけを Web の投稿画面の URL（`ShareIntent`）で開く（画像は付かない。確認は挟まない）。投稿は利用者が各アプリで確定する。
struct ResultActions: View {
    /// 共有シートと LINE に渡す本文（ハッシュタグ入り。`ResultText.share`）。
    let shareText: String
    /// X に渡す本文。X の上限に収めたもの（順番決めは `ResultText.orderPost`）。nil なら `shareText` を渡す。
    var postText: String? = nil
    /// 共有シートに本文と一緒に渡す結果の画像。nil なら本文だけを共有する。
    var shareImage: UIImage? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            shareSheetItem
            Button {
                openURL(ShareIntent.xPost(text: postText ?? shareText))
            } label: {
                Label(L10n.shareToX, systemImage: "square.and.pencil")
            }
            Button {
                openURL(ShareIntent.lineShare(text: shareText))
            } label: {
                Label(L10n.shareToLINE, systemImage: "paperplane")
            }
        } label: {
            ResultActionLabel(title: L10n.shareResult)
        }
        .buttonStyle(.plain)
        // 盤面の下から上へ開いても、項目を上から「共有シート → X → LINE」の順に保つ
        .menuOrder(.fixed)
        .frame(maxWidth: Theme.Layout.resultActionsMaxWidth)
    }

    /// 共有シートを開く項目。画像を描き終える前（`shareImage` が nil）は本文だけを渡すので「画像付き」と言わない名前にする。
    @ViewBuilder
    private var shareSheetItem: some View {
        if let shareImage {
            // 画像を本体（X・Instagram・LINE は画像として受け取る）、本文は添える。プレビューの題名はアプリ名
            ShareLink(
                item: ShareImageFile(image: shareImage),
                message: Text(shareText),
                preview: SharePreview(L10n.appName, image: Image(uiImage: shareImage))
            ) {
                Label(L10n.shareWithImage, systemImage: "photo")
            }
        } else {
            ShareLink(item: shareText) {
                Label(L10n.shareTextOnly, systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// 共有シートに渡す結果の画像。PNG で書き出す（盤面の線と文字がにじまない）。
/// 画像は `ShareImageRenderer` が描いたもので、盤面と結果とアプリ名だけが載っている。
struct ShareImageFile: Transferable, Sendable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { file in
            guard let data = file.image.pngData() else { throw ShareImageError.encodingFailed }
            return data
        }
    }
}

enum ShareImageError: Error {
    /// `UIImage` を PNG にできなかった。
    case encodingFailed
}

/// 「結果を共有」のラベル。地は塗らず（ページの地のまま）、`ink600` の枠と `ivory` の文字にする。
/// 開始ボタン（`flare` の塗りと光彩）より控えめにして主従を保ち、`flare` / `gold` は使わない。
/// 文字の後ろの `chevron.down` で、押すと選ぶメニューが開くことを示す。
private struct ResultActionLabel: View {
    let title: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline.weight(.bold))
                // 名前は文字から読ませる（「結果を共有」）
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.bold))
                // アクセシビリティサイズでは省略せず 2 行まで折り返す（行の高さも `TypeLayout.growsFixedAreas` で伸びる）
                .lineLimit(TypeLayout.labelLineLimit(for: typeSize))
                .multilineTextAlignment(.center)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.ivory)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: Theme.Layout.resultActionsHeight)
        .contentShape(.capsule)
        .overlay(Capsule().strokeBorder(Theme.ink600, lineWidth: 1.5))
    }
}

#Preview {
    ResultActions(shareText: "ルーレットで「ラーメン」に決まりました！\n\n#デキレーレット")
        .padding()
        .background(Theme.ink900)
}
