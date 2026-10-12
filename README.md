# deki-roulette

[デキレーレット](https://roulette.basekeita.com/) の iOS アプリ。
結果をユーザが事前に指定できる抽選アプリで、ルーレットと順番決めの 2 画面をタブで切り替える。

機能仕様は [`docs/SPEC.md`](docs/SPEC.md) が正。Web 版（React + Vite）から移植したもので、
プラットフォーム差分は同書の「iOS 版との対応」にまとめてある。Web 版のコードは b7b3936 以前の履歴にある。

## Status

| branch \ workflow | Build | Archive | Upload |
|---|---|---|---|
| main | [![Build](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/build.yml?query=branch%3Amain) | [![Archive](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/archive.yml/badge.svg?branch=main)](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/archive.yml?query=branch%3Amain) | — |
| develop | [![Build](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/build.yml/badge.svg?branch=develop)](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/build.yml?query=branch%3Adevelop) | — | [![Upload](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/upload.yml/badge.svg?branch=develop)](https://github.com/shilokuma-inc/deki-roulette/actions/workflows/upload.yml?query=branch%3Adevelop) |

## CI

GitHub Actions（`.github/workflows/`）。どのワークフローも最初に `xcodegen generate` で `.xcodeproj` を生成する。

| ワークフロー | トリガー | 内容 |
|---|---|---|
| Build | 全ブランチへの push と Fork からの PR | シミュレータでビルドしてユニットテストを実行 |
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

- Xcode 27 / iOS 17.0 以上
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

アプリアイコンは `scripts/make-icon.swift` でレイヤーごとに描き、Icon Composer の `.icon`
（`DekiRoulette/Resources/AppIcon.icon`。`icon.json` と `Assets/` のレイヤー画像）に組み立てている。
背景は `icon.json` の `fill` で、前景（針・ハブ・スライスと区切り線・盤面の外周）はそれぞれ別の group にしてある。
iOS 26 以降は Liquid Glass の質感が付き、iOS 18 以前は Xcode がビルド時に書き出す平面の画像が使われる。
ダーク・色付き・クリアの外観は Icon Composer の自動に任せている。作り直すとき:

```bash
swift scripts/make-icon.swift DekiRoulette/Resources   # DekiRoulette/Resources/AppIcon.icon を作り直す
```

`.icon` の中の画像と `icon.json` はスクリプトの出力なので、手で直さない（Icon Composer で開いて調整を試すのはよいが、
決めた値はスクリプトに戻す。戻さないと次に作り直したときに消える）。スクリプトで指定できるのは、背景（単色・上から下への
グラデーション・自動のグラデーション）と、group ごとの透け具合・縁の光（specular）・影、レイヤーごとの Liquid Glass の有無。
外観ごとの見え方は、Icon Composer に付属する `ictool` で画像に書き出して確かめられる
（`--rendition` は `Default` / `Dark` / `TintedLight` / `TintedDark` / `ClearLight` / `ClearDark`）:

```bash
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  DekiRoulette/Resources/AppIcon.icon --export-image --output-file /tmp/AppIcon.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

アイコンの案は `--candidates` で `<番号>-<名前>.icon` として書き出し（`00` が今の既定のアイコン）、`scripts/preview-icons.swift` で
外観ごと（Default / Dark / TintedDark / ClearLight）の一覧と、60px・40px の一覧の画像にする。`DekiRoulette/` の下に置いた `.icon` は
すべてアプリに入るので、案はリポジトリの外に書き出す:

```bash
swift scripts/make-icon.swift --candidates "$TMPDIR/icon-candidates"
swift scripts/preview-icons.swift "$TMPDIR/icon-candidates" "$TMPDIR/icon-preview"   # preview-*.png を書き出す
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
