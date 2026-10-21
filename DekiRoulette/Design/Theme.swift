import SwiftUI
import UIKit

/// 配色・書体・アニメーション。Web 版 `tailwind.config.ts` の `theme.extend` に対応する。
///
/// 色は端末の外観設定に従う。トークン名は Web 版のまま据え置き、ライトでは役割ごとに値を反転させる
/// （`ink` 系は「地の側」、`ivory` と `muted` は「文字の側」として読む）。
/// 盤面だけは外観に依らず同じ見た目にする（`MARK: 盤面` を参照）。
enum Theme {
    /// 画面の背景。スライスの区切り線とラベルには使わない（`onSlice` を使う）。
    /// ローンチ画面の `LaunchBackground`（`Assets.xcassets`）にも同じ 2 値を置いているので、変えるときは両方を合わせる。
    static let ink900 = Color(light: 0xFAF7F2, dark: 0x17111F)
    /// カード・入力欄・タブバーの背景。
    static let ink800 = Color(light: 0xFFFFFF, dark: 0x1F1829)
    /// 枠線、無効ボタンの背景。
    static let ink700 = Color(light: 0xE6DFD5, dark: 0x2A2138)
    /// 入力欄の枠、破線枠。
    static let ink600 = Color(light: 0xD5CBBE, dark: 0x3A2F4C)
    /// 指定中の行の枠。
    static let ink500 = Color(light: 0xB6A9C6, dark: 0x4C3F62)
    /// 削除ボタン。
    static let ink400 = Color(light: 0x7A6C90, dark: 0x7D6D96)
    /// 本文。
    static let ivory = Color(light: 0x241C30, dark: 0xF5EFE6)
    /// 補助テキスト。
    static let muted = Color(light: 0x655877, dark: 0xA99BBD)

    /// 順番決めの 1 位とフォーカスリング専用。ルーレットの結果は止まったスライスの色（`sliceColor(in:at:)`）を使う。
    static let gold = Color(light: 0x8A6410, dark: 0xFFC94A)

    /// スピン・並べ替えの操作専用。塗りは両モードで同じ色。
    static let flare = Color(hex: 0xFF4E63)
    /// `flare` を文字に使うときの色。ライトの地では塗りのままだと読めないため濃くする。
    static let flareText = Color(light: 0xC81E37, dark: 0xFF4E63)
    /// `flare` の塗りに乗る文字。塗りが固定なので文字も固定。
    static let onFlare = Color(hex: 0x17111F)
    /// 開始ボタンの光。ライトの地では強く出すぎるため弱める。
    static let flareGlow = Color(light: 0xFF4E63, dark: 0xFF4E63, lightAlpha: 0.3, darkAlpha: 0.45)

    // MARK: 盤面

    // 盤面は外観設定に依らず同じ見た目にする。スライスは「明るい塗り + 暗い文字」でコントラストを
    // 取っているため、地の側だけ反転させると成り立たなくなる。

    /// スライスの区切り線とラベル。
    static let onSlice = Color(hex: 0x17111F)
    /// 盤面の縁。
    static let wheelRim = Color(hex: 0x2A2138)
    /// 盤面の外周線。
    static let wheelEdge = Color(hex: 0x4C3F62)
    /// 中心のハブ。
    static let wheelHub = Color(hex: 0x1F1829)
    /// ハブの枠と中心の点。
    static let wheelHubMark = Color(hex: 0xF5EFE6)
    /// 盤面の影。ライトの地では濃く出すぎるため弱める。
    static let wheelShadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.2, darkAlpha: 0.5)
    /// 針の影。
    static let pointerShadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.25, darkAlpha: 0.55)

    // MARK: スライスの色

    /// 盤面のスライスを塗る 10 色。彩度と明度を揃えてあり、ラベルとセパレータを `onSlice` で描くため、
    /// どのスライスも暗色テキストで 4.5:1 を超える明るさに寄せてある。外観設定では変えない。
    private static let slicePaints: [UInt32] = [
        0xFF8080, 0xFFA366, 0xF2CE5C, 0xA3DB6B, 0x5FD6A8,
        0x5CC9E0, 0x7BAEF5, 0xA48CF0, 0xCE8CEE, 0xFF85C0,
    ]

    /// ライトの地に文字や細い枠として置くための、同じ色相のまま暗くした 10 色。
    /// 明るい塗りのままでは白地で読めないため用意している。
    private static let sliceInks: [UInt32] = [
        0xD92323, 0xAF571D, 0x856D20, 0x557B30, 0x327C60,
        0x2F7A8A, 0x2F6FC8, 0x785CD0, 0x9E48C8, 0xD32278,
    ]

    /// 盤面の塗り。
    static let sliceColors: [Color] = slicePaints.map { Color(hex: $0) }

    /// 文字・色見本・細い枠に使うスライス色。指定中の印にも専用色は使わずこれを流用する。
    static let sliceAccents: [Color] = zip(sliceInks, slicePaints).map { Color(light: $0, dark: $1) }

    /// 自動の項目の規則（並び順と件数）だけで引くスライス色。継ぎ目の色を `SlicePalette` がずらすため、必ず件数つきで引く。
    /// 描画は項目の見た目（色の項目）を踏まえる `sliceColor(in:at:)` / `sliceAccent(in:at:)` を使う（これはその自動の規則と、テストの基準）。
    static func sliceColor(at index: Int, count: Int) -> Color {
        sliceColors[SlicePalette.index(at: index, count: count, paletteSize: sliceColors.count)]
    }

    static func sliceAccent(at index: Int, count: Int) -> Color {
        sliceAccents[SlicePalette.index(at: index, count: count, paletteSize: sliceAccents.count)]
    }

    /// 項目リスト `items` の `index` 番目のスライスの塗り。色の項目は選んだ色、自動・絵文字の項目は並び順と件数から引く。
    /// 件数は `items.count` を使うので、盤面の塗り・結果の帯の枠・光彩・共有画像は同じ項目リストを渡す。
    static func sliceColor(in items: [Item], at index: Int) -> Color {
        sliceColors[paletteIndex(in: items, at: index, paletteSize: sliceColors.count)]
    }

    /// `sliceColor(in:at:)` の文字・色見本用（`sliceAccent(at:count:)` と同じ使い分け）。
    static func sliceAccent(in items: [Item], at index: Int) -> Color {
        sliceAccents[paletteIndex(in: items, at: index, paletteSize: sliceAccents.count)]
    }

    private static func paletteIndex(in items: [Item], at index: Int, paletteSize: Int) -> Int {
        let appearance = items.indices.contains(index) ? items[index].appearance : .auto
        return SlicePalette.index(for: appearance, at: index, count: items.count, paletteSize: paletteSize)
    }

    /// 曲線は `Config.spinEasing` に置き、触覚の発火時刻（`HapticSchedule`）とクリック音の時刻（`SpinTicks`）の逆算と同じ形を共有する。
    static let spinAnimation = spinAnimation(easing: Config.spinEasing)

    /// 曲線 `easing` で `duration` 秒の補間。フリックで始めたスピンは離した瞬間の速さに合わせた曲線、
    /// 勢いが足りずに惰性で回すときは `FlickCoast` が決めた曲線と長さを渡す（`spinAnimation(path:)` が区間 1 つの動きで使う）。
    static func spinAnimation(easing: CubicBezierCurve, duration: TimeInterval = Config.spinDuration) -> Animation {
        .timingCurve(easing.x1, easing.y1, easing.x2, easing.y2, duration: duration)
    }

    /// 盤面の動き（`RouletteModel.rotationPath`）の補間。区間 1 つ（焦らしを入れないスピン・惰性）は今までどおり
    /// `spinAnimation(easing:duration:)` の `timingCurve` で、焦らしを入れた区間の列は `SpinPathAnimation` で補間する。
    static func spinAnimation(path: SpinPath) -> Animation {
        guard path.segments.count > 1 else {
            let motion = path.segments[0]
            return spinAnimation(easing: motion.easing, duration: motion.duration)
        }
        return Animation(SpinPathAnimation(path: path))
    }

    /// 結果が現れる演出。両画面で使い回す。
    static let revealAnimation = Animation.timingCurve(0.2, 0.9, 0.3, 1, duration: Config.revealAnimationDuration)

    // MARK: 書体

    /// 同梱の書体（`AppFont`）のトークン。文字の `.font` はここから引く（SF Symbols の `Image(systemName:)` の `.font` は記号の大きさ・太さなのでシステムのまま）。
    /// 太さはフェイスで出すので、返した `Font` に `.weight(_:)` / `.bold()` を掛けない。
    enum Typography {
        /// テキストスタイルの文字。Dynamic Type でスタイルと同じ割合で拡大する。`weight` を省くとスタイルの既定の太さ（`AppFont.defaultWeight(for:)`）。
        static func font(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
            let face = AppFont.face(for: weight ?? AppFont.defaultWeight(for: style))
            return .custom(face.postScriptName, size: defaultSize(for: style), relativeTo: style)
        }

        /// 固定の大きさの文字（盤面・結果の帯・共有画像）。Dynamic Type で大きくしない。
        static func fixed(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .custom(AppFont.face(for: weight).postScriptName, fixedSize: size)
        }

        /// UIKit で描く文字（3D のラベル画像など）。読めなかったら丸ゴシックのシステムの書体に戻す。
        static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> UIFont {
            let face = AppFont.face(for: weight)
            if let font = UIFont(name: face.postScriptName, size: size) { return font }
            let system = UIFont.systemFont(ofSize: size, weight: systemWeight(of: face))
            guard let descriptor = system.fontDescriptor.withDesign(.rounded) else { return system }
            return UIFont(descriptor: descriptor, size: size)
        }

        /// シートのツールバーの文字のボタン（「閉じる」「編集」）。システムの既定と同じ semibold の太さ（Bold のフェイス）にする。
        /// iOS 26 のツールバーのボタンは環境の書体で描かれるので、付けないとアプリの既定（本文の Regular）になる。
        static var barButton: Font { font(.body, weight: .semibold) }

        /// `List` のセクションの見出し。アプリの根の本文の書体を引き継がないよう、システムの見出しと同じ大きさ・太さを明示する
        /// （iOS 26 は本文の semibold、iOS 17・18 は footnote。`UIListContentConfiguration.groupedHeader()` の値）。
        static var listSectionHeader: Font {
            if #available(iOS 26, *) {
                font(.body, weight: .semibold)
            } else {
                font(.footnote)
            }
        }

        /// `List` のセクションの注記（システムと同じ footnote）。
        static var listSectionFooter: Font { font(.footnote) }

        /// スタイルの既定の大きさ（Dynamic Type が標準の `.large` のとき）。iOS と visionOS で違うので、数字を書き写さずシステムから引く。
        static func defaultSize(for style: Font.TextStyle) -> CGFloat {
            let traits = UITraitCollection(preferredContentSizeCategory: .large)
            return UIFont.preferredFont(forTextStyle: uiTextStyle(style), compatibleWith: traits).pointSize
        }

        static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
            switch style {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .subheadline: .subheadline
            case .callout: .callout
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            #if os(visionOS)
            case .extraLargeTitle: .extraLargeTitle
            case .extraLargeTitle2: .extraLargeTitle2
            #endif
            default: .body
            }
        }

        private static func systemWeight(of face: AppFont.Face) -> UIFont.Weight {
            switch face {
            case .regular: .regular
            case .bold: .bold
            case .black: .black
            }
        }
    }

    // MARK: レイアウト

    /// 画面の寸法。Web 版では Tailwind のユーティリティ（`max-w-3xl` / `w-[min(320px,78vw)]`）だったもの。
    /// 横並び（`horizontalSizeClass == .regular`、主に iPad）では盤面を基準より大きく描く。
    enum Layout {
        /// 縦積みでの盤面の上限。ラベルの省略と文字サイズの基準（`WheelLabel.referenceDiameter`）と同じ大きさ。
        static let wheelMaxWidthCompact = CGFloat(WheelLabel.referenceDiameter)
        /// 横並びでの盤面の上限。13 インチ iPad の横向きで余白が目立たない大きさ。
        static let wheelMaxWidthRegular: CGFloat = 480
        /// 横並びでの項目リストの幅。
        static let listWidthRegular: CGFloat = 360
        /// 横並びの 2 列の間隔。縦積みでは上下の間隔に使う。
        static let columnSpacing: CGFloat = 48
        /// ページの左右の余白。
        static let pageHorizontalPadding: CGFloat = 20
        /// ページ全体の上限。横並びの 2 列 + 間隔 + 左右の余白がちょうど収まる幅。
        /// compact の端末はこれより狭いので、縦積みの見え方には影響しない。
        static let pageMaxWidth = wheelMaxWidthRegular + columnSpacing + listWidthRegular + pageHorizontalPadding * 2
        /// 結果の下の行（「結果を共有」）の高さ。タップ領域 44pt を満たし、開始ボタン（約 52pt）より低くして主従を保つ。
        /// アクセシビリティサイズでは最小高さとして使い、文字に合わせて伸ばす（`TypeLayout.growsFixedAreas`）。
        static let resultActionsHeight: CGFloat = 46
        /// 結果の下の行の幅の上限。縦積みの盤面（`wheelMaxWidthCompact`）と同じで、横並びや iPad でも間延びさせない。
        static let resultActionsMaxWidth = wheelMaxWidthCompact
        /// 結果の下の X・LINE のボタンの円（直径 `resultActionsHeight`）に置くロゴの一辺。
        /// X は文字のような細い形なので小さめ、LINE は角丸の四角の地を含むアイコンなので大きめにして、見た目の重さをそろえる。
        /// LINE はガイドラインの最小サイズ（モバイルで 40px）を @2x でも上回る。
        static let shareLogoXSize: CGFloat = 18
        static let shareLogoLINESize: CGFloat = 26
    }

    // MARK: 3D の盤面

    /// 3D 表示の盤面の寸法（基準直径 `WheelLabel.referenceDiameter` での pt。盤面の大きさに比例させる）と見え方。
    /// 盤の塗りは 2D と同じトークン（`sliceColor(in:at:)` / `wheel*` / `onSlice`）で、外観に依らず固定する。
    enum Wheel3D {
        /// 盤（スライスの円板）の厚み。
        static let thickness: CGFloat = 14
        /// 外周の縁が盤の表面より手前に出る高さ。
        static let rimLift: CGFloat = 3
        /// 外周の縁の幅（スライスの円の外側。2D の盤面の縁と同じ）。
        static let rimWidth: CGFloat = 11
        /// 中心のハブが盤の表面より手前に出る高さ。
        static let hubLift: CGFloat = 6
        /// 盤を裏から支える支柱の太さ（半径）と長さ。盤が傾くと縁の下から見える。
        static let postRadius: CGFloat = 9
        static let postLength: CGFloat = 70
        /// 3D の場面を盤面の枠より広く描く割合（片側、盤面の直径に対して）。傾いた盤・針・揺れが枠からはみ出しても切れないようにする。
        static let overscan: CGFloat = 0.15
        /// カメラの縦の画角（度）。小さいほど透視が弱く、正面では 2D に近い見え方になる。
        static let fieldOfView: Double = 30
        /// 盤の側面・縁・支柱を照らす光の強さ。表面のスライスは照明に依らず塗りの色のまま出す。
        static let ambientLight: CGFloat = 500
        static let keyLight: CGFloat = 800
        /// 電飾の電球を外周の縁の上面から浮かせる高さ（pt。直径に依らない）。持ち上げた止まったスライスの面（縁の上面 + 0.6pt）より手前、
        /// 結果の帯・針（縁・ハブの上面 + 1pt 以上）より奥に置き、光彩の画像に隠れず、針の後ろになる（2D の重なり順と同じ）。
        static let lightLift: CGFloat = 0.8
        /// 電球の円の細かさ（周の分割数）。
        static let lightSegments = 16
        /// 光の尾・残像の残像（遅れた角度のスライスの塗り）を盤の表面から浮かせる高さ（pt。直径に依らない）。
        /// ラベル（0.3pt）より手前（2D と同じくラベルの上に重なる）、止まっていないスライスを暗くする層（0.4pt）・ハブ・縁より奥に置く。
        static let ghostLift: CGFloat = 0.35
        /// 光の尾を外周の縁の上面から浮かせる高さ（pt。直径に依らない）。縁の外周線（上面 + 0.1pt）より手前、
        /// 電飾のにじみ（上面 + 0.7pt）と電球（`lightLift`）より奥に置き、電飾と一緒のときは 2D と同じく電球の奥になる。
        static let trailLift: CGFloat = 0.3
        /// 光の尾を描く弧の切れ端 1 つの角度（度）。長さに依らない同じ形の切れ端を並べて回し、濃さだけを毎フレーム変える
        /// （メッシュを作り直さない）。2D の 1 区間（最長 120 度 ÷ 24 区間 = 5 度）の半分。
        static let trailPieceAngle: Double = 2.5

        /// 直径 `diameter`（pt）の盤での、光の尾のにじみの内径と外径（pt）。2D と同じ芯の環（`TrailRing.ringRadius`）を中心に
        /// `TrailRing.glowWidth` の幅だけ広げるが、外は外周の縁（スライスの円の外 `rimWidth`）で止める。2D では縁の外も盤面の枠の中の地に重なるが、
        /// 3D の縁の外は盤の無い宙なので、はみ出すと傾けたときに浮いて見えるため。
        static func trailGlowBounds(diameter: CGFloat) -> (inner: CGFloat, outer: CGFloat) {
            let scale = max(diameter, 0) / CGFloat(WheelLabel.referenceDiameter)
            let ring = TrailRing.ringRadius(diameter: diameter)
            let half = TrailRing.glowWidth * scale / 2
            let rim = CGFloat(WheelGeometry.sliceRadius(diameter: Double(diameter))) + rimWidth * scale
            return (ring - half, min(ring + half, rim))
        }
    }

    // MARK: 停止の強調

    // 止まった瞬間に針の下のスライスだけを短く押し出して少し大きいまま残し、他のスライスを強く沈める。
    // 止まったスライスには白系の縁取りと外側への光彩を付け、細いスライスでも見つけられるようにする。
    // 専用色は使わず、暗くするのは `onSlice` を重ねるだけ、縁取りと光彩は盤面と同じく外観に依らない白系にする。

    /// 止まっていないスライスに重ねて暗くする色。沈めたラベルは読ませる対象ではないが、
    /// どの項目かは見分けられる範囲に留める（`ThemeContrastTests`）。
    static let sliceDim = onSlice.opacity(0.5)
    /// 止まったスライスの縁取り。沈めた隣のスライスに対して 3:1 以上の明るさにする。
    static let stopOutline = Color(hex: 0xF5EFE6)
    /// 縁取りの太さ（基準直径 `WheelLabel.referenceDiameter` での pt。盤面の大きさに比例させる）。
    static let stopOutlineWidth: CGFloat = 3
    /// 光彩の不透明度。白系・止まったスライスの色のどちらにも使う。
    static let stopGlowOpacity = 0.8
    /// 止まったスライスから外側へにじませる光彩（白系、`GlowStyle.white`）。
    static let stopGlow = Color(hex: 0xF5EFE6).opacity(stopGlowOpacity)
    /// 虹色の光彩（`GlowStyle.rainbow`）。新しい色は足さず、色相順に並んだスライスの 10 色を盤面の中心のまわりに一周させる。
    /// 盤面の塗りと同じ色なので `gold` / `flare` の用途とは重ならず、文字にも使わない。
    static let stopGlowRainbow = AngularGradient(
        colors: sliceColors + [sliceColors[0]], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
    )
    /// 光彩の半径（基準直径での pt）。
    static let stopGlowRadius: CGFloat = 10
    /// 止まった瞬間にスライスを押し出す倍率。戻りで `stopHoldScale` に収まる。
    /// 縁取りを含めて外周の縁（基準直径で 16pt）の内側に収まる大きさに留める。
    static let stopPulseScale: CGFloat = 1.10
    /// 結果が出ている間、止まったスライスを前に出しておく倍率。
    static let stopHoldScale: CGFloat = 1.07
    /// 停止の瞬間に針が沈む量（pt）。停止の演出が ON のときは 2 倍（`pointerBounceOffset(_:)`）。
    static let pointerBounceOffset: CGFloat = 4
    /// 停止の演出が ON のとき、針を大きく弾く倍率（沈む量を `pointerBounceOffset` の何倍にするか）。
    static let pointerBigBounceFactor: CGFloat = 2

    /// 停止の瞬間に針が沈む量（pt）。動きを減らす設定では沈めない（0）。
    static func pointerBounceOffset(_ bounce: PointerBounce) -> CGFloat {
        switch bounce {
        case .none: 0
        case .normal: pointerBounceOffset
        case .big: pointerBounceOffset * pointerBigBounceFactor
        }
    }
    /// 押し出し・沈み込みの行き。
    static let stopPulseAnimation = Animation.easeOut(duration: 0.14)
    /// 押し出し・沈み込みの戻り。少し弾ませる。強調が解けてスライスが元の大きさに戻るときにも使う。
    static let stopSettleAnimation = Animation.spring(duration: 0.4, bounce: 0.35)
    /// 他のスライスが暗くなる／戻るときの変化。
    static let stopDimAnimation = Animation.easeOut(duration: 0.25)

    // MARK: 電飾

    // 「スピンの演出」の電飾（`WheelLights`。電球の数は `Config.wheelLightCount`）。2D の盤面の縁（スライスの円の外側にある暗い環）の上に、
    // 回らない層で電球を並べる。盤面の枠と寸法は変えず、縁の幅（基準直径でスライスの円の外 5〜11pt）と枠までの余白（〜16pt）の中に収める。
    // 盤面と同じく外観に依らず固定の暖かい白系にし、`gold`（順番決めの 1 位・フォーカスリング）と `flare`（開始ボタン）は使わない。

    /// 電球の色。明るさ（`WheelLights.Bulb.brightness`）を不透明度にして縁の上に重ねる。縁（`wheelRim`）に対して 3:1 以上、
    /// いちばん暗いときに重ねた色でも縁から見分けられること（`ThemeContrastTests`）。
    static let wheelLight = Color(hex: 0xFFE7B0)
    /// 背景の光の脈動（`WheelBackGlow`）の色。盤面の外（ページの地 `ink900` の上）に重ねるので外観に合わせ、ダークは電飾（`wheelLight`）より淡い
    /// 暖かい白系、ライトは淡い地に溶けないよう琥珀色にする。`gold` / `flare` は使わない。
    static let wheelBackGlow = Color(light: 0xE8892A, dark: 0xFFF1D6)

    /// 背景の光の脈動の寸法（基準直径 `WheelLabel.referenceDiameter` での pt。直径に比例させる）。
    /// 光は外周の縁の外周（スライスの円の外 11pt。`Wheel3D.rimWidth` と同じ）から盤面の枠（外 `outerOffset`）までの環に置き、
    /// 縁の外周でいちばん明るく枠で 0 になるよう放射状にぼかす。盤面の面には重ねない（盤面の後ろから漏れる光に見せる）。
    enum BackGlow {
        /// 光の環の内側（いちばん明るいところ）の、スライスの円の半径からの出幅。外周の縁の外周（11pt）。
        static let innerOffset: CGFloat = 11
        /// 光の環の外側（0 になるところ）の、スライスの円の半径からの出幅。盤面の枠（16pt）。
        static let outerOffset: CGFloat = 16

        /// 直径 `diameter`（pt）の盤面での、光の環の内側の半径（pt）。
        static func innerRadius(diameter: CGFloat) -> CGFloat {
            CGFloat(WheelGeometry.sliceRadius(diameter: Double(diameter))) + innerOffset * scale(diameter)
        }

        /// 直径 `diameter`（pt）の盤面での、光の環の外側の半径（pt）。
        static func outerRadius(diameter: CGFloat) -> CGFloat {
            CGFloat(WheelGeometry.sliceRadius(diameter: Double(diameter))) + outerOffset * scale(diameter)
        }

        private static func scale(_ diameter: CGFloat) -> CGFloat {
            max(diameter, 0) / CGFloat(WheelLabel.referenceDiameter)
        }
    }

    /// 電飾の寸法（基準直径 `WheelLabel.referenceDiameter` での pt。盤面の大きさに比例させる）。
    enum LightRing {
        /// 電球の環の半径の、スライスの円の半径からの出幅。縁の外周線（+3.5〜5pt）と縁の外周（+11pt）の間の中央。
        static let ringOffset: CGFloat = 8
        /// 電球の半径。縁の幅（6pt）に収まる大きさ。
        static let bulbRadius: CGFloat = 2.2
        /// にじみが最も強いときに電球の外へ広げる光の幅。環の外側でも盤面の枠（スライスの円の外 16pt）を越えない。
        static let haloWidth: CGFloat = 5
        /// にじみの光の中心の不透明度（にじみの強さ × 明るさに掛ける）。
        static let haloOpacity = 0.6

        /// 直径 `diameter`（pt）の盤面での電球の環の半径（pt）。スライスの円（`WheelGeometry.sliceRadius`）の外 `ringOffset`。
        /// 2D の `WheelLightsView` と 3D の `Wheel3DScene` が同じ値を使う。
        static func ringRadius(diameter: CGFloat) -> CGFloat {
            CGFloat(WheelGeometry.sliceRadius(diameter: Double(diameter))) + ringOffset * scale(diameter)
        }

        /// 直径 `diameter`（pt）の盤面での電球の半径（pt）。
        static func bulbRadius(diameter: CGFloat) -> CGFloat {
            bulbRadius * scale(diameter)
        }

        /// 直径 `diameter`（pt）の盤面での、にじみが最も強いときに電球の外へ広げる光の幅（pt）。
        static func haloWidth(diameter: CGFloat) -> CGFloat {
            haloWidth * scale(diameter)
        }

        private static func scale(_ diameter: CGFloat) -> CGFloat {
            max(diameter, 0) / CGFloat(WheelLabel.referenceDiameter)
        }
    }

    // MARK: 光の尾・残像

    // 「スピンの演出」の光の尾・残像（`WheelTrails`）。残像はスライスの塗り（`sliceColor(in:at:)`）だけを薄く重ね、
    // 光の尾は盤面の縁（スライスの円の外側にある暗い環）の上を針の下から後ろへ伸びる弧にする。
    // 盤面と同じく外観に依らず固定の冷たい白系にし（電飾の暖かい白と見分ける）、`gold` / `flare` は使わない。

    /// 光の尾の色。濃さ（`WheelTrails.Trail.opacity`）を不透明度にして縁の上に重ねる。縁（`wheelRim`）に対して 3:1 以上（`ThemeContrastTests`）。
    static let wheelTrail = Color(hex: 0xD8F0FF)

    /// 光の尾・残像の寸法（基準直径 `WheelLabel.referenceDiameter` での pt。盤面の大きさに比例させる）。
    enum TrailRing {
        /// 光の尾の芯の中心の半径の、スライスの円の半径からの出幅（縁の中央。電飾の電球の環と同じ）。
        static let ringOffset: CGFloat = 8
        /// 光の尾の芯の太さ。縁の幅（6pt）に収める。
        static let coreWidth: CGFloat = 4
        /// 芯のまわりのにじみの太さ。盤面の枠（スライスの円の外 16pt）を越えない。
        static let glowWidth: CGFloat = 12
        /// にじみの不透明度（芯の濃さに掛ける）。
        static let glowOpacity = 0.35
        /// 尾を描き分ける区間の数（頭から先へ段階的に薄くする）。
        static let segments = 24

        /// 直径 `diameter`（pt）の盤面での光の尾の芯の中心の半径（pt）。スライスの円の外 `ringOffset`。
        /// 2D の `WheelTrailsView` と 3D の `Wheel3DScene` が同じ値を使う。
        static func ringRadius(diameter: CGFloat) -> CGFloat {
            CGFloat(WheelGeometry.sliceRadius(diameter: Double(diameter))) + ringOffset * scale(diameter)
        }

        private static func scale(_ diameter: CGFloat) -> CGFloat {
            max(diameter, 0) / CGFloat(WheelLabel.referenceDiameter)
        }
    }

    // MARK: 火花・紙吹雪

    // 「スピンの演出」の針の先の火花と停止の瞬間の紙吹雪（`WheelParticles`）。盤面と同じく外観に依らず固定し、
    // `gold`（順番決めの 1 位・フォーカスリング）と `flare`（開始ボタン・針）は使わない。

    /// 火花の芯（白熱した白）。縁（`wheelRim`）に対して 3:1 以上（`ThemeContrastTests`）。
    static let wheelSpark = Color(hex: 0xFFF6E0)
    /// 火花のにじみと尾（橙）。芯のまわりに薄く重ねる。針の `flare`（赤）・`gold`（黄）と色相を分ける。
    static let wheelSparkGlow = Color(hex: 0xFF9A3C)

    /// 紙吹雪の色。スライスの 10 色（`sliceColors`）を固定で使う。紙吹雪は特定のスライスを指さないので、
    /// 項目の見た目（`sliceColor(in:at:)`）や止まったスライスでは変えない（指定・結果に依らず同じ見た目）。
    static let confettiColors: [Color] = sliceColors

    /// 火花の寸法（基準直径 `WheelLabel.referenceDiameter` での pt）。
    enum SparkGlow {
        /// にじみの半径の、芯の半径に対する倍率。
        static let haloScale: CGFloat = 3
        /// にじみの不透明度（火花の濃さに掛ける）。
        static let haloOpacity = 0.45
    }

    // MARK: 停止の瞬間のフラッシュ

    /// 停止の瞬間に盤面の枠の中へ 1 回だけ重ねる光（`WheelStopEffects.flashOpacity`）。盤面と同じく外観に依らず固定の白系で、
    /// 不透明度はいちばん明るいときも 0.25。`gold` / `flare` は使わない。縁（`wheelRim`）に対して 3:1 以上（`ThemeContrastTests`）。
    static let stopFlash = Color(hex: 0xFFF8EC)

    /// フラッシュの丸い光の形。中心で不透明度 × 1、半径の半ばで × `middleOpacity`、盤面の枠の縁（半径 = 一辺 ÷ 2）で 0 にする。
    /// 2D の `WheelStopFlashView` と 3D の `Wheel3DScene` が同じ形にする。
    enum StopFlash {
        static let middleOpacity = 0.7
    }

    // MARK: 結果の帯

    // 結果が出ている間、盤面の中心より下に重ねて結果のラベルを全文で出す帯（寸法と位置は `ResultBand`）。
    // 盤面に重ねるので外観に依らず固定し、白系の地に盤面と同じ暗い文字で載せる。枠は止まったスライスの塗り
    // （`sliceColor(in:at:)`）にして、どのスライスの結果かを帯からも読み取れるようにする。

    /// 帯の地。
    static let resultBandFill = Color(hex: 0xF5EFE6)
    /// 帯の文字。
    static let resultBandInk = onSlice
    /// 帯の影。止まったスライスと沈めた盤面から浮かせる。
    static let resultBandShadow = pointerShadow
    /// 停止の演出（`SpinEffects.stopEffects`）が ON のときの帯の登場（小さい大きさから少し行き過ぎて収まる。`ResultBand.popIn*`）。
    static let resultBandPopAnimation = Animation.spring(duration: ResultBand.popInDuration, bounce: ResultBand.popInBounce)

    /// 削除を元に戻すトーストの出入り。
    static let undoToastAnimation = Animation.easeOut(duration: 0.2)

    // MARK: 共有画像

    // 共有シートに渡す結果の画像（`RouletteShareImageView`。寸法は `ShareImageLayout`）。アプリの外で見られるので外観に依らず固定し、
    // 盤面の固定色（`wheel*` / `onSlice` / スライスの塗り）がなじむダークの地に、白系の文字でアプリ名だけを載せる（アイコンは置かない）。

    /// 共有画像の地。ダークの `ink900` と同じ値を固定で持つ。
    static let shareBackground = Color(hex: 0x17111F)
    /// 共有画像の文字（アプリ名）。ダークの `ivory` と同じ値を固定で持つ。
    static let shareInk = Color(hex: 0xF5EFE6)

    // MARK: スワイプ削除

    /// 行を左にスワイプしたときに出る削除ボタンの塗り。外観に依らず固定し、文字は `onDestructive` で載せる。
    static let destructive = Color(hex: 0xC62B3B)
    /// 削除ボタンの文字。
    static let onDestructive = Color(hex: 0xFFFFFF)
    /// 指を離したあと、行が開く／閉じる位置へ収まる動き。
    static let swipeSettleAnimation = Animation.spring(duration: 0.3, bounce: 0)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// 端末の外観設定に追従する色。
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

/// 結果が現れる演出。Web 版の `animate-reveal` に対応する。
struct RevealModifier: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .scaleEffect(shown ? 1 : 0.96)
    }
}

/// 表示された時点から `delay` 後に現れる。`reducedMotion` のときは即座に出す。
struct RevealOnAppear: ViewModifier {
    let delay: TimeInterval
    let reducedMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .modifier(RevealModifier(shown: shown))
            .onAppear {
                if reducedMotion {
                    shown = true
                } else {
                    withAnimation(Theme.revealAnimation.delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    /// アプリの既定の書体。`.font` を持たない文字（`Toggle` / `Button` / `TextField` のラベルなど）も同梱の書体の本文にする。
    /// シートは環境を引き継ぐので、アプリの根に 1 回掛ければよい。
    /// `.fontDesign(.rounded)` は掛けない（環境に置くと `Font.custom` の文字までシステムの丸ゴシックに置き換わり、同梱の書体が出ない）。
    func appTypography() -> some View {
        font(Theme.Typography.font(.body))
    }

    /// シートの画面の題名（ナビゲーションバーの中央・インライン）。`navigationTitle` の文字は UIKit の外観の API でも同梱の書体にならないので、
    /// 同じ題名を `.principal` の `Text` で同梱の書体で出す（`navigationTitle` も残し、戻るボタンと読み上げの画面名に使わせる）。
    func appNavigationTitle(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(Theme.Typography.font(.headline))
                        .foregroundStyle(Theme.ivory)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }

    func revealOnAppear(delay: TimeInterval = 0, reducedMotion: Bool) -> some View {
        modifier(RevealOnAppear(delay: delay, reducedMotion: reducedMotion))
    }
}
