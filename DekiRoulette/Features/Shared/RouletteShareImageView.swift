import SwiftUI

/// 共有シートに渡すルーレットの結果画像。一辺 `side` の正方形に、盤面（2D。画面の `RouletteWheelView` と同じ `WheelFaceView`）・
/// 針・結果の帯（画面と同じ `ResultBandLabel`）・アプリ名（`L10n.appName` の文字だけ）を描く。寸法は `ShareImageLayout.roulette(side:)`。
/// 画面のスクリーンショットではなく描き直すので、画面キャプチャ中に印を伏せる仕組み（`ScreenCaptureMonitor`）とは関わらない。
/// 3D 表示が ON のときもこの 2D の盤面で描く。
///
/// 入力は項目（id とラベル）・結果（ラベルと添字）・回転角だけで、指定や印を受け取る口は持たない（SPEC §6.5・§7.3）。
/// 配色は外観に依らず固定（`Theme.shareBackground` / `shareInk` と盤面の固定色）。止まったスライスは画面で結果が出ている間と同じ強調
/// （他を `Theme.sliceDim` で沈め、縁取り・光彩・`stopHoldScale` の押し出し）。盤面の影は付けない（ダークの地では見えず、余白に掛かるだけのため）。
struct RouletteShareImageView: View {
    /// 結果を出したときの項目。`outcome.index` はこの配列の添字。
    let items: [Item]
    let outcome: SpinOutcome
    /// 止まったときの累積の回転角（度）。画面と同じ向きで盤面を回す。
    let rotation: Double
    /// 止まったスライスの光彩の色。画面の設定に合わせて親が渡す。
    var glowStyle = GlowStyle.default
    /// 画像の一辺（描画の単位。`ShareImageRenderer` が `scale` 1 で焼くので px と一致する）。
    var side = ShareImageLayout.defaultSide

    var body: some View {
        let layout = ShareImageLayout.roulette(side: side)
        let diameter = CGFloat(layout.wheelDiameter)
        ZStack {
            Theme.shareBackground

            WheelFaceView(
                items: items, side: diameter, highlight: outcome.index, glowStyle: glowStyle,
                highlightScale: Theme.stopHoldScale, animated: false
            )
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(rotation))
            .position(layout.wheelCenter)

            WheelPointerView(width: layout.pointerSize.width, height: layout.pointerSize.height)
                .position(x: layout.wheelCenter.x, y: layout.pointerTop + layout.pointerSize.height / 2)

            // 帯は回転しない層に置く（画面と同じ）。枠は止まったスライスの塗り
            ResultBandLabel(
                label: WheelLabel.decorated(
                    outcome.label,
                    appearance: items.indices.contains(outcome.index) ? items[outcome.index].appearance : .auto
                ),
                accent: Theme.sliceColor(in: items, at: outcome.index),
                diameter: layout.wheelDiameter
            )
            .position(layout.bandCenter)

            Text(L10n.appName)
                .font(.system(size: ShareImageLayout.brandFontSize(side: side), weight: .bold))
                .foregroundStyle(Theme.shareInk)
                .lineLimit(1)
                .position(x: side / 2, y: ShareImageLayout.brandCenterY(side: side))
        }
        .frame(width: side, height: side)
    }
}

/// 共有画像を `UIImage` に焼く。`ImageRenderer` は `@MainActor` なので View 側から呼ぶ。
/// `scale` は 1 に固定し、端末の画面倍率に依らず一辺 `side` px の画像にする。重い処理なので、結果が確定したあとに 1 回だけ呼び、
/// 画面が `@State` に持つ（`RouletteScreen` の `.task(id:)`。スピン中・結果が無いときは呼ばない）。
@MainActor
enum ShareImageRenderer {
    /// ルーレットの結果画像。`items` と `outcome` は結果を出したときのもの、`rotation` は止まったときの累積の回転角。
    static func roulette(
        items: [Item], outcome: SpinOutcome, rotation: Double, glowStyle: GlowStyle = .default,
        side: Double = ShareImageLayout.defaultSide
    ) -> UIImage? {
        render(
            RouletteShareImageView(items: items, outcome: outcome, rotation: rotation, glowStyle: glowStyle, side: side),
            side: side
        )
    }

    /// 一辺 `side` の正方形の View を画像にする。書体はアプリ全体と同じ丸ゴシック（`ImageRenderer` はアプリの environment を継がない）。
    /// 地・文字・盤面は固定のトークンだが、針と帯の影（`Theme.pointerShadow`）は外観で濃さが変わるので、解決の環境をダークに固定して
    /// 端末の外観に依らず同じ画像にする。
    static func render(_ content: some View, side: Double) -> UIImage? {
        let renderer = ImageRenderer(
            content: content
                .frame(width: side, height: side)
                .fontDesign(.rounded)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

#Preview {
    RouletteShareImageView(
        items: ItemLabel.makeItems(["ラーメン", "カレー", "寿司", "焼肉"]),
        outcome: SpinOutcome(index: 2, label: "寿司"),
        rotation: 45
    )
    .scaleEffect(0.3)
    .frame(width: 324, height: 324)
}
