import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 結果の下に置く「結果をコピー」と「共有」。両画面で同じ見た目にする。
/// 「コピーしました」の表示は `Config.copyFeedbackDuration` の間だけ出す。
/// `shareImage` があれば共有シートに本文と一緒に結果の画像（`ShareImageFile`）を渡し、無ければ本文だけを渡す（今までどおり）。
struct ResultActions: View {
    /// クリップボードに書き込む本文。
    let copyText: String
    /// 共有シートに渡す本文（アプリ名入り）。
    let shareText: String
    /// 共有シートに本文と一緒に渡す結果の画像。nil なら本文だけを共有する。
    var shareImage: UIImage? = nil
    /// 「結果をコピー」ボタンのアクセシビリティ ID。App Store 用スクリーンショットの UI テストが、
    /// 結果が出た（＝このボタンが出た）のを待つのに使う。
    var copyIdentifier: String

    @State private var copied = false
    @State private var copyTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: copy) {
                ResultActionLabel(title: copied ? L10n.copied : L10n.copyResult)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(copyIdentifier)

            // 開始ボタンの `flare` より目立たせないため、コピーと同じ控えめな見た目にする
            if let shareImage {
                // 画像を本体（X・Instagram・LINE は画像として受け取る）、本文は添える。プレビューの題名はアプリ名
                ShareLink(
                    item: ShareImageFile(image: shareImage),
                    message: Text(shareText),
                    preview: SharePreview(L10n.appName, image: Image(uiImage: shareImage))
                ) {
                    ResultActionLabel(title: L10n.share, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            } else {
                ShareLink(item: shareText) {
                    ResultActionLabel(title: L10n.share, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear { copyTask?.cancel() }
    }

    private func copy() {
        UIPasteboard.general.string = copyText
        copied = true
        copyTask?.cancel()
        copyTask = Task {
            try? await Task.sleep(for: .seconds(Config.copyFeedbackDuration))
            guard !Task.isCancelled else { return }
            copied = false
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

/// コピー・共有ボタンのラベル。`muted` の文字にカプセルの地と枠。
private struct ResultActionLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            Text(title)
                .font(.caption.weight(.bold))
        }
        // 隣のラベルが「コピーしました」に変わって幅が動いても、こちらが省略記号で切れないようにする
        .fixedSize()
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.ink800, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.ink700, lineWidth: 1))
    }
}

#Preview {
    ResultActions(copyText: "結果: ラーメン", shareText: "結果: ラーメン\n\nデキレーレット", copyIdentifier: "result.copy")
        .padding()
        .background(Theme.ink900)
}
