# main / develop と GitHub Pages の運用

更新: 2026-10-13。ユーザーがPublic化し、main/developの作成・初回push・両方の配信を承認済み。
**main/developの作成・初回配信・実URLでのChrome検証に加え、両ブランチのpush自動配信も確認済み。** 既存の非公開Sites試遊は別の配信先として残す。

iOS先行・Android後発は維持し、PagesはPCなどから試作を触るために使う。
GitHub FreeではPublicリポジトリでPagesを利用できる。有料プランではPrivateリポジトリも
対象になり得るため、Pagesのために常にPublic化が必須というわけではない。
[GitHub公式: Pagesの公開元](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)

## ブランチ運用

| ブランチ | 役割 | 公開URL | 時間送り |
| --- | --- | --- | --- |
| main | 確認済みの試作 | https://yakitama5.github.io/mars-terraforming/ | なし |
| develop | 次の変更の試遊 | https://yakitama5.github.io/mars-terraforming/develop/ | 開発 +5分 |
| codex/内容 | 個別の実装 | 自動配信なし | ローカル設定による |

普段はdevelopから作業ブランチを作り、PRでdevelopへまとめて試遊し、確認後に
`develop → main` のPRで通常版へ反映する。mainを直接修正する緊急対応では、
修正をdevelopへも戻して次の反映で失わないようにする。
最初は同じコミット履歴からmainとdevelopを用意する。
main/developとも「完成品」を意味せず、同じ短時間試作の配信経路を分ける。

## ひとつのサイトにふたつのビルドを同梱する

`.github/workflows/pages.yaml` はmain/developのpush、または両ブランチ上での手動実行を入口にする。
両方のブランチの先頭SHAを取得して固定し、それぞれのcheckoutで依存解決、ハーネス、Webビルドを
実行する。mainをサイト直下、developを `develop/` にまとめ、1個のPages artifactを配信する。
片方だけをdeployしてもう片方の配信内容を消してしまうことを避ける。
[GitHub公式: カスタムワークフロー](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)

両方のチェックとビルドが成功したときだけ配信する。例えばdevelopのチェックが失敗した場合、
mainも含め配信中のサイトを更新しない。安定版の更新を開発版から独立させる必要が出たら、
前回成功成果物の保持や配信先の分離を検討する。最初はこの一括更新を採用する。

ワークフロー全体を共通concurrency groupで直列化する。実行中の配信は途中キャンセルせず、
待機後に最新の両ブランチを取得する。配信直前にもSHAを照合し、ビルド中に更新があった場合は
古い成果物の配信をスキップして待機中の実行に任せる。GitHubの待機実行は通常1つで、新しい
待機実行に置き換わる場合がある。全コミットを個別に配信する運用ではない。
[GitHub公式: concurrency](https://docs.github.com/en/actions/concepts/workflows-and-actions/concurrency)

`deployment.json` に両ブランチのSHAとActions run IDを含め、どの組合せを配信したか確認できる。
Pages設定やbranchが不足するとワークフローは失敗し、代わりのブランチや初期状態で配信しない。

## ビルド設定と保存・キャッシュの分離

Flutterは3.47.7、依存は `pubspec.lock` を `--enforce-lockfile` で再現する。
変更時は既存のcheckワークフローとPagesワークフローのSDK指定をそろえる。
`tools/build_web_preview.sh` は次の設定を受け取り、各checkoutの `site-preview/dist` へ出力する。

| 変数 | main | develop |
| --- | --- | --- |
| MARS_DEV_TOOLS | false | true |
| MARS_WEB_BASE_HREF | /mars-terraforming/ | /mars-terraforming/develop/ |
| MARS_WEB_SAVE_NAMESPACE | mars-terraforming-main | mars-terraforming-develop |

通常版と開発版はlocalStorageとWeb Locksの名前空間を分け、同じブラウザで同時に開いても
別世界として扱う。Service Workerのキャッシュも配信パスごとに分け、一方の更新で
もう一方のオフライン資材を削除しない。Pagesへ移るとSitesとはoriginが変わるため、
既存Sitesのセーブは自動移行されない。iOSとの同期も未実装。

ブラウザへの最初の取得とキャッシュ完了には通信が必要。その後はキャッシュした版を
オフラインで遊べる。更新済みの版が既存タブに直ちに切り替わるとは限らず、同じ配信先の
タブを閉じて開き直すと待機中のService Workerが有効になる。
リポジトリ名変更・カスタムドメイン導入時はbase hrefとURL、保存名前空間の扱いを見直す。

ローカルでそれぞれビルドする例:

```sh
MARS_DEV_TOOLS=false \
MARS_WEB_BASE_HREF=/mars-terraforming/ \
MARS_WEB_SAVE_NAMESPACE=mars-terraforming-main \
mise exec -- bash tools/build_web_preview.sh

MARS_DEV_TOOLS=true \
MARS_WEB_BASE_HREF=/mars-terraforming/develop/ \
MARS_WEB_SAVE_NAMESPACE=mars-terraforming-develop \
mise exec -- bash tools/build_web_preview.sh
```

同じcheckoutで順に実行すると、最後のビルドが `site-preview/dist` に残る。
両方を確認する場合はそれぞれの成果物を退避し、上のURLと同じパス配置で静的配信する。

## 初回設定の再現手順（実施済み）

1. 公開する初回ファイル一式と、Public化をユーザーが確認する。既存の未コミット内容を保全する。
2. 初回コミットからmainとdevelopを用意してGitHubへpushする。
3. Settings → Pages → Build and deployment → Sourceを **GitHub Actions** にする。
4. Settings → Environments → github-pagesで配信可能なブランチに **mainとdevelopの両方** を指定する。
   既定ブランチだけを許可した設定ではdevelopからの更新が拒否される。
5. 「GitHub Pages (main + develop)」をmainから手動実行する。最初のpush時にPages設定が
   間に合わず失敗していても、設定完了後に実行し直せる。
6. 公開URLの両方を開き、通常版の時間送り非表示、開発版の時間送り表示、別々の保存、
   再読み込み、オフライン再開を確認する。`deployment.json` のSHAを確認する。

Pages artifactのdeployには `pages: write` と `id-token: write` が必要。ワークフローではdeploy
ジョブにだけ付与し、checkoutには保存用資格情報を残さない。branch作成、push、Public化を
ワークフロー自身が行うことはない。PRからの実行は既存のcheckワークフローのみ。
[GitHub公式: 配信ブランチ制限](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)

## 検証の状態

通常版・開発版のWebビルドと、同一originの2URLでのChrome検証が成功。
84件の既存テスト、YAML/埋込スクリプト構文、配信条件のfixture検証も成功。
詳細は `development.md` に記録。

2つの成果物をローカル配信してから、次の検証を再実行できる。

```sh
PLAYWRIGHT_MODULE='/path/to/node_modules/playwright' \
CHROME_BIN='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
MARS_PAGES_TEST_URL='http://127.0.0.1:8766/mars-terraforming/' \
node tools/pages_smoke.cjs
```

[初回配信Actions](https://github.com/yakitama5/mars-terraforming/actions/runs/38349251445) が成功。
初回の両ビルドは `52781db8e9d7fe21f8ef55dd136061e1fec0ca20`。
PagesはActions方式、既定ブランチはmain、github-pages環境はmain/developのみ許可する。
ソースと配信ページは誰でも閲覧できる。最新の配信SHAとrun IDは
[deployment.json](https://yakitama5.github.io/mars-terraforming/deployment.json) で確認できる。

実URLで `pages_smoke.cjs` が成功（終了コード0）。別セーブ、時間送りの分離、
キャッシュ共存、両方のオフライン再読み込みを確認した。
developでは `web_smoke.cjs` も成功（終了コード0）。3D表示、設備予約の順序変更、
研究・製造・輸送・居住、2タブ目の保護、報酬保持、オフライン再開を確認した。
検証用ブラウザの終了待ちを修正し、再実行でも全項目成功。

公開develop版の操作検証例（スクリーンショットは任意の一時ディレクトリへ出力）:

```sh
PLAYWRIGHT_MODULE='/path/to/node_modules/playwright' \
CHROME_BIN='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
MARS_BASE_URL='https://yakitama5.github.io/mars-terraforming/develop/' \
MARS_SAVE_KEY='mars_terraforming.save.mars-terraforming-develop_development' \
MARS_SCREENSHOT_DIR='/tmp/mars-pages-screenshots' \
node tools/web_smoke.cjs
```

Safari/Firefox・実機iOS/AndroidでのPages試遊、キャッシュ済みの旧版からの更新切替は未検証。
iOS Simulatorでの直前の操作検証は成功しており、今回の配信設定では再実行していない。

## 配信の再実行とpush起動の確認

初回の2回のmain/develop同時pushでは、PushEventが届いてもActions runが作成されず、
手動で配信した。その後、リポジトリのActions再有効化でpush自動起動が復旧した。
切り分けと実pushの検証記録は次節を参照。通常はpushで更新され、手動起動は再配信に使う。

配信を再実行する場合はActions画面の「Run workflow」、または次のコマンドを使う。
どちらのブランチから起動しても、main/develop両方の最新SHAを検証して同梱する。

```sh
gh workflow run pages.yaml --repo yakitama5/mars-terraforming --ref develop
gh run list --repo yakitama5/mars-terraforming --workflow pages.yaml
```

mainから起動する場合は `--ref main` にする。配信後は `deployment.json` と
両ブランチのSHAを比較し、以前の配信を新しい配信と取り違えない。

## push自動起動の追加調査（2026-10-13）

main/develop両方のPushEventが記録される一方、Actionsには手動実行しか登録されなかった。
通常のActions有効設定に加え、実行ポリシーは0件、ワークフローはactive、
ブランチの条件・リモートのファイル内容・コミットのskip指示なしを確認した。
実際のGit credentialはGitHub CLIと同じOAuthユーザートークンで、GITHUB_TOKENではない。
秘密値の出力や保存、認証範囲の拡大は行っていない。

両ワークフローの無効化→再有効化後、YAMLを変更せずdevelopへ `a37cb91` をpushしたが、
push起点のrunは作成されなかった。続いてリポジトリのActionsを無効化→有効化し、
元の許可設定（enabled=true / allowed_actions=all / sha_pinning_required=false）へ戻した。
続くdevelopへの `c8ed72c` のpushで、PagesとPrototype checksの両方が自動起動・成功した。
ワークフローYAML、認証方法、ブランチ条件は変更していない。

復旧前後の差から、リポジトリ単位のActions有効状態とイベント処理の不整合が疑われる。
GitHub内部の登録状態は直接観測できないため、内部原因やPublic化との因果関係は断定しない。
ワークフロー単位の再有効化では改善せず、リポジトリ単位の再有効化後に復旧した事実を残す。

同じ症状が再発した場合は、まずPushEvent・実行条件・skip指示・Actions設定・pushの認証方式を
確認する。リポジトリ全体の再有効化は、実行中のrunがないことと元の許可設定を確認してから
Settings → Actions → Generalで実施し、元の設定へ戻す。恒常的なワークフロー処理には組み込まない。

### 両ブランチの実pushによる確認

手動dispatchを使わず、developへpushして配信完了を確認した後、mainをfast-forwardしてpushした。
どちらも `event=push`、`head_sha=c8ed72cb749776384a90853e2f567c4b06c22620` を確認。
ビルド成功だけでなく、`Deploy both channels together` の実行成功と公開JSONの一致を確認した。

| pushしたブランチ | Pages run | 配信時のmain / develop | 公開JSONのrun |
| --- | --- | --- | --- |
| develop | [38360523899](https://github.com/yakitama5/mars-terraforming/actions/runs/38360523899) 成功 | `d69f5f5` / `c8ed72c` | `38360523899` |
| main | [38361236614](https://github.com/yakitama5/mars-terraforming/actions/runs/38361236614) 成功 | `c8ed72c` / `c8ed72c` | `38361236614` |

両runでmain/develop各ビルドの依存チェック・整形・静的解析・84テスト・Web releaseビルドが成功。
これは復旧を確認した時点の記録であり、後続コミットの最新配信は `deployment.json` で確認する。

公開URLに対するChromeの `pages_smoke.cjs` も再実行し、保存・ロック・キャッシュの分離、
mainの時間送り非表示、developだけの加速、両方のオフライン再読み込み・操作が全項目PASS。
この時点ではPASS後にNodeの終了待ちが再発し、検証用Nodeを手動終了した。
後続の修正でUpdaterへのstdio継承が原因と分かり、検証用Chromeに起動抑止引数を追加した。
両スクリプトはclose後に最終PASSを報告するよう変更し、Pagesを連続2回、開発循環を1回実行して
すべて自然終了0を確認。通信・初期化失敗の3ケースも自然終了1を確認した。
[原因・修正・検証の詳細](web-preview.md#検証プロセスの終了待ちの修正2026-10-13) を参照。
ゲームコードと配信YAMLは変更していない。
iOS・Safari・Firefoxでの再検証は、今回のActions設定修正では実施していない。

## 初回pushのコミット分割

元の企画書・雛形を保全し、既存の実装一式を次の9単位で記録した。
main/developはこの同じ履歴から開始する。配信後の検証記録は後続の文書コミットに分ける。

| コミット | 内容 |
| --- | --- |
| [a65a1ec](https://github.com/yakitama5/mars-terraforming/commit/a65a1ec) | 🎉new: Flutter基盤と固定依存・日本語フォントを追加 |
| [0ef0654](https://github.com/yakitama5/mars-terraforming/commit/0ef0654) | 📚doc: 元企画書と開発時の基本方針を記録 |
| [ca82fd4](https://github.com/yakitama5/mars-terraforming/commit/ca82fd4) | ✨feat: 財政と共有設備をつなぐ開発計画の進行を実装 |
| [51c4302](https://github.com/yakitama5/mars-terraforming/commit/51c4302) | ✨feat: 自動保存と再開・保存破損や多重操作への保護を追加 |
| [f55b41f](https://github.com/yakitama5/mars-terraforming/commit/f55b41f) | ✨feat: 3D拠点と設備予約の一覧・順序変更を実装 |
| [9efe850](https://github.com/yakitama5/mars-terraforming/commit/9efe850) | ✨feat: オフラインで試遊できるWeb版とブラウザ検証を追加 |
| [b596f56](https://github.com/yakitama5/mars-terraforming/commit/b596f56) | 🔧chore: 責務分離と品質チェックをCIで検証 |
| [e734004](https://github.com/yakitama5/mars-terraforming/commit/e734004) | ✨feat: mainとdevelopを別URLへGitHub Pages配信 |
| [52781db](https://github.com/yakitama5/mars-terraforming/commit/52781db) | 📚doc: 試作の操作・検証結果・仮仕様を引き継ぎに記録 |
