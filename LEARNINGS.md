# LEARNINGS — deki-roulette-ios 固有の知見

開発の中で得た、このリポジトリだけに当てはまる知見を溜める。全リポジトリ共通の知見は `~/.agents/LEARNINGS.md` に書く。
PC 固有の値（ローカルパス・Simulator の UDID・ユーザー名）と秘密情報は書かない。

## アプリアイコン（Icon Composer の .icon）

- `icon.json` の `groups` と、各 group の `layers` は先頭が手前になる（2026-10-12）
- group の `translucency` は、`enabled: false` にするときも `value` を書く。無いと `ictool` が「The data couldn’t be read because it is missing.」で書き出しに失敗する（2026-10-12）
- group の透け具合を既定のまま（有効）にすると、背景の暗い色が混ざってスライスの色がくすむ。今の絵の色を保つため、`scripts/make-icon.swift` は既定で透かさない（2026-10-12）
- iOS 18 の Simulator のホーム画面に出るのは、Xcode がビルド時に書き出した平面の画像で、Liquid Glass の縁の光も焼き込まれている（iOS 26 と同じ印象になる）（2026-10-12）
- `icon.json` の `fill` の `linear-gradient` は、`orientation` の `y` が 0 で上、1 で下（2026-10-12）
- `ictool` の `ClearLight` / `ClearDark` の書き出しは、壁紙が透けない不透明な灰色の板になる。一覧の背景に色を付けても見えるのは板の外だけ（2026-10-12）
- `ictool` の書き出しは 1 回 0.3 秒ほどかかる。33 案 × 外観 4 つ + 小さいサイズ 2 つで 1 分ほど（2026-10-12）

## 代替アイコン

- `UIApplication.setAlternateIconName(_:)`（async 版）は、iOS 26.5 と 18.6 の Simulator で「アイコンを変更しました」のアラートの OK を押すまで返らない。アイコンはアラートが出た時点で変わっている（2026-10-12）
- Simulator で代替アイコンの切り替えを試すには、テストのホストアプリ（`DekiRouletteTests` の `TEST_HOST` は `DekiRoulette.app`）から `setAlternateIconName` を呼ぶ。
  `TEST_RUNNER_<名前>=値 xcodebuild test …` で、テストの `ProcessInfo.processInfo.environment["<名前>"]` に値を渡せる。上のとおり返らないので、ホーム画面を撮ったらテストを止める（2026-10-12）
- ビルドした `Info.plist` の `CFBundleAlternateIcons` には、代替アイコンごとに `CFBundleIconName` だけが入る（`CFBundleIconFiles` の PNG は既定のアイコンの分しか `.app` に書き出されない）（2026-10-12）
