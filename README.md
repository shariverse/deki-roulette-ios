# deki-roulette

[デキレーレット](https://roulette.basekeita.com/) の iOS / visionOS アプリ。
結果をユーザが事前に指定できる抽選アプリで、ルーレットと順番決めの 2 画面をタブで切り替える。

機能仕様は [`docs/SPEC.md`](docs/SPEC.md) が正。Web 版（React + Vite）から移植したもので、
プラットフォーム差分は同書の「iOS 版との対応」「visionOS 版との対応」にまとめてある。
Web 版のコードは b7b3936 以前の履歴にある。

## Status

| branch \ workflow | Build | Archive | Upload |
|---|---|---|---|
| main | [![Build](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/build.yml?query=branch%3Amain) | [![Archive](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/archive.yml/badge.svg?branch=main)](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/archive.yml?query=branch%3Amain) | — |
| develop | [![Build](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/build.yml/badge.svg?branch=develop)](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/build.yml?query=branch%3Adevelop) | — | [![Upload](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/upload.yml/badge.svg?branch=develop)](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/upload.yml?query=branch%3Adevelop) |

## CI

GitHub Actions（`.github/workflows/`）。どのワークフローも最初に `xcodegen generate` で `.xcodeproj` を生成する。

| ワークフロー | トリガー | 内容 |
|---|---|---|
| Build | 全ブランチへの push と Fork からの PR | iOS と visionOS のシミュレータでビルドしてユニットテストを実行 |
| Archive | `main` への push、手動実行 | Release 構成でアーカイブし、App Store Connect API キーで署名して IPA を書き出す |
| Upload | `develop` と `release/**` への push、手動実行 | Archive に加えて TestFlight へアップロードし、IPA を Artifacts に残す |

ドキュメントだけの変更（`**/*.md`、`docs/**`）では Build を実行しない（Upload / Archive は実行する）。

作業ブランチで走るのは Build だけ。TestFlight へのアップロードには App Store Connect 側の 24 時間あたりの
上限（`Upload limit reached (90382)`）があり、作業ブランチまで上げていると枠を使い切るため。
作業ブランチのビルドを実機で確認したいときは、Upload を手動実行してそのブランチを選ぶ。

ビルド番号 (`CFBundleVersion`) はワークフローの `run_number` で上書きする。Archive / Upload には次の Secrets が必要:

| Secret | 内容 |
|---|---|
| `EXPORT_OPTIONS` | `ExportOptions.plist` の中身 |
| `APPLE_API_KEY_BASE64` | App Store Connect API キー (`.p8`) を base64 にしたもの |
| `APPLE_API_KEY_ID` | 同キーの Key ID |
| `APPLE_API_ISSUER_ID` | 同キーの Issuer ID |

署名もアップロードもこの API キーで行う。Upload が通るには、App Store Connect に Bundle ID
`com.basekeita.roulette` のアプリがあらかじめ登録されている必要がある。

## 環境

- Xcode 27 / iOS 17.0 以上 / visionOS 26.0 以上
- Swift 6（strict concurrency: complete）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

## セットアップ

`.xcodeproj` はコミットせず、`project.yml` から生成する。

```bash
xcodegen generate
open DekiRoulette.xcodeproj
```

コマンドラインでのビルドとテスト:

```bash
xcodebuild -project DekiRoulette.xcodeproj -scheme DekiRoulette \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

```bash
xcodebuild -project DekiRoulette.xcodeproj -scheme DekiRoulette \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

visionOS（Apple Vision Pro シミュレータ）では `-destination` を差し替える:

```bash
xcodebuild -project DekiRoulette.xcodeproj -scheme DekiRoulette \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' test
```

アプリアイコンは `scripts/make-icon.swift` で描いている。作り直すとき（第 2 引数を渡すと visionOS 用の 2 層 `AppIcon.solidimagestack` も同時に作る）:

```bash
swift scripts/make-icon.swift \
  DekiRoulette/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
  DekiRoulette/Resources/Assets.xcassets/AppIcon.solidimagestack
```

## 構成

```
DekiRoulette/
  App/            DekiRouletteApp（入口）, RootView（2 タブ）
  Core/           Config（定数）, Item, ItemLabel（正規化）, Shuffle（Fisher-Yates と arrange）,
                  RouletteMath（回転角の計算）, RevealTiming（演出時間）
  Design/         Theme（配色・アニメーション）, reveal 演出
  Features/
    Roulette/     RouletteModel, RouletteWheelView（盤面）, RouletteScreen
    Order/        OrderModel, OrderResultView, OrderScreen
    Shared/       ItemListView（項目リストと隠しジェスチャ）, MarkDot（印）, PageFrame（共通枠）,
                  SettingsView（設定）, PrimaryActionButton, AdaptiveStack
  Localization/   Localizable.xcstrings（日英）, InfoPlist.xcstrings, L10n
  Resources/      Assets.xcassets
DekiRouletteTests/  Swift Testing によるユニットテスト
```

Web 版との対応:

| Web 版 | iOS 版 |
|---|---|
| `src/config.ts` | `Core/Config.swift` |
| `src/items.ts` | `Core/ItemLabel.swift` |
| `src/shuffle.ts` | `Core/Shuffle.swift` |
| `useRoulette.spin` の角度計算 | `Core/RouletteMath.swift` |
| `src/hooks/useRoulette.ts` | `Features/Roulette/RouletteModel.swift` |
| `src/hooks/useOrder.ts` | `Features/Order/OrderModel.swift` |
| `src/hooks/useLongPress.ts` | `ItemListView` の `onLongPressGesture` |
| `src/components/*` | `Features/*/…View.swift` |
| `src/i18n.ts` | `Localization/Localizable.xcstrings` + `L10n.swift` |
| `tailwind.config.ts` | `Design/Theme.swift` |

## ライセンス

MIT
