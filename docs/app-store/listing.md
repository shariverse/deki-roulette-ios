# App Store の掲載情報（下書き）

## 掲載文（言語ごと）

アプリ名・サブタイトル・プロモーションテキスト・説明文・キーワードは、言語ごとに [metadata/](metadata/) の `<language>.md` に書く。

| ファイル | 言語 |
| --- | --- |
| [ja.md](metadata/ja.md) | 日本語 |
| [en.md](metadata/en.md) | 英語 |

どのファイルも「## アプリ名」「## サブタイトル」「## プロモーションテキスト」「## 説明文」「## キーワード」の見出しの下に、文面のコードブロックを 1 つ置く（見出しはスクリプトが探すので、どの言語でも日本語のまま）。
文字数の上限は App Store Connect の制限（アプリ名 30 文字、サブタイトル 30 文字、プロモーションテキスト 170 文字、キーワード 100 文字、説明文 4,000 文字）。
キーワードはカンマ区切りで空白を入れず、アプリ名とサブタイトルに入っている語は外す（入れなくても検索の対象になる）。

## カテゴリ（案）

- プライマリ: ライフスタイル
- セカンダリ: 仕事効率化（ほかの候補: エンターテインメント。人間が決める）

## 年齢制限の回答（案）

すべての項目に「なし」と答える見込み（暴力・性的な内容・ギャンブル・ユーザーが作る内容の共有・Web の閲覧などは無い。お金を賭ける機能も、ほかの人に入力が見える機能も無い）。

## URL（案）

| 項目 | 候補 | メモ |
| --- | --- | --- |
| サポート URL | <https://roulette.basekeita.com/guide/> | Web 版の使い方ガイド。不具合の報告先は GitHub Issues（<https://github.com/KeitaOsaki/deki-roulette/issues>） |
| プライバシーポリシー URL | <https://roulette.basekeita.com/privacy/> | Web 版向けの文面（Cloudflare のアクセス解析など）。iOS 版は通信しないので、iOS 版向けの追記か別ページが要るかもしれない |

## スクリーンショット

`scripts/app-store-screenshots.sh` で撮る（UI テストを流して、ルーレット・結果・順番決め・並べ替え結果の 4 枚）。表示サイズは [screenshots.json](screenshots.json)（6.9 / 6.5 インチの iPhone、13 インチの iPad、Apple Vision Pro）。

掲載文（[metadata/](metadata/) の各ファイルの、見出しの下のコードブロック）とスクリーンショットは、ワークフロー「App Store Metadata」で App Store Connect に登録する（README の「App Store の掲載文とスクリーンショット」）。
