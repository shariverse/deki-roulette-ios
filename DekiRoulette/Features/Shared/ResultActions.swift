import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 結果の下に置く幅広の「結果を共有」と、その右の X・LINE のロゴのボタン。両画面で同じ見た目・同じ高さ（`Theme.Layout.resultActionsHeight`）にする。
/// 「結果を共有」は押すと直接共有シートを開く。`shareImage` があれば結果の画像（`ShareImageFile`）と本文を別々の項目（`ShareItem`）として渡し、
/// 無ければ本文だけを渡す。本文を画像に添える（`message`）だけだと「メモ」など添えた本文を読まない共有先に画像しか届かないため。
/// 受け取れる共有先（X・LINE・メモ・メッセージなど）には画像と本文、本文を受け取らない共有先（Instagram のフィード・「画像を保存」）には画像だけが届く。
/// 専用のコピーボタンは置かない（本文は共有シートの「コピー」で写す。画像があるときに「コピー」で何が写るかは実機で確かめる）。
/// X は本文だけを X アプリの投稿画面（URL スキーム）で開き、開けなければ Web の投稿画面で開く（`ShareIntent.xPostCandidates`）。
/// LINE は本文だけを Web の URL（`ShareIntent.lineShare`）で開く。どちらも画像は付かず、確認は挟まない。投稿は利用者が各アプリで確定する。
/// X・LINE は各社の公式のロゴを元の色のまま枠の中に置く（「X」1 文字の文字のボタンは閉じるボタンと間違えて押されたため）。
struct ResultActions: View {
    /// 共有シートと LINE に渡す本文（ハッシュタグ入り。`ResultText.share`）。
    let shareText: String
    /// X に渡す本文。X の上限に収めたもの（順番決めは `ResultText.orderPost`）。nil なら `shareText` を渡す。
    var postText: String? = nil
    /// 共有シートに本文とは別の項目として渡す結果の画像。nil なら本文だけを共有する。
    var shareImage: UIImage? = nil
    /// 「結果を共有」ボタンのアクセシビリティ ID。App Store 用スクリーンショットの UI テストが、
    /// 結果が出た（＝このボタンが出た）のを待つのに使う。
    var shareIdentifier: String

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
            // 画像と本文を別々の項目にする（本文は `message` にしない。両方に渡すとメッセージなどで本文が二重になる）。
            // プレビューの題名はアプリ名、画像は結果の画像
            ShareLink(
                items: ShareItem.items(image: ShareImageFile(image: shareImage), text: shareText),
                preview: { _ in SharePreview(L10n.appName, image: Image(uiImage: shareImage)) }
            ) {
                ResultActionLabel(title: L10n.shareResult)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(shareIdentifier)
        } else {
            ShareLink(item: shareText) {
                ResultActionLabel(title: L10n.shareResult)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(shareIdentifier)
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

/// 共有シートに渡す項目（画像か本文）。画像は `ShareImageFile` と同じ PNG、本文は文字列（プレーンテキスト）として書き出す。
/// 項目ごとに書き出す形を 1 つだけにする（画像の項目から本文を、本文の項目から画像を出さない）。
extension ShareItem: Transferable where Image == ShareImageFile {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard case .image(let file) = item, let data = file.image.pngData() else {
                throw ShareImageError.encodingFailed
            }
            return data
        }
        .exportingCondition { item in
            if case .image = item { true } else { false }
        }
        ProxyRepresentation { item in
            if case .text(let text) = item { text } else { "" }
        }
        .exportingCondition { item in
            if case .text = item { true } else { false }
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
                .font(Theme.Typography.font(.subheadline, weight: .bold))
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
    ResultActions(shareText: "ルーレットで「ラーメン」に決まりました！\n\n#デキレーレット", shareIdentifier: "result.share")
        .padding()
        .background(Theme.ink900)
}
