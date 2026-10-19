import SwiftUI

struct RouletteScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(Config.hapticsEnabledKey) private var hapticsEnabled = true
    @AppStorage(Config.soundEnabledKey) private var soundEnabled = true
    @AppStorage(Config.glowStyleKey) private var glowStyle = GlowStyle.default
    @AppStorage(Config.wheel3DEnabledKey) private var wheel3DEnabled = false
    let model: RouletteModel
    @State private var sound = SpinSoundPlayer()
    /// 共有シートに本文と一緒に渡す結果の画像。結果ごとに 1 回だけ描く（`shareImageKey` の変化で `.task` が描き直す）。
    @State private var shareImage: UIImage?

    var body: some View {
        PageFrame(
            title: L10n.title,
            tagline: L10n.tagline,
            busy: model.spinning,
            useCases: L10n.useCases
        ) {
            Text(L10n.helpBasic)
            HelpHeading(text: L10n.helpAimTitle)
            Text(L10n.helpAim)
            Text(L10n.helpAimStealth)
            Text(L10n.helpAimRandom)
        } content: {
            AdaptiveStack(horizontal: regular, alignment: .center, spacing: Theme.Layout.columnSpacing) {
                wheelSection
                ItemListView(
                    items: model.items,
                    marks: model.marks,
                    busy: model.spinning,
                    concealMarks: model.spinning,
                    atCapacity: model.atCapacity,
                    onAdd: { model.addItems($0) },
                    onRemove: { model.removeItem(id: $0) },
                    onRemoveAll: { model.removeAll() },
                    onRestore: { model.restore($0, at: $1) },
                    onLongPress: { model.toggleTarget(id: $0) },
                    onLoad: { model.replaceItems($0) },
                    onSetAppearance: { model.setAppearance($1, for: $0) }
                )
                .frame(maxWidth: regular ? Theme.Layout.listWidthRegular : .infinity)
            }
        }
        .onChange(of: model.result) { _, result in
            if let result {
                AccessibilityNotification.Announcement(L10n.resultAnnounce(result)).post()
            }
        }
        // 触覚: 開始の手応え、境目ごとの刻み、止まった手応え。設定で OFF にできる
        .sensoryFeedback(trigger: model.spinning) { _, spinning in
            hapticsEnabled && spinning ? .impact(weight: Config.hapticSpinStartWeight) : nil
        }
        .sensoryFeedback(trigger: model.boundaryTick) { _, _ in
            hapticsEnabled ? .selection : nil
        }
        // 指で動かしている間の境目は、スピン中の刻みより強く返す
        .sensoryFeedback(trigger: model.dragBoundaryTick) { _, _ in
            hapticsEnabled ? .impact(weight: Config.hapticDragBoundaryWeight) : nil
        }
        .sensoryFeedback(trigger: model.outcome) { _, outcome in
            hapticsEnabled && outcome != nil ? .success : nil
        }
        .onAppear { if soundEnabled { sound.prepare() } }
        .onDisappear {
            sound.stop()
            // 惰性の残りの触覚の刻みも止める
            model.stopCoast()
        }
        // 結果が出て演出が終わったあとに 1 回だけ共有画像を描く。スピン中・結果が無いときは描かず、前の画像も捨てる。
        // 3D 表示が ON でも 2D の盤面で描く。光彩は画面の設定に合わせる
        .task(id: shareImageKey) {
            guard shareImageKey != nil, let outcome = model.outcome else {
                shareImage = nil
                return
            }
            shareImage = ShareImageRenderer.roulette(
                items: model.items, outcome: outcome, rotation: model.rotation, glowStyle: glowStyle
            )
        }
    }

    /// 共有画像を描き直す鍵。結果が出て演出が終わった後だけ値を持ち、結果ごと（`spinCount`）に変わる（結果の表示の `.id` と同じ）。
    /// 結果を出したまま項目の見た目を変えたときも描き直す（結果の表示は出し直さない）。
    private var shareImageKey: ShareImageKey? {
        guard let outcome = model.outcome, !model.spinning else { return nil }
        return ShareImageKey(result: outcome.label + "\(model.spinCount)", appearances: model.items.map(\.appearance))
    }

    private struct ShareImageKey: Hashable {
        let result: String
        let appearances: [ItemAppearance]
    }

    private var regular: Bool { sizeClass == .regular }

    private var wheelSection: some View {
        VStack(spacing: 24) {
            wheel
            // 帯は回転しない層に置く（盤面の `rotationEffect` の外側）。盤面のフリックを妨げないよう触れられなくする。
            // 3D 表示では帯を盤と同じ面に乗せるので、3D の盤面が自分で描く
            .overlay {
                if !wheel3DEnabled { resultBand }
            }
            .frame(maxWidth: regular ? Theme.Layout.wheelMaxWidthRegular : Theme.Layout.wheelMaxWidthCompact)

            PrimaryActionButton(
                title: model.spinning ? L10n.spinning : L10n.spin,
                busy: model.spinning,
                enabled: model.canSpin,
                action: spin
            )
            .accessibilityIdentifier("roulette.spin")

            ZStack {
                // 結果が出ている間だけ出す。順番決めと同じ位置・同じ見た目
                if let outcome = model.outcome, !model.spinning {
                    let text = ResultText.roulette(label: outcome.label, heading: L10n.resultHeading)
                    ResultActions(
                        copyText: text,
                        shareText: ResultText.share(text, appName: L10n.appName),
                        shareImage: shareImage,
                        copyIdentifier: "roulette.result.copy"
                    )
                    .id(outcome.label + "\(model.spinCount)")
                }
            }
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity)
    }

    /// 盤面。設定の「3D 表示」が ON なら 3D で描き、OFF なら今の 2D の盤面のまま。
    @ViewBuilder
    private var wheel: some View {
        if wheel3DEnabled {
            Wheel3DView(
                items: model.items,
                rotation: model.rotation,
                // 2D と同じく、結果が出ている間だけ止まったスライスを強調する
                highlightedIndex: model.outcome?.index,
                interactive: !model.spinning,
                spinEasing: model.spinEasing,
                rotationDuration: model.rotationDuration,
                glowStyle: glowStyle,
                result: wheel3DResult,
                // 2D と同じく、指を離した角度からフリックのスピンを始める
                onBoundaryCross: dragCrossedBoundary,
                onGrab: grab,
                onRelease: release
            )
        } else {
            RouletteWheelView(
                items: model.items,
                rotation: model.rotation,
                // 結果が出ている間だけ止まったスライスを強調する。項目を触って結果が消えれば強調も解ける
                highlightedIndex: model.outcome?.index,
                interactive: !model.spinning,
                spinEasing: model.spinEasing,
                rotationDuration: model.rotationDuration,
                glowStyle: glowStyle,
                onBoundaryCross: dragCrossedBoundary,
                onGrab: grab,
                onRelease: release
            )
        }
    }

    /// 3D の盤面に乗せる結果の帯。2D の帯と同じく結果が出ている間だけ出し、`spinCount` 基準で出し直す。
    private var wheel3DResult: Wheel3DResult? {
        guard let outcome = model.outcome, !model.spinning else { return nil }
        return Wheel3DResult(
            id: outcome.label + "\(model.spinCount)",
            label: bandLabel(outcome),
            // 項目を足し引きすると `outcome` は消えるので、項目リスト（件数）はスピン開始時と同じ
            accent: Theme.sliceColor(in: model.items, at: outcome.index)
        )
    }

    /// 結果の帯に出す全文。絵文字の項目は前に絵文字を付ける（読み上げと共有の本文はラベルのまま）。
    private func bandLabel(_ outcome: SpinOutcome) -> String {
        let appearance = model.items.indices.contains(outcome.index) ? model.items[outcome.index].appearance : .auto
        return WheelLabel.decorated(outcome.label, appearance: appearance)
    }

    /// 盤面の中心より下に重ねる結果の帯。盤面の下に結果の領域は持たず、結果のラベルはここで全文を出す（盤面のラベルは省略される）。
    /// 出し直しは `spinCount` 基準で、指で盤面を動かしても出し直さない。
    /// 盤面と同じく装飾扱いで読み上げない（結果は Announcement で伝える）。
    @ViewBuilder
    private var resultBand: some View {
        if let outcome = model.outcome, !model.spinning {
            GeometryReader { proxy in
                let diameter = Double(min(proxy.size.width, proxy.size.height))
                ResultBandLabel(
                    label: bandLabel(outcome),
                    // 項目を足し引きすると `outcome` は消えるので、項目リスト（件数）はスピン開始時と同じ
                    accent: Theme.sliceColor(in: model.items, at: outcome.index),
                    diameter: diameter
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 盤面は正方形なので、枠の中心が盤面の中心
                    .offset(y: ResultBand.centerOffset(diameter: diameter))
                    .revealOnAppear(reducedMotion: reduceMotion)
                    .id(outcome.label + "\(model.spinCount)")
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// 「スピン」ボタン。直前のフリックの向きで回す。
    private func spin() {
        spin(fullSpins: nil, direction: nil, releaseVelocity: nil)
    }

    /// 指で動かしている盤面の針が境目を越えた。触覚はモデルの刻みで鳴り、回転音はここで 1 回鳴らす（間引きはモデル）。
    private func dragCrossedBoundary(at time: TimeInterval) {
        if model.crossDragBoundary(at: time), soundEnabled { sound.playClick() }
    }

    /// 盤面から指を離した。追従で回した角度を取り込み、勢いがあればその角度からフリックのスピンを始める。
    /// `dragRotation` の取り込みとスピンの開始は同じ更新に入れる（盤面が離した位置から回り出す）。
    /// 指を離さずにジェスチャが取り消されたとき（`angularVelocity` が nil）は、追従した角度を残すだけで回さない。
    private func release(angularVelocity: Double?, dragRotation: Double) {
        model.rotate(by: dragRotation)
        guard let angularVelocity else { return }
        flick(angularVelocity: angularVelocity)
    }

    /// 盤面のフリック。強さは周回数にだけ反映し、フリックした向きに回す。盤面は離した瞬間の速さで回り出し、そこから減速する。
    /// 閾値未満（ゆっくり動かして離した、止めてから離した）ならスピンを始めず、離した速さに応じて少しだけ惰性で回して止める。
    private func flick(angularVelocity: Double) {
        guard let flick = FlickSpin.spin(angularVelocity: angularVelocity) else {
            coast(angularVelocity: angularVelocity)
            return
        }
        spin(fullSpins: flick.fullSpins, direction: flick.direction, releaseVelocity: angularVelocity)
    }

    /// 勢いの足りないフリックの惰性。抽選しないので、結果の表示・`spinCount`・「スピン」ボタンの向きは変わらない。
    /// 盤面は離した瞬間の速さで回り出して止まる（`FlickCoast`）。動きを減らす設定では付けない（離した角度のまま）。
    private func coast(angularVelocity: Double) {
        guard let next = model.beginCoast(angularVelocity: angularVelocity, reducedMotion: reduceMotion) else { return }
        // 惰性で回る間も、針が境目を越えるたびに鳴らす（時刻は惰性の曲線から先に求めてある。触覚はモデルが刻む）
        if soundEnabled { sound.play(at: model.clickTimes) }
        withAnimation(Theme.spinAnimation(easing: model.spinEasing, duration: model.rotationDuration)) {
            model.rotation = next
        }
    }

    /// 盤面に再び触れた。惰性で回っている途中なら、今の角度で止めてから指に追従させる。
    /// 補間中の角度は observable でないので、モデルが曲線から逆算した角度を補間なしで書く（盤面の `.animation` も掛けない）。
    /// 惰性の残りの回転音と触覚の刻みも止める。止めた角度を返す（追従の境目の判定の基準にする）。止めるものが無ければ nil。
    private func grab() -> Double? {
        guard let angle = model.stopCoast() else { return nil }
        sound.stop()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.rotation = angle
        }
        return angle
    }

    private func spin(fullSpins: Int?, direction: SpinDirection?, releaseVelocity: Double?) {
        guard let next = model.beginSpin(
            reducedMotion: reduceMotion, fullSpins: fullSpins, direction: direction, releaseVelocity: releaseVelocity
        ) else { return }
        if soundEnabled { sound.play(at: model.clickTimes) }
        if reduceMotion {
            // 動きを減らす設定では回さずに止まる。終了は保険のタイマーが担う
            model.rotation = next
        } else {
            withAnimation(Theme.spinAnimation(easing: model.spinEasing)) {
                model.rotation = next
            } completion: {
                model.finishSpin()
            }
        }
    }
}

/// 結果の帯の見た目。2D では盤面に重ね、3D では画像に焼いて盤と同じ面に貼る（`Wheel3DView`）。
/// 寸法は `ResultBand`、色は `Theme.resultBand*` で、枠は止まったスライスの塗り（`accent`）。
struct ResultBandLabel: View {
    let label: String
    let accent: Color
    let diameter: Double

    var body: some View {
        let scale = diameter / WheelLabel.referenceDiameter
        Text(label)
            .font(.system(size: ResultBand.fontSize(diameter: diameter), weight: .black))
            .foregroundStyle(Theme.resultBandInk)
            .lineLimit(1)
            .minimumScaleFactor(ResultBand.minimumScaleFactor)
            .truncationMode(.tail)
            .padding(.horizontal, ResultBand.horizontalPadding(diameter: diameter))
            .padding(.vertical, ResultBand.verticalPadding(diameter: diameter))
            .background(Theme.resultBandFill, in: .capsule)
            .overlay(Capsule().strokeBorder(accent, lineWidth: 2 * scale))
            .shadow(color: Theme.resultBandShadow, radius: 4 * scale, y: 2 * scale)
            .frame(maxWidth: ResultBand.maxWidth(diameter: diameter))
    }
}

#Preview {
    RouletteScreen(model: RouletteModel(items: ItemLabel.makeItems(L10n.defaultItems)))
        .environment(SavedListsModel(lists: []))
}

#Preview("AX5") {
    RouletteScreen(model: RouletteModel(items: ItemLabel.makeItems(L10n.defaultItems)))
        .dynamicTypeSize(.accessibility5)
}
