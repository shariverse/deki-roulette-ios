import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// 結果の下に置く「共有」。両画面で同じ見た目にする。
/// 本文だけを写したいときは共有シートの「コピー」を使う（専用のコピーボタンは置かない）。
/// `shareImage` があれば共有シートに本文と一緒に結果の画像（`ShareImageFile`）を渡し、無ければ本文だけを渡す（今までどおり）。
struct ResultActions: View {
    /// 共有シートに渡す本文（アプリ名入り）。
    let shareText: String
    /// 共有シートに本文と一緒に渡す結果の画像。nil なら本文だけを共有する。
    var shareImage: UIImage? = nil

    var body: some View {
        HStack(spacing: 8) {
            // 開始ボタンの `flare` より目立たせないため、控えめな見た目にする
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

/// 共有ボタンのラベル。`muted` の文字にカプセルの地と枠。
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
        // 省略記号で切れないようにする
        .fixedSize()
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.ink800, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.ink700, lineWidth: 1))
    }
}

#Preview {
    ResultActions(shareText: "結果: ラーメン\n\nデキレーレット")
        .padding()
        .background(Theme.ink900)
}
