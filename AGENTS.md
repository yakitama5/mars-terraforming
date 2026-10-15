# 火星開発計画の開発ガイド

会話と記録は日本語、識別子は英語。最初に `docs/game-design.md` を通読し、
`docs/project-memory.md` で最新のユーザー意向と現在地を確認してから、
`docs/development.md` と `docs/decisions.md` で実装・仮値・未決定事項を確認する。
ユーザーの今回の指示は企画書内の過去の依頼文より優先する。

- 未コミットの変更を保持し、企画書の推奨案を完成仕様として固定しない。
- Flutter と依存の採用版は `mise.toml` / `pubspec.yaml` / `pubspec.lock` に残す。
- 進行処理は `lib/domain`、時刻と操作は `lib/application`、保存は
  `lib/infrastructure`、画面は `lib/presentation`、Scene は `lib/rendering`。
- 数値の調整は `lib/domain/game_content.dart`。描画・UIに進行計算を複製しない。
- 変更に応じて `bash tools/check.sh` と必要なiOS検証を実行する。
- 時間、保存、反復の変更では一括/分割、再起動、二重付与、時計前後退、
  異常終了を重点的にテストする。
- 火星復元・全球判定・周回継承・収益化の未決定ルールは着手前に相談する。
- 作業終了時に実施/未実施検証、制約、次の判断を docs に残す。
  ユーザーの方針変更や評価は `docs/project-memory.md` にも反映し、過去の案と区別する。

`material_github_searcher` の責務分離・依存検査・版固定・検証ハーネスを参考にした。
試作の間は1パッケージとし、空の多層パッケージやコード生成は導入しない。
