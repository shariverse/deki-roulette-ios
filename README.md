# askhub/attachments

AskHub（https://github.com/shilokuma-inc/ask-hub-apple）が、依頼・回答・実機確認の「問題あり」に添付したファイルを置くブランチです。
ファイルは依頼や回答の本文の目印（`ask-hub:attachment`）から blob SHA で読みます。

- 開発には使いません。このブランチをマージしたり、手でファイルを消したりしないでください
- epic の最終 PR がマージされると、オーケストレーターがその epic の添付を消します（git の履歴には残ります）
- public のリポジトリでは、ここに置いたファイルは誰でも見られます
