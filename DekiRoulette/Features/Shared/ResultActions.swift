import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 結果の下に置く幅広の「結果を共有」と、その右の X・LINE のロゴのボタン。両画面で同じ見た目・同じ高さ（`Theme.Layout.resultActionsHeight`）にする。
/// 「結果を共有」は押すと直接共有シートを開く。`shareImage` があれば本文と一緒に結果の画像（`ShareImageFile`）を渡し、無ければ本文だけを渡す。
/// 本文だけを写したいときは共有シートの「コピー」を使う（専用のコピーボタンは置かない）。
/// X は本文だけを X アプリの投稿画面（URL スキーム）で開き、開けなければ Web の投稿画面で開く（`ShareIntent.xPostCandidates`）。
/// LINE は本文だけを Web の URL（`ShareIntent.lineShare`）で開く。どちらも画像は付かず、確認は挟まない。投稿は利用者が各アプリで確定する。
/// X・LINE は各社の公式のロゴを元の色のまま枠の中に置く（「X」1 文字の文字のボタンは閉じるボタンと間違えて押されたため）。
struct ResultActions: View {
    /// 共有シートと LINE に渡す本文（ハッシュタグ入り。`ResultText.share`）。
    let shareText: String
    /// X に渡す本文。X の上限に収めたもの（順番決めは `ResultText.orderPost`）。nil なら `shareText` を渡す。
    var postText: String? = nil
    /// 共有シートに本文と一緒に渡す結果の画像。nil なら本文だけを共有する。
    var shareImage: UIImage? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            // アクセシビリティサイズでは横に並べると「結果を共有」が狭くなるので、X・LINE を下の段に回す
            if TypeLayout.growsFixedAreas(for: typeSize) {
                VStack(spacing: 8) {
                    shareButton
                    HStack(spacing: 8) { destinationButtons }
                }
            } else {
                // 「結果を共有」が残りの幅をすべて取り、X・LINE は高さと同じ幅の円
                HStack(spacing: 8) {
                    shareButton
                        .frame(maxWidth: .infinity)
                    destinationButtons
                }
            }
        }
        .frame(maxWidth: Theme.Layout.resultActionsMaxWidth)
    }

    @ViewBuilder
    private var destinationButtons: some View {
        Button {
            open(ShareIntent.xPostCandidates(text: postText ?? shareText))
        } label: {
            ShareLogoLabel(logo: "ShareLogoX", size: Theme.Layout.shareLogoXSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.shareToX)

        Button {
            openURL(ShareIntent.lineShare(text: shareText))
        } label: {
            ShareLogoLabel(logo: "ShareLogoLINE", size: Theme.Layout.shareLogoLINESize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.shareToLINE)
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareImage {
            // 画像を本体（X・Instagram・LINE は画像として受け取る）、本文は添える。プレビューの題名はアプリ名
            ShareLink(
                item: ShareImageFile(image: shareImage),
                message: Text(shareText),
                preview: SharePreview(L10n.appName, image: Image(uiImage: shareImage))
            ) {
                ResultActionLabel(title: L10n.shareResult)
            }
            .buttonStyle(.plain)
        } else {
            ShareLink(item: shareText) {
                ResultActionLabel(title: L10n.shareResult)
            }
            .buttonStyle(.plain)
        }
    }

    /// 候補の URL を前から開き、開けなかったら次を開く。`canOpenURL` を使わないので `LSApplicationQueriesSchemes` は要らない。
    private func open(_ candidates: [URL]) {
        guard let url = candidates.first else { return }
        openURL(url) { accepted in
            if !accepted {
                open(Array(candidates.dropFirst()))
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
        }
        .foregroundStyle(Theme.ivory)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: Theme.Layout.resultActionsHeight)
        .contentShape(.capsule)
        .overlay(Capsule().strokeBorder(Theme.ink600, lineWidth: 1.5))
    }
}

/// X・LINE のロゴのボタンのラベル。「結果を共有」と同じ高さ・同じ `ink600` の枠の円の中に、公式のロゴを元の色のまま置く。
/// ロゴの画像（Asset Catalog の `ShareLogoX` / `ShareLogoLINE`）は比率・色を変えずに縮めるだけ。X は外観で黒と白を切り替える。
private struct ShareLogoLabel: View {
    let logo: String
    let size: CGFloat

    var body: some View {
        Image(logo)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            // 名前はボタンの accessibilityLabel から読ませる
            .accessibilityHidden(true)
            .frame(width: Theme.Layout.resultActionsHeight, height: Theme.Layout.resultActionsHeight)
            .contentShape(.circle)
            .overlay(Circle().strokeBorder(Theme.ink600, lineWidth: 1.5))
    }
}

#Preview {
    ResultActions(shareText: "ルーレットで「ラーメン」に決まりました！\n\n#デキレーレット")
        .padding()
        .background(Theme.ink900)
}
