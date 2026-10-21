# App Store 公開用の文面（下書き）

デキレーレット iOS / visionOS 版を App Store で公開するときに使う文面と、スクリーンショットの設定です。
Web 版の公開コピー（<https://roulette.basekeita.com/>）・アプリの「使い方」・[SPEC](../SPEC.md) から書きました。**公開・登録の前に、人間が中身を確かめてください。**

| ファイル | 中身 | 使う場所 |
| --- | --- | --- |
| [metadata/](metadata/) | 言語ごと（ja・en）のアプリ名・サブタイトル・プロモーションテキスト・説明文・キーワード | App Store Connect の「App 情報」「App Store」タブ（言語ごと） |
| [listing.md](listing.md) | 掲載文のファイルの一覧と書き方・カテゴリ・年齢制限・スクリーンショット・URL | App Store Connect の「App 情報」「App Store」タブ |
| [review-notes.md](review-notes.md) | 審査用メモ（審査員への説明。日本語版と英語版） | App Store Connect の「App Review に関する情報」のメモ |
| [languages.json](languages.json) | 掲載する言語と、撮影・登録に使うロケールの対応 | スクリーンショットの撮影と掲載文の登録（ワークフロー） |
| [screenshots.json](screenshots.json) | 撮る表示サイズ（iPhone・iPad・Apple Vision Pro）と機種 | スクリーンショットの撮影と登録（ワークフロー） |

## 決まっていないこと（人間が決める）

- **プライバシーポリシー URL とサポート URL**（[listing.md](listing.md) に候補）。サイトのプライバシーポリシーは Web 版（Cloudflare のアクセス解析あり）向けの文面なので、iOS 版向けの追記か別ページが要るかもしれない
- App Store Connect の主要言語（[languages.json](languages.json) の先頭。今は ja。登録のときに確かめる）
- カテゴリと年齢制限の回答（[listing.md](listing.md) に案）
- 価格と配信国

## 書くときに守ったこと

- 画面本文と同じく、隠し操作（ステルス）の内容を示唆する語（「当たり」「必ず」など）を掲載文に置かない（[SPEC](../SPEC.md) §6.5）
- アプリにない機能（通知・ウィジェット・課金・アカウント）を書かない
- データは端末の中だけ・通信しない、という実装と食い違うことを書かない。端末のバックアップ（iCloud・パソコン）には含まれることは、設定画面の説明と同じく書く
