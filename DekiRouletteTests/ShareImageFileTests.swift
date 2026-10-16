import Testing
import UIKit
import UniformTypeIdentifiers
@testable import DekiRoulette

/// 共有シートに渡す画像が PNG として書き出されることを確かめる。
struct ShareImageFileTests {
    @Test func PNGとして書き出す() async throws {
        // `exported(as:)` は iOS 18.2 から。CI の Simulator は最新の iOS なので、そこで確かめる
        guard #available(iOS 18.2, *) else { return }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let data = try await ShareImageFile(image: image).exported(as: .png)
        // PNG の先頭 8 バイトの印
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        // 画像として読み戻せる（画素数は描いたときの倍率に依る）
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.cgImage != nil)
    }
}
