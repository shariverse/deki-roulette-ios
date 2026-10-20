import Foundation

/// 文言テーブルへの入口。実体は `Localizable.xcstrings`（日英）。
/// 表示言語は OS の設定に従う（設定アプリのアプリ別言語も有効）。アプリ内での切替は持たない。
enum L10n {
    static var title: String { tr("title") }
    static var tagline: String { tr("tagline") }
    static var spin: String { tr("spin") }
    static var spinning: String { tr("spinning") }
    static func resultAnnounce(_ label: String) -> String { fmt("resultAnnounce", label) }
    static var itemListTitle: String { tr("itemListTitle") }
    static var addPlaceholder: String { tr("addPlaceholder") }
    static var addButton: String { tr("addButton") }
    static var emptyList: String { tr("emptyList") }
    static var needMoreItems: String { tr("needMoreItems") }
    static func atCapacity(_ max: Int) -> String { fmt("atCapacity", max) }
    static func itemCount(_ count: Int, _ max: Int) -> String { fmt("itemCount", count, max) }
    static func removeAccessibilityLabel(_ label: String) -> String { fmt("removeAccessibilityLabel", label) }
    static var duplicateLabelNotice: String { tr("duplicateLabelNotice") }
    static var helpTitle: String { tr("helpTitle") }
    static var helpBasic: String { tr("helpBasic") }
    static var helpAimTitle: String { tr("helpAimTitle") }
    static var helpAim: String { tr("helpAim") }
    static var helpAimStealth: String { tr("helpAimStealth") }
    static var helpAimRandom: String { tr("helpAimRandom") }
    static var useCasesTitle: String { tr("useCasesTitle") }
    static var useCases: String { tr("useCases") }
    static var noticeTitle: String { tr("noticeTitle") }
    static var notice: String { tr("notice") }
    static var orderNavLabel: String { tr("orderNavLabel") }
    static var rouletteNavLabel: String { tr("rouletteNavLabel") }
    static var orderTitle: String { tr("orderTitle") }
    static var orderTagline: String { tr("orderTagline") }
    static var orderShuffle: String { tr("orderShuffle") }
    static var orderShuffling: String { tr("orderShuffling") }
    static var orderResultPlaceholder: String { tr("orderResultPlaceholder") }
    static var orderResultTitle: String { tr("orderResultTitle") }
    static func orderRankAccessibilityLabel(_ rank: Int) -> String { fmt("orderRankAccessibilityLabel", rank) }
    static var orderMarkFirst: String { tr("orderMarkFirst") }
    static var orderMarkLast: String { tr("orderMarkLast") }
    static var orderHelpBasic: String { tr("orderHelpBasic") }
    static var orderHelpAimTitle: String { tr("orderHelpAimTitle") }
    static var orderHelpAim: String { tr("orderHelpAim") }
    static var orderHelpAimStealth: String { tr("orderHelpAimStealth") }
    static var orderHelpAimRandom: String { tr("orderHelpAimRandom") }
    static var orderUseCases: String { tr("orderUseCases") }
    static var settingsTitle: String { tr("settingsTitle") }
    static var soundTitle: String { tr("soundTitle") }
    static var rouletteAdvancedTitle: String { tr("rouletteAdvancedTitle") }
    static var glowStyleTitle: String { tr("glowStyleTitle") }
    static func glowStyleName(_ style: GlowStyle) -> String {
        switch style {
        case .white: tr("glowStyleWhite")
        case .slice: tr("glowStyleSlice")
        case .rainbow: tr("glowStyleRainbow")
        }
    }
    static var spinEffectsTitle: String { tr("spinEffectsTitle") }
    static var spinEffectsEnabled: String { tr("spinEffectsEnabled") }
    static func spinEffectName(_ item: SpinEffectItem) -> String {
        switch item {
        case .lights: tr("spinEffectLights")
        case .trails: tr("spinEffectTrails")
        case .particles: tr("spinEffectParticles")
        case .tease: tr("spinEffectTease")
        case .stopEffects: tr("spinEffectStopEffects")
        case .sounds: tr("spinEffectSounds")
        }
    }
    static var spinEffectsSoundNote: String { tr("spinEffectsSoundNote") }
    static var wheel3DTitle: String { tr("wheel3DTitle") }
    static var tiltReferenceTitle: String { tr("tiltReferenceTitle") }
    static func tiltReferenceName(_ reference: TiltReference) -> String {
        switch reference {
        case .flat: tr("tiltReferenceFlat")
        case .grip: tr("tiltReferenceGrip")
        }
    }
    static var appIconTitle: String { tr("appIconTitle") }
    static func appIconName(_ choice: AppIconChoice) -> String {
        switch choice {
        case .standard: tr("appIconStandard")
        case .neon: tr("appIconNeon")
        case .pastel: tr("appIconPastel")
        case .spinner: tr("appIconSpinner")
        case .target: tr("appIconTarget")
        }
    }
    static var appIconFailedTitle: String { tr("appIconFailedTitle") }
    static var appIconFailedMessage: String { tr("appIconFailedMessage") }
    static var soundToggle: String { tr("soundToggle") }
    static var soundNote: String { tr("soundNote") }
    static var close: String { tr("close") }
    static var copyright: String { tr("copyright") }
    static var copyrightTitle: String { tr("copyrightTitle") }
    static var copyrightOwner: String { tr("copyrightOwner") }
    static var trademarkNotice: String { tr("trademarkNotice") }
    static func addItemsButton(_ count: Int) -> String { plural("addItemsButton", count) }
    static var duplicateAddTitle: String { tr("duplicateAddTitle") }
    static var duplicateAddMessage: String { tr("duplicateAddMessage") }
    static var duplicateAddConfirm: String { tr("duplicateAddConfirm") }
    static var duplicateAddCancel: String { tr("duplicateAddCancel") }
    static var resetItemsTitle: String { tr("resetItemsTitle") }
    static var resetItemsDescription: String { tr("resetItemsDescription") }
    static var resetItemsRoulette: String { tr("resetItemsRoulette") }
    static var resetItemsOrder: String { tr("resetItemsOrder") }
    static func resetItemsConfirm(_ screen: String) -> String { fmt("resetItemsConfirm", screen) }
    static var resetItemsMessage: String { tr("resetItemsMessage") }
    static var resetItemsAction: String { tr("resetItemsAction") }
    static var shareResult: String { tr("shareResult") }
    /// 「結果を共有」のメニューの項目。共有シートを開く項目は、画像があれば「画像付きで共有…」、描き終える前は「共有…」。
    static var shareWithImage: String { tr("shareWithImage") }
    static var shareTextOnly: String { tr("shareTextOnly") }
    /// 「結果を共有」のメニューの X・LINE の項目。行き先と動作が分かる名前にする（「X」1 文字は閉じるボタンと間違えられる）。
    static var shareToX: String { tr("shareToX") }
    static var shareToLINE: String { tr("shareToLINE") }
    /// 共有画像で省略した順位の件数の行（「ほか 3 件」）。
    static func shareOrderOthers(_ count: Int) -> String { fmt("shareOrderOthers", count) }
    /// 共有の本文のルーレットの結果の文。`%@` にラベルが入る（`ResultText.roulette(label:template:)`）。
    static var shareRouletteResult: String { tr("shareRouletteResult") }
    /// 共有の本文の順番決めの見出し（並びの前の 1 行）。
    static var shareOrderHeading: String { tr("shareOrderHeading") }
    /// 共有の本文の末尾のハッシュタグ。アプリ名の代わりに置く。
    static var shareHashtag: String { tr("shareHashtag") }
    static var appName: String { tr("appName") }
    static var listMenuLabel: String { tr("listMenuLabel") }
    static var saveListAction: String { tr("saveListAction") }
    static var loadListAction: String { tr("loadListAction") }
    static var manageListsAction: String { tr("manageListsAction") }
    static var appearanceEditAction: String { tr("appearanceEditAction") }
    static var appearanceEditorTitle: String { tr("appearanceEditorTitle") }
    static var appearanceEditorFooter: String { tr("appearanceEditorFooter") }
    static var appearanceAuto: String { tr("appearanceAuto") }
    static var appearanceColorSection: String { tr("appearanceColorSection") }
    static var appearanceEmojiSection: String { tr("appearanceEmojiSection") }
    static var appearanceEmojiPlaceholder: String { tr("appearanceEmojiPlaceholder") }
    static var appearanceEmojiInvalid: String { tr("appearanceEmojiInvalid") }
    static var appearanceEmojiFooter: String { tr("appearanceEmojiFooter") }
    static var appearanceReset: String { tr("appearanceReset") }
    static func appearanceEmojiValue(_ emoji: String) -> String { fmt("appearanceEmojiValue", emoji) }
    /// 色の選択肢の名前。VoiceOver と編集シートの行で読む。
    static func colorName(_ color: SliceColor) -> String {
        switch color {
        case .red: tr("appearanceColorRed")
        case .orange: tr("appearanceColorOrange")
        case .yellow: tr("appearanceColorYellow")
        case .lime: tr("appearanceColorLime")
        case .green: tr("appearanceColorGreen")
        case .cyan: tr("appearanceColorCyan")
        case .blue: tr("appearanceColorBlue")
        case .violet: tr("appearanceColorViolet")
        case .purple: tr("appearanceColorPurple")
        case .pink: tr("appearanceColorPink")
        }
    }

    /// 項目の見た目の説明（「自動」「青」「絵文字 🍣」）。
    static func appearanceDescription(_ appearance: ItemAppearance) -> String {
        switch appearance {
        case .auto: appearanceAuto
        case .color(let color): colorName(color)
        case .emoji(let emoji): appearanceEmojiValue(String(emoji))
        }
    }
    static var noSavedLists: String { tr("noSavedLists") }
    static var saveListTitle: String { tr("saveListTitle") }
    static var saveListNamePlaceholder: String { tr("saveListNamePlaceholder") }
    static var saveListMessage: String { tr("saveListMessage") }
    static var save: String { tr("save") }
    static var cancel: String { tr("cancel") }
    static var savedListsFullTitle: String { tr("savedListsFullTitle") }
    static func savedListsFullMessage(_ max: Int) -> String { fmt("savedListsFullMessage", max) }
    static var savedListsTitle: String { tr("savedListsTitle") }
    static func savedListItemCount(_ count: Int) -> String { fmt("savedListItemCount", count) }
    static var savedListsEmptyHint: String { tr("savedListsEmptyHint") }
    static var renameListTitle: String { tr("renameListTitle") }
    static var rename: String { tr("rename") }
    static var delete: String { tr("delete") }
    static func renameListAccessibilityLabel(_ name: String) -> String { fmt("renameListAccessibilityLabel", name) }
    static var removeAll: String { tr("removeAll") }
    static var removeAllConfirmTitle: String { tr("removeAllConfirmTitle") }
    static func removedToast(_ label: String) -> String { fmt("removedToast", label) }
    static var undo: String { tr("undo") }
    static var hapticsTitle: String { tr("hapticsTitle") }

    static var defaultItems: [String] { lines("defaultItems") }
    static var orderDefaultItems: [String] { lines("orderDefaultItems") }

    static func markLabel(_ mark: Mark) -> String? {
        switch mark {
        case .first: orderMarkFirst
        case .last: orderMarkLast
        case .target: nil
        }
    }

    private static func tr(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    private static func fmt(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: .current, arguments: args)
    }

    /// 複数形（`variations.plural`）を持つ文言。件数に応じた形を選ぶ。
    private static func plural(_ key: String, _ count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString(key, comment: ""), count)
    }

    private static func lines(_ key: String) -> [String] {
        tr(key).split(separator: "\n").map(String.init)
    }
}
