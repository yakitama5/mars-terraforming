# 開発・検証の引き継ぎ

更新: 2026-10-14。最新は地形上の都市開発と指令画面。進行データはcontent district-5を維持。
最新の変更と検証は [地形と指令UI](terrain-command-ui.md) を参照。
序盤の数値・機関運営は [並行開発と機関運営](agency-development.md) を参照。
前段の変更と検証は [序盤の投資と予約の見通し](early-development.md)、
20時間の方針・投資の基礎数値は [都市投資と序盤のペース](investment-pacing.md)、
球体・六角区画・研究ツリーの初期改善は [戦略試作の記録](strategy-prototype.md) を参照。
企画書は原本を保持。仮仕様は `decisions.md` に分けた。

## 作業環境と採用版

ローカル実体は `mars_terraforming`（アンダースコア）。Gitのoriginは
`https://github.com/yakitama5/mars-terraforming.git`。依頼時のハイフン名ディレクトリは存在しなかった。
初期状態はコミットなしで、Flutter雛形・企画書が未追跡。既存のネイティブ雛形・署名設定を保持。
Bundle IDは既存の `com.example.marsTerraforming` で製品用には未確定。

| 対象 | 採用版・記録 |
| --- | --- |
| Flutter stable | 3.47.7 / framework abaf9c523780a608bd46686fd5e53740a07077f8 |
| Dart（付属） | 3.13.5 |
| FlutterScene | 0.24.3、最低Flutter3.47.0 / Dart ^3.10.0 |
| Xcode / Simulator runtime | 26.1.1 / iOS26.1 |
| 依存の固定 | pubspec.yamlで直依存を完全固定、pubspec.lockで推移依存固定 |
| SDK管理 | mise.toml、SDK制約も完全一致 |

着手時の公式確認:
[Flutter公式配布JSON](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json)、
[SDK archive](https://docs.flutter.dev/install/archive)、
[flutter_scene公開版](https://pub.dev/packages/flutter_scene)、
[pub.dev API](https://pub.dev/api/packages/flutter_scene)。検索結果の過去の版で固定しない。
3.47.7 macOS arm64 SDKのSHA-256は
`dd9da574c3168460550117eb0e8dd0313ae934fabf64a82a6d557fff5fd1422e`。

iOS/macOSはInfo.plistで `FLTEnableFlutterGPU=true`、AndroidはmanifestのEnableFlutterGPUを設定。
iOSのInfo.plistとDart側の両方で横画面指定。iPadは試作中fullscreen。
基本形状だけなので独自アセット用hookは不要、Scene依存自身のhookがシェーダを生成する。
生成物は配布時に同梱し、起動時の通信は不要。

## 起動と遊び方

```sh
mise install
mise exec -- flutter pub get --enforce-lockfile
mise exec -- flutter devices
mise exec -- flutter run -d <iOS-device-id>
```

開発用時間送り（通常とは別の保存枠）:

```sh
mise exec -- flutter run -d <iOS-device-id> --dart-define=DEV_TOOLS=true
```

1. 「惑星マップ」で地球・火星と都市を選ぶ。球体を回転・拡大できる。
2. 「都市開発」で区画を選び「比較に保存」。別の区画/都市で「候補を比較」すると増強と展開の費用・工期・隣接効果を比べられる。
3. 「研究ツリー」の全体表示で3分野のつながりを見て研究を予約する。研究だけでなく実証条件も必要。
4. 「設備・進行 → 製造・受注／輸送・居住」で受注・製造・輸送を予約する。
5. 「稼働状況」で次の予約を↑↓変更。「予約の見通し」で30分/1時間/8時間後を試算し、必要なら順序を組み替える。支払済みの現在の1回は継続する。
6. 初輸送後に居住方式を選び、火星の都市区画へ居住地区を建設すると24人が入居する。
7. 地区や研究の完成で次の都市・製造・輸送を解放し、現地実証を進める。
8. 通常は端末時刻で進む。開発用は「+5分」と時間送りメニューの「+1時間／+1日」で確認できる。
9. 再起動時も同じ世界で予約の続きを進める。旧形式の市街・住民・成果・予約は保持する。

予約は設備ごとに並び、↑↓で次の着手順を変更できる。費用を確保済みの現在の1回は、
順序変更後も残り時間から続く。例えば工場の無期限受注中に居住キット製造を予約し、
キットの↑を押すと、現在の受注1回→キット製造→受注の再開となる。
反復をすべて取り消す必要はない。「次の予約」の停止アイコンは、未着手なら予約取消、
実行中なら現在の1回を最後に反復終了する。返金は行わない。
先頭が前提・資材・資金・分岐待ちなら後続も待つので、別の予約を前へ移動して配分を変えられる。
設備休止中も次の順番を編集でき、再開後は支払済みの現在の1回から続ける。

設備一覧は画面幅いっぱいに開き、広いPC画面は2列、iPhone横画面相当は1列で表示する。
各カードには稼働/休止と維持費、現在の進捗・残り時間、予約の種別・反復数・停止理由がある。
「惑星マップ」で球体へ戻る。「開発記録」は設備画面のサブタブで確認できる。

## 構造とハーネス

参考リポジトリ `material_github_searcher` の依存方向、版固定、チェック、
ドキュメントによる引き継ぎを採用。過剰なpackage分割を避け1package内で分離した。

| 場所 | 責務 |
| --- | --- |
| lib/domain | 純Dartの数値定義・状態・時間進行・保存インターフェース |
| lib/application | 時刻取得・操作・自動保存。小さいChangeNotifierで画面へ通知 |
| lib/infrastructure | ネイティブの2世代ファイル保存 / Webの2世代localStorage・Web Locks |
| lib/presentation | 日本語Flutter UI。計算結果を表示し、操作をcontrollerへ渡す |
| lib/rendering | FlutterScene。数値を受け取るだけでゲームの進行・保存を行わない |
| lib/main.dart | composition root、保存先と開発枠の選択、横画面 |
| tools/check_architecture.dart | 層を逆向きに参照しないか検査 |

```sh
mise exec -- bash tools/check.sh
mise exec -- flutter build ios --simulator --debug
mise exec -- flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/prototype_test.dart -d <iOS-simulator-id>
```

driveテストは一時保存ディレクトリだけを使い、通常/開発セーブを触らない。
画面の起動・研究予約・時間送り・居住分岐の選択・保存再読み込みを検証し、
成功時は `docs/screenshots` に実際のGPU描画を含むスクリーンショットを保存する。
Flutter test/build/driveを同じcheckoutで並列実行するとnative assets生成が競合するため直列に実行する。

## 初期版からの検証履歴

以下は各段階での記録。最新のUI・区画仕様・テスト件数は戦略試作の記録を優先する。

## GitHub Pages / main・developの初回公開

ユーザーの追加相談に合わせ、`.github/workflows/pages.yaml` と
[運用・公開手順](github-pages.md) を追加。当初GitHub側はPRIVATE・空だったが、ユーザーがPublic化し、
初回コミット、main/developの作成・push、両方のPages配信を承認。公開リポジトリを確認済み。
初回一式を9つの意味あるコミットに分け、両ブランチを同じ履歴でpush済み。
PagesはActions方式で有効化し、github-pages環境はmainとdevelopの2ブランチを許可。
既存の非公開Sites試遊URLはそのまま残っている。

- mainの通常版を `/mars-terraforming/`、developの時間送り付き版を
  `/mars-terraforming/develop/` へ同梱するワークフローで公開した。
- ビルドごとに `MARS_WEB_BASE_HREF` と `MARS_WEB_SAVE_NAMESPACE` を指定。
  namespace未指定なら既存Sitesの保存キーを維持し、ネイティブ保存は変更しない。
- CacheStorageの削除範囲をService Workerの配信パスに限定した。
  Pagesが除外する `.last_build_id`・`.gitignore` などの隠しファイルをprecache/配布からも除外し、
  存在しないファイルでキャッシュ登録が全失敗する問題を防いだ。
- main/develop相当のWeb releaseビルドをそれぞれ成功。
  2パスを同一localhost originで配信し、Chromeで `tools/pages_smoke.cjs` 成功。
  mainの時間送り非表示、developだけの時間送り、別の世界/保存/ロック、キャッシュ共存、
  両タブのオフライン再読み込みと操作を確認。Pages成果物にsymlinkはなかった。
  最初は検証完了後のブラウザ終了待ちが残ったため、ネットワーク状態を戻してcontextを閉じる
  後片付けを追加し再実行、終了コード0を確認。前回こちらで起動したSimulatorはデータを
  消さず終了し、ローカル検証サーバーも終了した。
- `bash tools/check.sh` 成功: 依存方向・整形・静的解析OK、84テスト成功。
- ワークフローのYAML、Bash6本、埋込Pythonの構文検査成功。
  仮のGitHub APIと一時ディレクトリで、SHA固定・2ビルド同梱・配信記録、
  main/developどちらかのHEAD更新時に古いビルドを配信しない条件を確認。
- [初回Actions配信](https://github.com/yakitama5/mars-terraforming/actions/runs/38349251445) 成功。
  両ブランチの解析・テスト・releaseビルドをGitHubのLinux環境で実行し、配信まで成功。
  配信対象は `52781db8e9d7fe21f8ef55dd136061e1fec0ca20`。
  最新の配信対象は [deployment.json](https://yakitama5.github.io/mars-terraforming/deployment.json) に記録する。
- 公開された [main](https://yakitama5.github.io/mars-terraforming/) と
  [develop](https://yakitama5.github.io/mars-terraforming/develop/) でChrome実操作を実施。
  `pages_smoke.cjs` 成功: 保存/ロック/キャッシュ分離、mainに時間送りなし、developのみ加速、
  両方のオフライン再読み込みと操作。終了コード0。
- 公開developで `web_smoke.cjs` 成功: 3D表示、設備順序変更、支払済み工程継続、順序保存、
  研究→製造→輸送→居住1棟/12人、2タブ目停止、報酬保持、オフライン再開。
  検証用ブラウザの終了待ちはcontextを先に閉じる修正で解消し、再実行で終了コード0を確認。
  実URLの [設備一覧](screenshots/pages-equipment.png)・[居住完成](screenshots/pages-habitat.png) を保存。
- 初回の自動run未登録は、リポジトリのActionsを一度無効化して元の設定で再有効化すると復旧した。
  ワークフロー単位の再有効化では改善しなかった。YAML・認証方法・push条件は変更していない。
  GitHub側のリポジトリ単位の状態不整合が疑われるが、内部原因は断定しない。
- developの [push配信38360523899](https://github.com/yakitama5/mars-terraforming/actions/runs/38360523899)、
  mainの [push配信38361236614](https://github.com/yakitama5/mars-terraforming/actions/runs/38361236614) が成功。
  どちらも `event=push`・`head_sha=c8ed72c`、deploy step実行成功、公開JSONのSHA/run一致を確認。
  両ブランチの84テスト・解析・Webビルドを再実行して成功。調査と復旧手順はgithub-pages.mdへ記録した。
- 復旧後の公開URLでChromeの `pages_smoke.cjs` の全機能チェックがPASS。
  保存/ロック/キャッシュ分離、時間送りの分離、両方のオフライン再開を再確認した。
  この時点ではPASS後にNodeの終了待ちが再発し、手動終了したため完走とは扱わなかった。
- 後続調査で、Google UpdaterがChromeのstdioを継承してPlaywrightのcloseを遅らせる原因を確認。
  両検証スクリプトに `--disable-updater-scheduler` を追加し、初期化失敗時もbrowserを閉じ、
  全close後に最終PASSを出すよう修正した。Nodeの強制終了は使わない。
  公開版のPages連続2回・開発循環1回が自然終了0、通信/初期化失敗3ケースが自然終了1。
  全6ケースでChrome終了・タイムアウトなし・手動killなしを確認。終了待ちの残件は解消。
  環境・実測・再確認手順は [Web検証ガイド](web-preview.md#検証プロセスの終了待ちの修正2026-10-13) に記録した。
- GitHubは標準ActionsのNode.js 20非推奨を通知したが、Node.js 24による実行と配信は成功。
  Actionの更新とrunner環境変更時にはこのハーネスで互換性を再確認する。
- iOS再実行は行わず直前の設備操作検証を参照。Safari/Firefox・実機iOS/AndroidのWeb試遊、
  キャッシュ済み旧版からの更新切替は未検証。次は設備一覧の情報量と↑↓操作の試遊をもとに改善する。

## 今回の設備配分・Web対応の検証

- `bash tools/check.sh`: 依存方向・24ファイル整形・静的解析OK、84テスト成功。
  初回43件に、設備順序/画面11件、ブラウザ保存24件、Controller6件を追加。
- 設備単位の入替、支払済み工程継続、無期限反復の後回し、停止理由の再評価、
  並べ替え後の一括/分割進行一致、保存/再開での順序保持を確認。
- ブラウザ保存の2世代回復、保存失敗時保全、未知版保護、外部変更検出、
  初回保存失敗時の進行停止、競合後の待機中保存の破棄を確認。
- Web releaseビルド成功。Chromeの独立プロファイルで `tools/web_smoke.cjs` 成功。
  実際のFlutterScene描画、外部受注の無期限反復より居住キットを前にする操作、
  実行中の受注継続、再読込後の順序保持、研究→製造→輸送→居住1棟/12人を確認。
- 同じセーブの2タブ目は日本語説明を出し進行前に停止。再読み込み時の実績報酬保持、
  ネットワークを切った状態でのコールド再読み込み・設備画面の操作も成功。
  アプリから取得したHTTPリソースのoriginはローカル配信元だけだった。
- [Web初期拠点](screenshots/web-initial.png)、[設備一覧](screenshots/web-equipment.png)、
  [居住完成](screenshots/web-habitat.png)、[2タブ目停止](screenshots/web-second-tab.png) を保存。
- Web版のビルド・保存・検証・配置手順は [web-preview.md](web-preview.md)。
  同じWebビルドをCIに追加。GitHub上での初回実行結果は上のPages公開記録を参照。
- iPhone17 Pro / iOS26.1 の `flutter drive` 成功。実GPU、設備一覧の↑操作、現在の受注継続、
  予約順変更、一覧から3D画面への復帰、居住1棟/12人、保存再開を確認。
  [iOS設備一覧](screenshots/prototype-equipment.png) などのスクリーンショットを更新。
  初回はSimulator起動で停滞し、今回の検証プロセス・使用端末だけを終了。
  データを消さず再起動（17秒）して単独再試行すると、Xcode build 16.7秒・テスト30秒で成功。
- Sitesへ同じ配布物を非公開配置し、デプロイ `succeeded` を確認。URLと配置IDはweb-preview.md。
  ローカル検証サーバーは終了、SitesのURLをアプリ内ブラウザで開くよう要求済み。
- Safari/Firefox、実機iOS、Android、Sitesの認証を含む実操作は未検証。
  Web初回取得とキャッシュ完了には通信が必要。保存はoriginごとでiOSとは同期しない。

## 初回小循環の検証記録

- `bash tools/check.sh` 最終成功: 依存方向OK、15 Dartファイル整形差分なし、静的解析指摘なし、43テスト成功。
- 内訳: 進行19・保存20・Widget/Controller4。100通りの一括/分割一致、
  無期限受注1年分350,400完了、10年の無予約放置、時計前後退、資金不足/再建、
  資材不足、3回反復終了、分岐局所停止、保存/再開重複防止、破損/中断回復、未知版保護を確認。
- iOS Simulator向けdebugビルド成功（Flutter3.47.7 / Xcode26.1.1）。
- iPhone17 Pro / iOS26.1で実GPUを使うintegration_testが成功。
  研究予約、外部受注3回との工場共有、製造、輸送、建設の分岐待ち、
  ドーム選択、居住1棟/12人/方法別実績、保存再読み込みの重複防止を確認。
- 実際のiOSスクリーンショットを [初期拠点](screenshots/prototype-initial.png)、
  [居住施設完成](screenshots/prototype-habitat.png)、[地球拠点](screenshots/prototype-earth.png) に保存。
- 進行/保存/WidgetテストはGPUを差し替え、描画とは分離して検証する。
- 初回Scene描画時にシェーダpipeline生成約0.7秒などの停止がログに出た。
  現時点で読み込み画面からの事前描画最適化は未実装。実機性能の測定は別途必要。
- 最初のSimulator起動はホストのメモリ/ランタイム画像I/O負荷でSpringBoard初期化が停滞。
  今回起動した端末だけを通常終了し、ビルドと起動を直列にした後は24秒で起動、検証成功。
  ユーザーデータの消去・端末リセット・他アプリの終了は行っていない。
- 保存テストで不正UTF-8がI/O失敗として扱われる不具合を発見し、
  バイト読み込み→明示的decodeへ修正。正常な前世代への回復を再検証した。
- ゲーム本体も開発モードで起動。path_provider経由のiOS Application Support内に
  development.jsonと前世代が生成され、5秒ごとに保存世代が更新されることを確認。
  simctlでこのアプリだけを終了/再起動し、同じworldId・予約・取得記録を保持して
  経過時間が進むことを確認（無予約状態でのコールド起動）。シミュレータには操作可能な本体を残した。
- 実機・Android・電源断・長期の通常時間プレイ、OSでの休止復帰、GPU初期化失敗の故障注入は未実施。

## 残る範囲

- iOS実機の描画負荷・電池消費・バックグラウンド復帰、Androidでの起動。
- 通常時間による長期試遊、4〜6週間のゲームバランス。
- 保存形式の旧版移行（初版のみ）、実機の電源断試験。
- 3Dの選択/配置、方式別施設の固有表現、政策・税率、大きな研究ツリー。
- 火星復元、事故、全球環境、ED、周回、任意Googleバックアップ。

次にユーザーと決めることは、設備一覧の情報量、↑↓の使いやすさ、
予測完了時刻やドラッグ操作を追加するか。現段階は予約順の編集で配分し、割合配分は未実装。
