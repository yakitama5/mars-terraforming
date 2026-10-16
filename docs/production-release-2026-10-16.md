# 2026-10-16 本番反映の記録

ユーザーが表情と瞬きの動画を確認後、このチャットで「おｋ、本番反映しておいて」と今回分を明示承認した。以前の公開承認待ちは解消し、既存の公開リポジトリとGitHub Pagesへ反映した。

## 反映した内容

青基調のUI、土地・隣接効果の内訳、3幕の導入と都市・ロケットの命名、任意研究6本、ドーム・地下都市それぞれの居住編ED、採用済みのミナの通常絵・喜怒哀楽・瞬き・短いうなずき。生成画像はアプリに同梱する。実動作動画はリポジトリの記録用で、ゲームの配信資源には含めない。

- [PR #22](https://github.com/yakitama5/mars-terraforming/pull/22): 作業ブランチ→develop。対象 `392b4ec8ef4910a848c32956adc9b18cd5d7fd12`、統合後 `4e4c19b86ad8db619f4be31f6ed8d64f349a4d87`。
- [PR #23](https://github.com/yakitama5/mars-terraforming/pull/23): develop→main。統合後 `0a565d3b6a569d19ea94c172093ae8bfe5754271`。
- [最終配信run 38839512502](https://github.com/yakitama5/mars-terraforming/actions/runs/38839512502): main/develop両方の解析・テスト・Webビルドと、実際の `Deploy both channels together` が成功。2026-10-16 11:21 JST完了。
- 公開 `deployment.json` のmain/develop/runが上記と一致することを、配信後と画像検証前後に確認した。

[通常版](https://yakitama5.github.io/mars-terraforming/) / [開発版](https://yakitama5.github.io/mars-terraforming/develop/)。ゲームのソースと採用画像は両版で同一、時間送りと保存・ロック・キャッシュの名前空間は従来どおり分ける。

## 実施した検証

- 最新一式の `mise exec -- bash tools/check.sh` が成功。依存方向、整形、静的解析、387テスト。PRとmain統合後のGitHub Actionsも成功。
- 公開developで `opening_smoke.cjs` が自然終了0。OP読書中の時計停止、3件の命名・改名、研究一覧、小画面、オフライン再開時の名前・世界の保持。
- 公開developで `web_smoke.cjs` が自然終了0。研究・製造・輸送・火星居住、地区建設、人員・提携、予約順と支払済み工程、比較・見通し、別タブ保護、報酬保持、オフライン再開。ゲーム取得資源は公開元originのみ。
- 最終配信の両URLで `pages_smoke.cjs` が自然終了0。通常版の時間送り非表示、開発版だけの加速、別世界・保存・ロック・キャッシュの分離、両版の同時オフライン再起動、配置・手引き・通知・人員配分。
- main/developの通常＋喜怒哀楽＋瞬きの計12画像をHTTP取得し、ローカルの採用画像とSHA-256/サイズが全一致。mainのService Workerキャッシュ内の6画像も一致。オフライン再起動後、6画像をService Worker由来の応答からデコードし、1254×1254・SHA一致を再確認。ブラウザ例外なし。
- 公開mainのオンライン/オフラインOPを844×390で目視確認。全て専用ブラウザを使い、ユーザーの通常セーブには触れていない。
- 公開前のdistrict-5から同じ専用Chromeプロファイルを継続し、district-6への移行を確認。同じ世界・研究者7人/工業員5人・地区を維持し、予約済み生命維持研究は不在中に1回完了。研究成果と完了通知が各1件で、再起動・オフラインでも増えない。全visitでOPが表示されないことをassertした。
- 旧キャッシュ `e17d3ada5549d3f7`（48件）から `b8a1faa2796e89cc`（57件）へ更新し、旧キャッシュが退役。オフラインの新規起動でも新しい世界形式と画像6枚のデコードを確認した。

実画面: [公開mainのOP](screenshots/blue-main-release-opening.png)、[旧世界の移行後・オフライン](screenshots/blue-main-upgraded-offline.png)。

### 既存キャッシュから切り替わるタイミング

新workerは開いているゲームタブを強制的に切り替えない。最初の検証3visitは新workerのインストールを待たずブラウザを閉じてしまい、旧版のままだった。成功とは扱わず、検証側の待ち条件を修正した。

10秒ほどページを保持した診断visitでは約7.3秒で `waiting=installed` と新キャッシュ57件を確認。次回の通常起動でdistrict-6へ移行し、さらに別起動のオフラインでも新しい版を維持した。キャッシュやセーブの削除、skipWaitingの強制、アプリ側の変更は行っていない。古い表示が残る場合は、オンラインで更新取得を待ってからゲームのタブを閉じ、開き直す。必要時間は通信環境によって変わる。

## 範囲と制約

今回の配信ではゲーム本体の追加修正はないため、iOS Simulatorは直前の導入・居住編ED・保存再開とミナの表情・動作・録画検証を参照し、再実行していない。iOS実機・Androidの性能/電池/長時間負荷、Safari/Firefox、4〜6週間のバランスは未検証。

全球屋外居住の判定、火星復元、研究継承周回、収益化の未決定ルールは変更していない。
