import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 結果の下に置く幅広の「結果を共有」と、X・LINE のボタン。両画面で同じ見た目・同じ高さ（`Theme.Layout.resultActionsHeight`）にする。
/// 本文だけを写したいときは共有シートの「コピー」を使う（専用のコピーボタンは置かない）。
/// `shareImage` があれば共有シートに本文と一緒に結果の画像（`ShareImageFile`）を渡し、無ければ本文だけを渡す（今までどおり）。
/// X・LINE は本文だけを Web の投稿画面の URL（`ShareIntent`）で開く（画像は付かない）。投稿は利用者が各アプリで確定する。
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
                // 「結果を共有」が残りの幅をすべて取り、X・LINE は文字の幅だけ
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
            openURL(ShareIntent.xPost(text: postText ?? shareText))
        } label: {
            ResultActionLabel(title: L10n.shareToX, fillsWidth: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.shareToXAccessibility)

        Button {
            openURL(ShareIntent.lineShare(text: shareText))
        } label: {
            ResultActionLabel(title: L10n.shareToLINE, fillsWidth: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.shareToLINEAccessibility)
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

/// 「結果を共有」と X・LINE のボタンのラベル。地は塗らず（ページの地のまま）、`ink600` の枠と `ivory` の文字にする。
/// 開始ボタン（`flare` の塗りと光彩）より控えめにして主従を保ち、`flare` / `gold` は使わない。
private struct ResultActionLabel: View {
    let title: String
    var systemImage: String?
    /// 残りの幅をすべて取るか（「結果を共有」）。偽なら文字の幅だけ（X・LINE）。
    var fillsWidth = true

    @Environment(\.dynamicTypeSize) private var typeSize

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
                // アクセシビリティサイズでは省略せず 2 行まで折り返す（行の高さも `TypeLayout.growsFixedAreas` で伸びる）
                .lineLimit(TypeLayout.labelLineLimit(for: typeSize))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.ivory)
        // X・LINE は短い名前なので折り返さず、幅も高さもタップ領域を下回らないようにする
        .fixedSize(horizontal: !fillsWidth, vertical: false)
        .padding(.horizontal, fillsWidth ? 20 : 16)
        .padding(.vertical, 8)
        .frame(
            minWidth: fillsWidth ? nil : Theme.Layout.resultActionsHeight,
            maxWidth: fillsWidth ? .infinity : nil,
            minHeight: Theme.Layout.resultActionsHeight
        )
        .contentShape(.capsule)
        .overlay(Capsule().strokeBorder(Theme.ink600, lineWidth: 1.5))
    }
}

#Preview {
    ResultActions(shareText: "ルーレットで「ラーメン」に決まりました！\n\n#デキレーレット")
        .padding()
        .background(Theme.ink900)
}
