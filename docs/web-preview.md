# PCでのWeb試遊

更新: 2026-10-13。設備配分の操作をPCでも試すためのWeb版。
iOS先行・Android後発という製品方針は変更していない。
ゲーム進行・日本語UI・FlutterScene描画を共有し、保存先だけをプラットフォームごとに分ける。

## 起動

```sh
mise install
mise exec -- flutter pub get --enforce-lockfile
mise exec -- bash tools/build_web_preview.sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory site-preview/dist
```

[http://127.0.0.1:8765/](http://127.0.0.1:8765/) をChromeで開く。
WebGL2が利用できる環境を使用する。初回は3Dシェーダと描画の初期化に時間がかかることがある。
配信を終了する場合はHTTPサーバーのターミナルでCtrl+Cを押す。
Web LocksとService Workerを使うため、HTTPSまたはlocalhost/127.0.0.1で配信する。
HTMLファイルを直接開く方法では動作しない。

`tools/build_web_preview.sh` はFlutterのreleaseビルドを作り、
`tools/prepare_web_preview.py` でオフライン用ファイルを生成して
`site-preview/dist/` に配布物を配置する。
Flutter SDK・依存は `mise.toml`、`pubspec.yaml`、`pubspec.lock` で固定する。

| 対象 | 採用版・設定 |
| --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5。今回のWeb対応でSDKは更新していない |
| flutter_scene | 0.24.3。ChromeのWebGL2で3Dを描画 |
| package:web | 1.1.1を直接依存として固定。ブラウザ保存とWeb Locksに使用 |
| 日本語フォント | Noto Sans JPを `assets/fonts/NotoSansJP.ttf` に同梱 |
| フォントのライセンス | `assets/fonts/OFL.txt`。外部フォントホストに依存しない |
| Webビルド | release / JavaScript、`--no-web-resources-cdn`。描画エンジンも同梱 |

通常の設定と開発用時間送りは別にする。Web試遊ビルドは既定で `DEV_TOOLS=true`。
通常時間にする場合は次のようにビルドし直す。

```sh
MARS_DEV_TOOLS=false mise exec -- bash tools/build_web_preview.sh
```

通常時間でも工程の数値は現在の短時間試作の仮値。
開発用「+5分」は通常時間のセーブへ影響しない。

## 操作を試す

1. 「計画をつくる」で精密機器の外部受注、生命維持研究、居住キット製造、火星輸送、居住区建設を予約する。
2. 「設備・進行」で各設備の進行中の作業、次の予約、停止理由を確認する。
3. 工場の予約にある前後ボタンで、外部受注と居住キット製造の順番を変更する。
4. 支払済みの現在の1回は続き、次の着手から変更した順番を使う。無期限受注より自分の計画を前に置くこともできる。
5. 開発用「+5分」で進め、初着陸後に居住方式を選ぶ。居住区完成と施設表示の変化を確認する。
6. 再読み込みし、予約順・世界・研究・実績が保持されることを確認する。

設備の休止中、資金・資源不足、研究や分岐待ちも設備ごとに表示する。
金額・工程時間・設備能力は共通の `lib/domain/game_content.dart` が起点。

## 保存と複数タブ

`lib/infrastructure/save_factory.dart` の条件付きexportで保存実装を選ぶ。
ネイティブは従来の `FileSaveStore`、Webは `BrowserSaveStore` を使い、
進行・保存インターフェース・ゲーム状態の形式は共通にする。

| 保存枠 | ブラウザのlocalStorageキー |
| --- | --- |
| 通常 | `mars_terraforming.save.normal` |
| 開発用 | `mars_terraforming.save.development` |

1つのキーに現在と直前の2世代をまとめ、1回の `localStorage.setItem` で一括確定する。
各世代はSHA-256付きJSONで、資金・進行時刻・予約・研究・報酬取得記録を同時に保存する。
現在世代が破損していれば正常な前世代を採用する。
両世代が破損している場合や未対応の形式の場合は、新規ゲームで上書きせず説明を表示する。

読み込み前に保存枠ごとのWeb Locksを確保し、開いている間は保持する。
同じ保存枠を別のタブでも開いた場合、2つ目は進行前に停止する。
最初のタブを閉じてから、2つ目を再読み込みすると再開できる。
保存内容が外部で変わった場合も、古い世界で上書きせず進行と後続保存を停止する。
時計を使ったロックの期限切れは設けず、端末時計変更の許容方針を維持する。

初回保存に失敗した場合は、ゲームを開始せず説明を表示する。
プレイ中の空き容量不足などは保存エラーを表示し、保存に成功するまでエラーを維持する。

ブラウザ保存はブラウザのプロファイルとorigin（スキーム・ホスト・ポート）に属する。
`localhost` と `127.0.0.1`、違うポート、SitesのURLは別セーブになる。
iOSのファイル保存からの移行・同期は行わない。
サイトデータを削除するとセーブも消える。プライベートモードの終了やブラウザによる
サイトデータの削除でも保持されない場合がある。Googleバックアップはまだ未実装。

## オフライン配信

初回アクセスではアプリ一式の取得とキャッシュ完了のため通信が必要。
取得後のゲーム進行・描画・保存にサーバー接続は必要ない。
キャッシュ完了後は同じURLのオフライン再読み込みも使える。
ブラウザのキャッシュやサイトデータを消した場合は、再取得のため通信が必要になる。

`tools/prepare_web_preview.py` が配布物の内容ハッシュを使った
`offline_worker.js` を生成する。アプリ・CanvasKit・Scene・日本語フォントを
同じoriginから取得し、ゲーム専用のキャッシュへ保存する。
`web/flutter_bootstrap.js` ではFlutterの旧Service Workerを登録せず、
オフラインキャッシュをこのworkerに一本化している。
ブラウザ保存とアプリ配布用キャッシュは別で、アプリ更新時のキャッシュ変更でセーブを消さない。

## ブラウザ検証

まず共通の進行・保存・UIを検証する。

```sh
mise exec -- bash tools/check.sh
```

Webを上記手順でビルド・配信してから、自動操作を実行する。
インストール済みPlaywrightとChromeを指定できる。個人のChromeプロファイルは使用せず、
検証用の独立したブラウザコンテキストを作る。

```sh
PLAYWRIGHT_MODULE='/path/to/node_modules/playwright' \
CHROME_BIN='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
MARS_BASE_URL='http://127.0.0.1:8765/' \
node tools/web_smoke.cjs
```

PlaywrightがNodeのモジュール検索パスにあれば `PLAYWRIGHT_MODULE` は省略できる。
Playwright管理下のChromiumを使う場合は `CHROME_BIN` も省略できる。
この自動操作は「+5分」を使うため、既定の開発用ビルドで実行する。

検証する内容は予約、設備内の順番変更、支払済み工程の継続、再読み込み後の順番保持、
研究→製造→輸送→居住、2タブ目の停止、報酬の保持、オフライン再読み込み、
外部ホストからのリソース取得がないこと。スクリーンショットを `docs/screenshots/` に出力する。
`MARS_SCREENSHOT_DIR` で出力先、`MARS_SAVE_KEY` でPagesなどの保存キーを指定できる。
実施結果と残る確認事項は [開発・検証の引き継ぎ](development.md) に記録する。
iOS実機・Android・別ブラウザの検証とは区別する。

## Sitesへの配置

所有者向けの非公開試遊として配置済み（2026-10-13）。
[Web試遊URL](https://mars-terraforming-playtest.yakuran01.chatgpt.site) のデプロイ成功をSitesで確認。
Chromeの実操作は同一配布物のlocalhost版で検証済み。ホスト先の認証を含む操作は未検証。
一般公開やiOS版の配信先変更を意味しない。

| 項目 | 値 |
| --- | --- |
| Sites project ID | `appgprj_6acd985756048191813dd5e095593a45` |
| 専用ソースディレクトリ | `site-preview/` |
| Sites設定の原本 | `tools/site_hosting.json`（Gitで管理） |
| 生成したSites設定 | `site-preview/.openai/hosting.json` |
| 静的配布物 | `site-preview/dist/`（ビルドから生成） |

Sitesへ同期する範囲は `site-preview/`。ゲームの開発元はこのリポジトリのFlutterソースに保つ。
`dist/`を直接編集せず、Flutterソースとビルド・梱包スクリプトを変更して再生成する。
`tools/site_hosting.json` のproject IDは同じ試遊サイトを更新するために保持する。
ビルド時にこの設定を `site-preview/.openai/hosting.json` へコピーする。
Sites専用の入れ子Gitをゲーム本体へ誤登録しないよう `site-preview/` 全体をignoreし、
ゲーム本体ではFlutterソース・生成手順・Sites設定原本を管理する。

配置記録:

- Source commit: `6c32ff5be9b7796118e66e831ba63d21f1df8a0e`（Sites専用Git）。Sites初回配置時点ではゲーム本体のGitは未コミットだった。
- Saved version: `appgprj_6acd985756048191813dd5e095593a45~appgver_1132ecb4aab88191930c8294278a008c`
- Deployment: `appgdep_6acd9db7eb1c81918cf5385f9270d5d2`、状態 `succeeded`。
- 公開範囲は所有者のみを維持。アクセス制御は変更していない。
- ローカル確認サーバーは配置完了後に終了。再確認時は上記コマンドで起動する。
- Sites helper実行時はNodeをPATHへ含める。最初の梱包はPATH不足で失敗したが、
  同じSite ID・ソースのまま再実行して成功。認証トークンはファイルへ保存していない。
