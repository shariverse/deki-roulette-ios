import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 結果の下に置く幅広の「結果を共有」。両画面で同じ見た目・同じ高さ（`Theme.Layout.resultActionsHeight`）にする。
/// 本文だけを写したいときは共有シートの「コピー」を使う（専用のコピーボタンは置かない）。
/// `shareImage` があれば共有シートに本文と一緒に結果の画像（`ShareImageFile`）を渡し、無ければ本文だけを渡す（今までどおり）。
struct ResultActions: View {
    /// 共有シートに渡す本文（アプリ名入り）。
    let shareText: String
    /// 共有シートに本文と一緒に渡す結果の画像。nil なら本文だけを共有する。
    var shareImage: UIImage? = nil

    var body: some View {
        // 「結果を共有」が残りの幅をすべて取る。行き先ごとのボタンを足すときはこの右に並べる
        HStack(spacing: 8) {
            shareButton
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: Theme.Layout.resultActionsMaxWidth)
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
                ResultActionLabel(title: L10n.shareResult, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
        } else {
            ShareLink(item: shareText) {
                ResultActionLabel(title: L10n.shareResult, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
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
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    // 名前は文字から読ませる（「結果を共有」）
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.ivory)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: Theme.Layout.resultActionsHeight)
        .contentShape(.capsule)
        .overlay(Capsule().strokeBorder(Theme.ink600, lineWidth: 1.5))
    }
}

#Preview {
    ResultActions(shareText: "結果: ラーメン\n\nデキレーレット")
        .padding()
        .background(Theme.ink900)
}
