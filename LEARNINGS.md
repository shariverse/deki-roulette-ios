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
- `.icon` のアプリアイコンの名前を `UIImage(named:)` に渡すと、iOS 26.5 の Simulator では UIKit のアサーション（`-[_UIImageCGImageContent initWithCGImageSource:CGImage:scale:]`）で落ち、
  18.6 では nil が返る。設定画面の見本は `scripts/make-icon.swift` が `ictool` で書き出した imageset（`<名前>-Preview`）を使う（2026-10-12）
- `Bundle.main.object(forInfoDictionaryKey:)` は、iPhone では `CFBundleIcons~ipad` のような端末に合わないキーを返さない（nil）。
  端末に依らず Info.plist を見るテストでは、`Bundle.main.bundleURL` の `Info.plist` を `PropertyListSerialization` で読む（2026-10-12）
- UI テストのターゲットが無いので、PR の画面のスクリーンショットは、コミットしない一時的なテストからホストアプリの `rootViewController` に
  `UIHostingController` を present して `xcrun simctl io <SIM> screenshot` で撮る（テストが目印を print して待つ間に撮る）。
  `NavigationLink` や `Button` は、見つけたアクセシビリティ要素の `accessibilityActivate()` で押せる（2026-10-12）
- `Button` の外側に `.accessibilityElement(children: .ignore)` を付けて名前を付け直すと、`accessibilityActivate()` で動作が起きない（VoiceOver や
  フルキーボードアクセスから押せないおそれがある）。読ませたくない画像は `.accessibilityHidden(true)` にして、名前はボタンの中の `Text` から読ませる（2026-10-12）

## テスト（Swift Testing）

- `#expect` の中で `CGFloat` と `Double` を `==` で比べると、値が同じでも常に偽になる（マクロの展開で暗黙の変換が効かない）。ローカルで通っているように見えてもテストを動かせる Mac が無いと気付けないので、`abs(a - b) < 1e-9` のように同じ型にそろえてから比べる。`CGPoint` / `CGSize` を使う `Core/` のファイルとテストは `import CoreGraphics` を明示する（2026-10-16）
- `ImageRenderer` で焼いた画像の画素を見るテストでは、止まったスライスの光彩（`stopGlow` の `.shadow`）が半径の 2〜3 倍まで届く（`Wheel3DView` が焼く余白を `stopGlowRadius × scale × 3` 取っているのと同じ）。
  「地」の色を見る画素は光彩の外（画像の縁の近く）に置く。盤面のすぐ上の余白で見ると、地より明るくなって許容 0.04 を超える（2026-10-16）
- `xcodebuild build-for-testing` はラッパー経由でローカルでも動くので、テストを動かせる Mac が無いときもテストのコンパイルまでは確かめられる
  （`build` ではスキームの設定上テストターゲットはビルドされない）（2026-10-16）

- テストを動かせる Mac が無いとき、`Core/` の純粋関数は使うファイルだけを `swiftc` で macOS 向けにまとめてビルドし、使い捨ての `main.swift` で
  テストと同じ条件の値を出して確かめられる（`Config.swift` の `import SwiftUI` は macOS でも通る。`WheelLabel` は `ItemAppearance` に依るので、
  `referenceDiameter` だけの stub を置く）。作業ツリーの外の一時ディレクトリで行い、コミットしない（2026-10-18）

## 効果音

- スピンの動きに合わせた音（うなり）を 5.7 秒分 1 本の波形に焼く（0.12 秒の 1 打ちを約 40〜50 回、線形補間で伸び縮みさせて足す）のは、
  macOS の `-O` で 3〜9ms。Debug ビルドではこれより桁で遅くなりうるので、スピン開始時はメインスレッドの外（`Task.detached`）で焼き、待った分の頭を切り落とす（2026-10-18）
- `Core/` を `swiftc` でまとめてビルドするとき、`SpinPath.swift` は `HapticSchedule.swift`（→ `RevealTiming.swift`）を、`SpinTease.swift` の
  `FlickSpin.swift` は `WheelDrag.swift` を引き込む。`cannot find '…' in scope` の名前のファイルを足していけば通る（2026-10-18）

## スピンの演出（パーティクル）

- 粒子は前のフレームの状態を積み上げず、生まれた時刻からの経過の閉じた式（抵抗のある放物運動は `(1 - e^{-kt}) / k`）で位置を出し、粒ごとの乱数は
  演出の種と粒の番号から作った SplitMix64 で引く。どのフレームから描いても同じ絵になり、`TimelineView` を止めて再開しても飛ばない。乱数を引く数は
  生まれる・生まれないに依らず同じにしておく（途中で抜けると同じ種でも後の値がずれる）（2026-10-18）
- 「同時に出る数 ≤ 上限」は、生まれうる時刻を 寿命の最大 ÷ 上限 の間隔に区切り、各時刻に強さの確率で 1 粒生む形にすると構造的に守れ、数も強さに比例する（2026-10-18）

## アニメーション

- 単調でない動き（止まり際の焦らしで戻る・行き過ぎる）も、iOS 17 の `CustomAnimation` なら `withAnimation` と `.animation(_:value:)` のまま補間できる。
  `animate(value:time:context:)` は補間する値の差（`VectorArithmetic`）を受け取るので、`value.scaled(by: 進み具合)` を返せばよく、進み具合は途中で戻っても 1 を超えてもよい。
  長さを過ぎたら nil を返すと終わる。`withAnimation` の `completion` が焦らしの終わりで呼ばれるかは実機・Simulator で未確認なので、長さから決めた保険のタイマーも残す（2026-10-18）
- 乱数を注入できるモデルで「指定の有無で同じ動き」をテストするときは、指定があっても止まる項目の乱数を引いて捨てる。指定のときだけ引かないと、
  後に続く乱数（焦らしの入り方）の位置がずれて、同じ種でも動きが変わる（2026-10-18）

## スピンの演出（明滅・脈動）

- 光過敏への配慮で「1 秒に 3 回未満」を守るときは、演出ごとではなく同時に出る演出の明るさの山をまとめて数える。停止の瞬間のフラッシュと
  電飾の全灯の点滅（0.6 秒周期 × 2）を別々に始めると、フラッシュ（0 秒）・点滅（0.3・0.9 秒）で 1 秒に 3 回になる。点滅を明るいところから始めて
  フラッシュと重ね、山の時刻を細かく拾って 1 秒の窓ごとに数えるテストで確かめる（2026-10-18）
- 電飾の脈動は点滅の終わり d を起点にしているので、光彩の余韻も停止からの経過 t で同じ起点の 0.5 - 0.5cos(2π(t - d)/T) から引くと位相がそろう。別々の View の脈動の位相をそろえるには、
  停止の時刻を親の View が 1 つだけ持って両方に渡す（各 View の `onChange` で `now()` を取ると、後から出た View とずれる）（2026-10-18）
- ゆっくりした脈動だけを描く `TimelineView` は `.animation(minimumInterval:paused:)` で間隔を落とせる（スケジュールの型は同じなので、
  `minimumInterval` に nil と値を切り替えられる）。切り替えの時刻は `.task(id:)` で待って `@State` を書き、body に読ませて描き直させる（2026-10-18）

## 入力欄・CI

- SwiftUI の `TextField` の binding は、かな入力の変換中（未確定の文字）でも更新される。入力のたびに値を判定して書き戻すと変換が壊れる（「すし」→ 🍣 の「す」で弾く）。
  1 文字に絞るなどの判定は、Return（`onSubmit`）・フォーカスが外れたとき・画面を離れたときの確定時に行う（2026-10-18）
- `.github/workflows/build.yml` の PR 側のジョブは、同じリポジトリのブランチでは `if` で常にスキップされ、push 側だけで走る。push 側は `paths-ignore` で
  `**/*.md` と `docs/**` だけの変更では走らないので、最後のコミットがドキュメントだけだと `gh pr checks` にはスキップしか出ない。
  その前のコードのコミットの push の Build の結果を見る（2026-10-18）
