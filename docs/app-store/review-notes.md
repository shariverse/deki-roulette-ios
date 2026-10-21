# 審査用メモ（下書き）

App Store Connect の「App Review に関する情報」→「メモ」に貼る。デモ用のアカウントは不要（ログインが無い）。

```
デキレーレットは、複数の候補から 1 つを選ぶ「ルーレット」と、項目をランダムに並べ替える「順番決め」の 2 画面のアプリです。

・アカウントの登録・ログインはありません（デモ用アカウントは不要です）。
・インターネットを通じた通信は行いません。入力した項目はすべて端末の中だけに保存します。
・課金・広告・通知はありません。クリップボードの読み取り・書き込みはしません（共有シートで「コピー」を選んだときは、システムが書き込みます）。
・写真への追加の許可は、共有シートで「画像を保存」を選んだときだけ求めます（写真の読み取りの許可は求めません）。

【確認の手順】
1. 起動すると「ルーレット」画面が出ます。「ラーメン」「カレー」「寿司」「焼肉」などの初期項目があり、「スピン」を押すと盤面が回って結果が出ます。盤面のフリックでも回せます。結果の下の「結果を共有」と X・LINE のボタンが使えます。共有シートには結果の画像が付きます。X・LINE のボタンは、結果の文面を入れた投稿画面（各アプリ、または Web）を開きます（アプリから投稿・通信はせず、URL を開くだけです）。
2. 画面の「順番決め」タブで「並べ替え」を押すと、1 位から 1 件ずつ順番が表示されます。
3. 項目は入力欄から追加・編集・削除できます（2〜24 個）。項目ごとに色や絵文字を付けられます。よく使うリストは名前を付けて保存できます。
4. ヘッダ右上の歯車から設定（効果音・触覚フィードバック・ルーレットの詳細設定・アプリアイコン・項目の初期化・著作権・ライセンス）を開けます。
5. 画面キャプチャの確認: 画面収録やミラーリングでキャプチャしている間の表示は通常と同じです（後述の印だけが出なくなります）。

【補足】
各画面の下部の「使い方」の中に「結果を決めておきたいとき」の説明があります。項目を 0.6 秒ほど長押しすると、その項目が次のスピンで選ばれます（順番決めは先頭・末尾）。人に画面を見せる場面を想定した機能で、指定した印は項目に触れている間と指定した直後だけ現れ、スピン中・結果表示中・画面の共有や収録中は出ません。設定は起動のたびにまっさらになります（前回の指定は残りません）。

iPhone・iPad・Apple Vision Pro に対応しています。
```

### 英語版

審査員向けの英語のメモ。スクリプト（`upload-app-store-metadata.rb`）はこのファイルの**最初の**コードブロックを読むので、今は上の日本語版が登録される。英語版を登録するなら、この英語版を上に移す。

```
DekiRoulette has two screens: a roulette that picks one item out of several, and a random order screen that shuffles items into a random order.

- There is no account registration or sign-in (no demo account is needed).
- The app does not communicate over the internet. All items you enter are stored only on the device.
- There are no in-app purchases, ads or notifications. The app does not read or write the clipboard (if you choose Copy in the share sheet, the system writes to it).
- The app asks for permission to add photos only when you choose Save Image in the share sheet. It never asks to read your photos.

[How to review]
1. On launch, the roulette screen appears with default items such as Ramen, Curry, Sushi and Yakiniku. Press "Spin" and the wheel turns and lands on a result. You can also flick the wheel to spin it. "Share result" and the X and LINE buttons appear below the result. The share sheet includes an image of the result. The X and LINE buttons open a post with the result text filled in, in the app or on the web (the app itself does not post or communicate; it only opens the URL).
2. On the "Random order" tab, press "Shuffle" and the order appears one place at a time.
3. Add, edit and delete items (2 to 24). Each item can have a color or an emoji, and you can save lists with a name.
4. Open Settings from the gear button at the top right (sound, haptics, roulette details, app icon, reset items, copyright, licenses).
5. Screen capture check: while the screen is being recorded or mirrored, everything looks the same except that the marks described below are hidden.

[Note]
The "How to use" section at the bottom of each screen explains "When the result is already decided": press and hold an item for about 0.6 seconds and that item will be the one the next spin lands on (for the order screen, the first or last place). It is designed for showing the screen to others: the mark only appears while you are touching an item and right after you set it, and it disappears while spinning, while the result is up, and while the screen is being shared or recorded. Marks reset on every launch.

The app supports iPhone, iPad and Apple Vision Pro.
```

## 審査で聞かれそうなこと

- **ユーザーが作る内容**: 項目は端末の中だけで、ほかの利用者に見せる機能は無い（共有は本人が押したときだけ。通報・ブロックの仕組みは不要）
- **ギャンブル**: 実際のお金を賭ける機能は無い（賭け事・賞金には使えない）
- **商標・人物**: アプリの中に実在のアーティスト名や画像は入れていない。初期項目（ラーメン・カレーなど）も一般的な語だけ。X・LINE のロゴは各社の配布素材を比率・色を変えずに縮めて使い、設定の「著作権」に商標の注記を置いている
- **クリップボード**: アプリからは読み書きしない（共有シートの「コピー」はシステムが書き込む）
- **写真**: 共有シートの「画像を保存」のときだけ追加の許可を求める（`NSPhotoLibraryAddUsageDescription`）。読み取りの許可は求めない
