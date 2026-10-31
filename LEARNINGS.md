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

- 粒ごとの乱数を種と番号から作るときは、番号を SplitMix64 の仕上げの式（mix）に通してから種と混ぜる。番号 × 黄金比の定数を種に XOR するだけだと、
  種が 0 のとき粒 i + 1 の初期状態が粒 i の状態を 1 歩進めたものになり、列が 1 つずれただけになる。仕上げの式は 0 を 0 に写すので、番号には定数を足してから通す
  （`mix(index + 0x9E3779B97F4A7C15)` は SplitMix64 を番号で始めた最初の出力。種 0 の最初の出力 `0xE220A8397B1DCDAF` で式を確かめられる）（2026-10-18）

## スピンの演出（指で動かしている間）

- 指で動かしている間の角度は View の state なので、補間中の角度のように曲線から引けない。指が動くたびに位置・角度を値型（`WheelDragMotion`）に記録して
  子の View に渡し、時刻 t の値は t までの点だけから求める（平滑した角速度は記録したときに点ごとに持つ）。こうすると過ぎた時刻の値が後から点が増えても変わらず、
  火花のような閉じた式の粒が出たり消えたりしない（2026-10-18）
- `DragGesture.Value.time` は `Date` の秒で、演出の時計（`systemUptime`）と別。ドラッグを始めたときに両方の今の時刻からずれを 1 回だけ求め、
  指の時刻に足してから記録する（描いた時刻ではなく指が動いた時刻を使えるので、フリックの角速度と同じ値になる）（2026-10-18）
- 角度に比例する見た目（電飾の並びの位置）の速さに上限を付けると閉じた式で書けないので、角度の変化だけを積む状態を参照型に入れて `@State` で持ち、
  `TimelineView` の中で進める（書き換えても描き直さない）。上限は経過時間に比例させ 1 回には 1 フレーム分までにすると、親の描き直しと `TimelineView` が
  同じフレームに 2 回描いても上限を超えない（2026-10-18）

- 指で動かしている間に、時刻から求めた差（残像のずらし = 今の角度 − 遅れた時刻の角度）を盤面に見えている角度（指のイベントでしか変わらない state）に足すと、
  イベントの間のフレームで見えている角度は止まったまま差だけが縮んで伸び縮みする。差は見えている角度と同じ時刻（最後の点の時刻 `min(now, lastTime)`）から測る（2026-10-18）
- 遅れを持ち越す流れは、盤面が逆へ動いたときに持ち越した分を捨てないと、向きを変えても前の向きへ流し続ける。変化と遅れの符号が逆なら 0 にする。
  また、出していない間に進めない流れ（3D で電飾を OFF にした間）は、出し直したときの角度の差を流さないよう、出さなくなったら作り直す（2026-10-18）
- 1 回に進める量を経過時間で抑える流れ（電飾の並び）は、指で動かしている間に捨てすぎる。角度が変わる描き直し（指の動きで親が描き直す）は
  直前の `TimelineView` の描き直しから間もなく来て経過時間が短く、経過時間の長い `TimelineView` の描き直しでは角度が変わらないため、
  上限より遅い動きでも差のほとんどを捨ててしまう。流し切れなかった分を上限付きで次に持ち越すと、上限の範囲で追いつき、遅い動きは盤面と同じだけ進む（2026-10-18）

## 3D の盤面（SceneKit）

- SceneKit は線形の色空間で描いて重ねるので、2D（SwiftUI の `Canvas`。sRGB のまま重ねる）と同じ色を不透明度で重ねると、暗い地の上では 2D より明るく見える。
  地の色が決まっているもの（縁の上の電球）は、2D で重ねた色を sRGB のまま混ぜて求め、不透明に塗ると画素まで 2D と同じ色になり、テストも色で比べられる（2026-10-18）
- SceneKit で毎フレーム形の変わる帯（長さの変わる光の尾の弧）は、メッシュを作り直さず、同じ形の短い切れ端を最長の長さ分並べて回しておき、
  切れ端ごとの不透明度と表示・非表示だけを変えると軽い。濃さは切れ端の中央の位置で 2D の区間の濃さを引く関数（`WheelTrails.Trail.opacity(atDistance:segments:)`）を
  2D と共有すると同じ位置が同じ濃さになる。同じ形のものを複数出すとき（残像の枚数）は `SCNGeometry` を複数のノードで共有し、ノードの `opacity` と角度だけを変える（2026-10-18）
- SceneKit の画像を貼った板は、透明な画素でも深度を書く。奥の半透明の重ね（深度を書かない残像）より先に描かれると、板の透明な余白の形に残像が抜ける。
  重ねるものは `writesToDepthBuffer = false` にして、手前に来る画像の板（結果の帯）の `renderingOrder` を大きくして後に描く（2026-10-18）
- 補間中の角度は `Animatable` の層（`Wheel3DSurface`）が毎フレーム受け取るが、角度が動かない間（結果表示中の点滅・脈動、指を止めたあとの落ち方）も
  毎フレーム描くものは、その層を `TimelineView` で包んで値を渡す。止める条件は 2D と同じ関数で決め、2D と 3D で同じ時計・同じ規則の View（`WheelLightsTimeline`）を共有すると、
  同じ時刻に同じ値になる（2026-10-18）
- 2D と同じ数・寿命・位置の粒子を 3D に出すときは、`SCNParticleSystem`（発生と寿命をシステムが乱数で持つ）ではなく、2D と同じ閉じた式で引いた粒を
  上限の数だけ作ったノードに毎フレーム写すと一致させやすく、画素のテストにも使える（数が 140 程度なら位置・大きさ・不透明度の書き換えは軽い）（2026-10-18）
- 長さと向きの変わる細い板（火花の尾）は、`SCNPlane(width: 1, height: 1)` のノードに `pivot = SCNMatrix4MakeTranslation(-0.5, 0, 0)` を付けると、
  板の左端がノードの位置に来て、`scale.x` が付け根から先への長さ、`eulerAngles.z` が向きになる（2026-10-18）
- 深度の前後に依らず「針の手前・結果の帯の奥」のように重ねたいものは、素材を `readsFromDepthBuffer = false`・`writesToDepthBuffer = false` にして
  `renderingOrder` を針より大きく帯より小さくする（帯は後に描かれて上に重なり、帯の画像の透明な余白からは奥が見える）（2026-10-18）
- 盤の表面から z だけ浮かせた面は、カメラまでの距離 d に対して d ÷ (d − z) 倍に広がって見える。2D と同じ枠に収めたい板（フラッシュ・紙吹雪）は
  ノードを (d − z) ÷ d 倍に縮めると、正面から見て表面と同じ大きさになる（2026-10-18）
- 画像に焼いた光彩だけを脈打たせるときは、光彩ごと焼いた板の上に光彩の無い同じ面の板を重ね、下の板の不透明度を倍率にする（面の中は不透明なので、
  はみ出した光彩だけが薄くなる。倍率 1 なら 1 枚のときと同じ見た目）。毎フレーム焼き直さずに済む（2026-10-18）
- `SCNRenderer.snapshot(atTime: 0)` の画面外描画は、直前に `SCNTransaction`（`animationDuration` > 0）で変えた値を動きの始まり（変える前の値）で描く。
  `highlight(_:reduceMotion: false)` の直後に描くと、暗くする層は不透明度 0 のまま写る（CI で、無いはずの差を比べて落ちた）。
  出し切った見た目を画素で確かめるときは、動きを付けない経路（動きを減らす設定）で作る（2026-10-18）
- iOS の SceneKit で `node.setValue(NSValue(scnVector3: v), forKeyPath: "scale")` は成分を読み違える（(1.07, 1.07, 1) が (3.7e19, 1.88, 3.7e19) になる。
  `position` の (1, 2, 3) は (0, 1.875, 0)）。macOS では起きない。値は `node.scale = v` のように型のあるプロパティに書き、`NSValue(scnVector3:)` は
  `CABasicAnimation` / `CASpringAnimation` の `fromValue` / `toValue` にだけ使う（こちらは正しく動く）（2026-10-19）
- `SCNRenderer.snapshot(atTime:)` の時刻はシステムの時計（`CACurrentMediaTime()`）。`CACurrentMediaTime() + 2` を渡すと、足したばかりの動き
  （`SCNTransaction`・`addAnimation`）が終わったあとの見た目を描ける（2026-10-19）
- テストを動かせる Mac が無いときも、手元の Xcode と起動中の Simulator があれば、アプリの Swift ファイル（`@main` の App を除く）を `swiftc -parse-as-library
  -enable-testing -emit-library -static -emit-module` で Simulator 向けの静的ライブラリにし、テストのファイルと
  `@main struct Runner { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }` を `-framework Testing`（Simulator のプラットフォームの
  `Developer/Library/Frameworks`）・`-plugin-path`（ツールチェーンの `usr/lib/swift/host/plugins/testing`）で実行ファイルにして、`xcrun simctl spawn <端末> <実行ファイル> --filter <型>` で流せる。
  バンドルの資源（音源・画像・Info.plist）を読むテストと、メインの実行ループの時刻に依るテストはこの方法では落ちる（2026-10-19）
- 上の `simctl spawn` の方法でも、`Wheel3DSceneTests`（`SCNRenderer` の画面外描画・`snapshot(atTime: CACurrentMediaTime() + 2)`）は流せる。
  テストのファイルが別のテストのファイルの補助に依ることがあり、`SeededGenerator` は `SeededGenerator.swift`、`WheelDragMotion.testCircular` は
  `WheelDragMotionTests.swift` にあるので、`WheelParticlesTests` を流すときは一緒にビルドする（`cannot find … in scope` の名前で探す）（2026-10-19）
- 同じノードの `scale` に 2 つの動き（現れ方の 0.96 倍と登場演出の 0.6 倍からのばね）を重ねるときは、親と子のノードに分けて掛ける（2026-10-18）


## アニメーション

- 単調でない動き（止まり際の焦らしで戻る・行き過ぎる）も、iOS 17 の `CustomAnimation` なら `withAnimation` と `.animation(_:value:)` のまま補間できる。
  `animate(value:time:context:)` は補間する値の差（`VectorArithmetic`）を受け取るので、`value.scaled(by: 進み具合)` を返せばよく、進み具合は途中で戻っても 1 を超えてもよい。
  長さを過ぎたら nil を返すと終わる。`withAnimation` の `completion` が焦らしの終わりで呼ばれるかは実機・Simulator で未確認なので、長さから決めた保険のタイマーも残す（2026-10-18）
- 乱数を注入できるモデルで「指定の有無で同じ動き」をテストするときは、指定があっても止まる項目の乱数を引いて捨てる。指定のときだけ引かないと、
  後に続く乱数（焦らしの入り方）の位置がずれて、同じ種でも動きが変わる（2026-10-18）
- 焦らしの区間の速さを `humMinIntensity`（36°/秒）未満に保つときは、区間の距離 ÷ 長さに曲線の傾きの山を掛けて見積もる。`cubic-bezier(0.42, 0, 0.58, 1)` の山は
  約 1.72 倍、`cubic-bezier(0.37, 0, 0.63, 1)`（sine）は約 1.59 倍。ただし `WheelParticlesTests` の「焦らしの区間では火花はごくわずか」は寿命 0.5 秒の窓の平均の強さで
  粒の数が決まり（種 20 個 × 各フレームの最大を見る）、山が下限に届かなくても窓の平均が 0.039 ほどあると上限の 1/10 を超えることがある（2026-10-19）

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

## 文言・設定画面

- `Localizable.xcstrings` はキーが並べ替えられていない（追加順）。Python の `json.load` → `json.dump` で書き直すと、空のエントリ（`"%lld" : {}`）の書き方や並び順が変わって差分が数百行に膨らむ。
  キーの追加・削除はテキストのまま該当の塊だけを差し替える（`json.loads` で壊れていないかだけ確かめる）（2026-10-19）
- `@AppStorage` を束ねた `DynamicProperty` の struct を View に持たせるとき、`private var x = …` にすると View の memberwise init が private になり、
  ほかのファイルから View を作れなくなる。`private let` にする（`DynamicProperty` は `let` でも更新を受ける）（2026-10-19）
- 「ルーレットの詳細設定」（`RouletteAdvancedSettingsView`）は `private` なので、スクリーンショットを撮るときは一時的に `private` を外し、コミットしない一時テストから
  `NavigationStack { RouletteAdvancedSettingsView() }` を present する。保存値の状態を変えて撮るときは
  `xcrun simctl spawn <SIM> defaults write <バンドル ID> <キー> -bool NO` で書いてから起動し、撮ったら `defaults delete` で戻す（2026-10-19）

## 書体（同梱のフォント）

- 環境に `.fontDesign(.rounded)` を置いたままだと、その下の `Font.custom(...)` の文字もシステムの丸ゴシック（日本語はヒラギノ角ゴ）で描かれ、同梱の書体が出ない（エラーも出ない）。同梱の書体を当てる View の上に `fontDesign` を置かない（2026-10-21）
- iOS 26 の SwiftUI の `navigationTitle` の文字は、`UINavigationBar.appearance()` の `titleTextAttributes` や `UINavigationBarAppearance` を設定しても変わらない。題名を同梱の書体にするには `.principal` の `ToolbarItem` に `Text` を置く。
  一方、ツールバーの文字のボタン（`Button("閉じる")` / `EditButton`）は環境の `.font` で描かれるので、アプリの根に本文の書体を掛けると Regular になる（ボタンに太さを明示する）。タブの項目は `UITabBarAppearance` の `titleTextAttributes` が効く（2026-10-21）
- iOS 26 の大きいタイトルを同梱の書体にするには、toolbar の `ToolbarItem(placement: .largeTitle)` / `.largeSubtitle` に `Text` を置く（中央寄せになるので `.frame(maxWidth: .infinity, alignment: .leading)`）。
  ただし `.toolbarBackground(_:for: .navigationBar)` と `.visible` を付けると大きいタイトルの置き場所が出なくなり、色だけ付けてもスクロールの途中の位置でバー全体が白く覆われる。地は塗らず、`.scrollEdgeEffectStyle(.hard, for: .top)` で読みやすくする。
  `.title` / `.subtitle` の置き場所の `Text` は大きいタイトルが出ている間も常に出る（置かないと縮んだ題名はシステムの書体）ので、`onScrollGeometryChange` で縮み切ったときだけ見せる。
  大きいタイトルが縮む間は `contentInsets.top`（バーの下端）がスクロールした分だけ減り（iPhone 17 Pro で 187 → 116）、その間 `contentOffset.y + contentInsets.top` は 0 のまま。途中で離すと展開か縮み切りに戻る。
  置き場所の `Text` の `accessibilityHidden` は Simulator の読み上げの木では効かない（2026-10-31）
- Zen Maru Gothic には `tnum`（等幅の数字）が無く、`.monospacedDigit()` を掛けても数字の字幅は変わる。行の高さはヒラギノより大きく、同じ文字サイズでも行が少し高くなる（2026-10-21）
- フォントのファイルが同じものかは、`git hash-object <ファイル>` の値を GitHub の contents API（`gh api repos/<owner>/<repo>/contents/<パス>`）の `sha` と比べると確かめられる（2026-10-21）

## 盤面の当たり判定・UI テスト

- 盤面の上の `Color.clear` に付けた `contentShape` を円（`WheelHitShape`）にすると、円の外のタッチは `highPriorityGesture` の `DragGesture` に届かず、
  後ろの `PageFrame` の `ScrollView` がそのまま受けてスクロールする（2D の盤面・3D の `SCNView`（`isUserInteractionEnabled = false`）・`allowsHitTesting(false)` の演出の層は
  タッチを取らないので、四隅に別の層は要らない）。判定は触れ始めの位置だけで、円の内側で始めたドラッグは指が外へ出ても続く（2026-10-30）
- このリポジトリには UI テストのターゲットが無い。画面で確かめるときは `project.yml` に `type: bundle.ui-testing`・`platform: iOS`・`TEST_TARGET_NAME: DekiRoulette` の
  ターゲットを足し、スキームの `test.targets` にも足して `xcodegen generate` し、`-only-testing:<ターゲット>` で流す（`project.yml` とテストのファイルはコミットしない）。
  盤面は `accessibilityHidden` なので、座標は「スピン」ボタンの frame から求める（盤面の下端はボタンの 24pt 上、compact では一辺 320pt）。
  フリックは `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` で、スピンが始まったかはボタンの文言（「スピン中…」）で見る。
  3D は launch の引数 `-wheel3DEnabled YES` で入る（2026-10-30）
- 一時的な UI テストのソースはスロットの外（`ralph-dd` の下の接頭辞付きのディレクトリ）に置き、`project.yml` の `sources` に絶対パスで渡すと、スロットには `project.yml` の変更しか残らない。
  大きいタイトルを途中まで縮めるドラッグは `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` で指を止めてから離す（止めないと慣性で流れる）。`sips --cropOffset` は効かず中央を切り抜く（2026-10-31）
- 一時的な UI テストのスクリーンショットは `XCTAttachment(screenshot:)` を `lifetime = .keepAlways` で残し、`-resultBundlePath` の `.xcresult` から
  `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>` で取り出すと確実（ファイル名は UUID なので、`manifest.json` の `suggestedHumanReadableName` で名前を付け直す）。
  スピン中は「スピン」を押して約 1.2 秒後に撮ると回っている途中が写る（2026-10-31）

## スピン中の暗転（ページの幕）

- （ナビゲーションバーが無い画面の方式。このリポジトリは今は次の項目の `NavigationStack` の外に重ねる方式）ページの一部だけを明るく残す幕は、領域ごとに `overlay` せず、`ScrollView` の中身（`VStack`）に `overlayPreferenceValue` で 1 枚だけ重ね、残す View の枠を `anchorPreference(.bounds)` で伝えて抜く。
  中身と同じ座標なのでスクロールしても穴が付いていき、中身より四方へ大きく塗れば `ScrollView` の切り抜きで上の安全領域・中身の下の余白まで覆える（overlay はレイアウトに響かない）。
  抜くのは四角 1 枚を穴の中心からの `RadialGradient`（中心は幕の範囲に対する割合の `UnitPoint`）で塗るだけにし、巨大な幕に `mask` / `compositingGroup` を掛けない（オフスクリーンの合成が幕の大きさになるおそれ）。
  even-odd の `Path`（外）とグラデーションの円（縁）の 2 枚に分けると、同じ半径で両方の端がアンチエイリアスされて継ぎ目に細い明るい輪が出るおそれがある（グラデーションは最後の色が外へ延びるので 1 枚で済む）（2026-10-31）
- ナビゲーションバーに題名・設定ボタンを載せた後は、`ScrollView` の中身に重ねた幕はバーに掛からない（iOS 26 はバーの下の本文は暗くなるが、題名と Liquid Glass のボタンは明るく残る）。
  幕を `NavigationStack` の外に `overlay`（`ignoresSafeArea`）で 1 枚だけ重ね、盤面の枠は `onGeometryChange` の `.global` で測って幕の原点を引けば、スクロールしても穴が付いていき、
  タブバー（`TabView` が上に描く）は暗くならない。
  枠は幕だけが読む `@Observable` に書くと、スクロールのたびに描き直すのは幕だけで済む（2026-10-31）
- iOS 26 のタブバー（浮いたガラス）は `ScrollView` の上に描かれるので、中身の幕はタブバーを暗くしない（`TabView` に手を入れずに Q6 の「タブバーは暗くしない」が満たせる）（2026-10-31）
