# deki-roulette

[デキレーレット](https://roulette.basekeita.com/) の iOS アプリ。
結果をユーザが事前に指定できる抽選アプリで、ルーレットと順番決めの 2 画面をタブで切り替える。

機能仕様は [`docs/SPEC.md`](docs/SPEC.md) が正。Web 版（React + Vite）から移植したもので、
プラットフォーム差分は同書の「iOS 版との対応」にまとめてある。Web 版のコードは b7b3936 以前の履歴にある。

## Status

| branch \ workflow | Build | Archive | Upload |
|---|---|---|---|
| main | [![Build](https://github.com/shariverse/deki-roulette-ios/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/shariverse/deki-roulette-ios/actions/workflows/build.yml?query=branch%3Amain) | [![Archive](https://github.com/shariverse/deki-roulette-ios/actions/workflows/archive.yml/badge.svg?branch=main)](https://github.com/shariverse/deki-roulette-ios/actions/workflows/archive.yml?query=branch%3Amain) | — |
| develop | [![Build](https://github.com/shariverse/deki-roulette-ios/actions/workflows/build.yml/badge.svg?branch=develop)](https://github.com/shariverse/deki-roulette-ios/actions/workflows/build.yml?query=branch%3Adevelop) | — | [![Upload](https://github.com/shariverse/deki-roulette-ios/actions/workflows/upload.yml/badge.svg?branch=develop)](https://github.com/shariverse/deki-roulette-ios/actions/workflows/upload.yml?query=branch%3Adevelop) |

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
ダーク・色付き・クリアの外観は Icon Composer の自動に任せている。

既定のアイコンのほかに、iOS 標準の代替アイコン（`UIApplication.setAlternateIconName(_:)` で切り替える）を 4 つ持つ。
32 案から選定で採用した `AppIcon-Neon`・`AppIcon-Pastel`・`AppIcon-Spinner`・`AppIcon-Target` で、
`DekiRoulette/Resources/AppIcon-<名前>.icon` に置き、`project.yml` の `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` に並べている。
作り直すとき（既定と代替をまとめて書き出す）:

```bash
swift scripts/make-icon.swift DekiRoulette/Resources   # AppIcon.icon・AppIcon-<名前>.icon と、設定画面の見本の imageset を作り直す
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

利用者は設定シートの「アプリアイコン」で選ぶ。候補の一覧は `DekiRoulette/Core/AppIconChoice.swift` で、グリッドの見本には
スクリプトが `ictool` で書き出した `DekiRoulette/Resources/Assets.xcassets/<名前>-Preview.imageset` を使う（アイコンそのものは `UIImage(named:)` で読めない）。

代替アイコンを足すとき:

1. `scripts/make-icon.swift` の `alternateIcons` に `IconDesign(name: "AppIcon-<名前>", …)` を足す（案から採用するときは `candidates` から移す）
2. `swift scripts/make-icon.swift DekiRoulette/Resources` で `DekiRoulette/Resources/AppIcon-<名前>.icon` と見本の `AppIcon-<名前>-Preview.imageset` を書き出す
3. `project.yml` の `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` に `AppIcon-<名前>` を空白区切りで足し、`xcodegen generate` を流す
4. `AppIconChoice` に `case` を足し（`rawValue` は `AppIcon-<名前>`）、`L10n.appIconName` と `Localizable.xcstrings`（日英）に表示名を足す。
   `AppIconChoiceTests` の「名前は変えない」の一覧にも足す

消すときは、手順 1・3・4 で足したもの（スクリプトの `alternateIcons`・`project.yml`・`AppIconChoice` と表示名・テストの一覧）から名前を消し、
`DekiRoulette/Resources/AppIcon-<名前>.icon` と `Assets.xcassets/AppIcon-<名前>-Preview.imageset` を消す（スクリプトは消さない）。
名前の食い違いは `AppIconChoiceTests` が、ビルドした `Info.plist`（`CFBundleIcons` / `CFBundleIcons~ipad` の `CFBundleAlternateIcons`）と、
`DekiRoulette/Resources` の `.icon` に突き合わせて見つける。利用者が選んだアイコンは `UIApplication.alternateIconName` に名前で残るので、
リリースした代替アイコンの名前は変えない。

新しいアイコンを選ぶときは、`candidates` に案を足し、`--candidates` で `<番号>-<名前>.icon` として書き出して
（`00-` は今アプリに入っているアイコンで、見比べる用）、`scripts/preview-icons.swift` で外観ごと（Default / Dark / TintedDark / ClearLight）の
一覧と、60px・40px の一覧の画像にする。`DekiRoulette/` の下に置いた `.icon` はすべてアプリに入るので、案はリポジトリの外の空のディレクトリに書き出す:

```bash
dir=$(mktemp -d)
swift scripts/make-icon.swift --candidates "$dir/icons"
swift scripts/preview-icons.swift "$dir/icons" "$dir/preview"   # preview-*.png を書き出す
swift scripts/preview-icons.swift DekiRoulette/Resources "$dir/app"   # アプリに入っているアイコンだけの一覧
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
