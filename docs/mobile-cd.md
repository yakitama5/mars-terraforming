# Android / iOS の内部テスト配信

更新: 2026-10-20。今回の依頼は、両ストアへの新規アプリ登録と、内部テストまでの自動配信。
従来の「Androidは後段」から、**Android / iOSの内部配信を並行して準備する**方針へ更新する。
一般公開の時期や収益化は決定していない。

## 現在地

- Google PlayにDear Marsを無料・日本語のゲームとして登録した。両OSの識別子は
  `io.github.yakitama5.marsterraforming`。ユーザーは内部テスターを本人だけに指定した。
  Androidは既存の「自分」リスト（本人1名）、iOSはASCにログイン中の本人とする。
- **Androidの内部テストは公開済みで、WIF経由の自動CDも成功した**。
  初回はユーザー承認後、bootstrapの署名済みAABをPlayが受理した。
  2026-10-19 06:20 JSTに本人のリストだけを保存して公開し、Consoleの「有効」
  「内部テスターに公開」、build `1 (0.1.0)`、有効な
  [テスト参加リンク](https://play.google.com/apps/internaltest/4701193900129105222)を確認した。
  未審査のため一時的なアプリ名・ID（unreviewed）が表示される。
  その後ユーザーからAndroidのインストール成功報告を得た。端末機種・実際のビルド番号・起動動作は未確認。
  Playに登録されたupload証明書のSHA-256は
  `5D:19:8F:61:7D:55:66:F9:34:D6:79:FD:D6:94:86:B1:C4:45:69:28:B5:84:F5:1F:87:CA:02:67:64:CB:C0:0A`。
  保存済みのupload鍵および実AABの署名証明書と一致を確認した。
- iOSの新規Apple Distribution証明書・App Store profile・P12の作成とGitHub Secrets保存を
  ユーザーが承認し、完了した。証明書ID `YM5LN6CXF7`、期限2027-10-19。
  profile名 `Dear Mars CD App Store`、portal ID `YK3C2NR242`、
  UUID `3220551a-9a94-411b-afe4-3e514224cb1f`。
  `IOS_DISTRIBUTION_P12_BASE64` / `IOS_DISTRIBUTION_P12_PASSWORD` /
  `IOS_PROVISION_PROFILE_BASE64` の保存と検証が完了している。
- ASCチームAPIキー `Dear Mars CD` のApp Manager・全アプリ範囲・有効期限なしでの作成と保存も
  ユーザー承認済み。P-256秘密鍵の形式を検証し、`ASC_PRIVATE_KEY_BASE64` Secretと
  `ASC_KEY_ID=J4ACAMS57J` Variableを保存・検証した。
  `ios-testflight` の既存ID・Team ID・Issuer IDも設定済みで、配信資格情報は揃った。
  秘密値やファイル本体はGit・記録に含めない。
  iOSの確定資材8ファイルは `/Users/yakuran/.config/mars-terraforming/mobile-cd/ios/` へ保護保管した。
  dir 0700 / file 0600とコピー元との全ハッシュ一致を確認。Downloads原本も0600に制限した。
  P12のmacOS一時keychainへの読み込み、profileのCMS署名・Apple信頼チェーン・Team・ID・
  配布方式・証明書一致を検証し、一時keychainの削除と既存設定の復元を確認済み。
- **iOSは作成制限が解消し、0.1.0 (4.1) の内部配信が完了した。CDの完了判定は修正中**。2026-10-20に当該Bundle ID限定の
  API GETがHTTP 200 / アプリ0件となり、UIから新規アプリを登録した。
  ASC app IDは `6824716143`、iOS / Dear Mars / 主言語 `ja`、
  Bundle IDは `io.github.yakitama5.marsterraforming`、SKUは `dear-mars-ios`。
  管理画面では「アクセス制限あり」を選び、対象として本人1名を指定した。
  Admin・Finance等に元からある全アプリへのアクセス権を除外する設定ではない。
  DPLA警告は消え、Paid Applications Schedule更新バナーは残るが、新たな契約同意は行っていない。
  Appleへの本人の問い合わせ方針は維持し、こちらからは送信していない。
- TestFlight内部グループ `Internal`（ID `31a450e9-8d74-481f-b47f-ff3f8d40e51f`）を作成し、
  本人1名の保存をUIで確認した。全Xcodeビルドの自動配信はoffにし、CD laneの明示的配信を使用する。
  `IOS_TESTFLIGHT_GROUP=Internal` を設定し、`MOBILE_IOS_ENABLED=true` の保存・照合も完了した。
  main `f2ddfb2` からiOSだけを指定した
  [初回iOS CD検証run `39346520536`](https://github.com/yakitama5/mars-terraforming/actions/runs/39346520536)で、
  署名済みIPAの生成・アップロード・Appleの処理・内部グループへの配信が成功した。
  APIでも `VALID` / `expired=false` / `IN_BETA_TESTING` と当該グループへの双方向所属を確認した。
  後続の独自確認が配信前の `READY_FOR_BETA_TESTING` だけを許可していたため、run全体はfailureとなった。
  配信記録Artifactは未保存。一時keychainと署名材料の削除は成功。完了判定の修正と回帰検証を進める。
- CDのmainは `f2ddfb2`。両OSのEnvironmentはmainだけに制限し、
  `MOBILE_ANDROID_ENABLED=true`、`MOBILE_IOS_ENABLED=true`。
  Consoleでの初回手動公開build `1` と、後続の自動CDによるbuild `301` を区別する。
  Cloud側のAPI・WIFとGitHub Variables、Playアプリ権限は設定済み。
  請求先を紐付けず、実WIF認証からAndroid内部テストへの自動配信まで確認した。
- Google Cloudについてユーザーは **請求先を紐付けない** と明示した。
  Cloud SDKへのCloud全体の新規OAuth権限は一度自動承認審査で停止した後、ユーザーが具体的に
  明示許可した。許可画面を進め、`/private/tmp/dear-mars-gcloud` に隔離したCLI認証が終了0で完了し、
  Play所有者本人と確認した。既存の別アカウントのCLI設定は使っていない。
  専用project `dear-mars-cd`（表示名 `Dear Mars CD`、number `36882274353`）を請求先なしで作成済み。
  実queryで `billingAccountName` が空、`billingEnabled=false` を確認した。
  既存CLI設定・既存project・既存の請求先は変更していない。
- 専用projectで `iam.googleapis.com` / `cloudresourcemanager.googleapis.com` /
  `iamcredentials.googleapis.com` / `sts.googleapis.com` / `androidpublisher.googleapis.com` の
  5 APIを有効化済み。配信SAは `dear-mars-play@dear-mars-cd.iam.gserviceaccount.com`、
  Workload Identity Pool / providerはともに `github`。
  `google.subject=assertion.sub` とし、81 bytesのGitHub新形式subjectを対応付けた。
  条件はrepository ID `1381473822`、owner ID `14286444`、`refs/heads/main`、
  subject末尾 `:environment:android-internal` に限定した。
  SAの `roles/iam.workloadIdentityUser` だけを
  `principalSet://iam.googleapis.com/projects/36882274353/locations/global/workloadIdentityPools/github/attribute.repository_id/1381473822`
  へ付与。配信SAにOwner / Editor / Token Creatorを付けず、JSONキーも作成していない。
- GitHub `android-internal` Environmentの
  `GOOGLE_WORKLOAD_IDENTITY_PROVIDER=projects/36882274353/locations/global/workloadIdentityPools/github/providers/github` と
  `GOOGLE_PLAY_SERVICE_ACCOUNT=dear-mars-play@dear-mars-cd.iam.gserviceaccount.com` を設定済み。
  ユーザーが当該SAへのDear Marsだけのアプリ情報閲覧・テストトラックへのリリースの2権限を
  期限なしで付与することを明示許可し、付与済み。SAの有効期限なし・対象アプリ1件Dear Marsを確認した。
  UIは従属するアプリ品質情報の閲覧も選択済み・変更不可となり計3件と表示するが、
  手動で選択したのは上記2権限。
- 2026-10-19 07:28 JST、main `f2ddfb2` からAndroidだけを指定し、
  [初回CD検証run `39172360969`](https://github.com/yakitama5/mars-terraforming/actions/runs/39172360969)を手動起動し、成功した。
  build `301 (0.1.0)` の生成・実WIF認証・fastlane配信と、internalトラックの
  versionCode `301` / status `completed` の再確認、配信記録Artifactの保存が成功。
  署名材料・WIF認証ファイルの後片付けも成功した。
  完了後にPlay Consoleを再読込し、「有効」「最新リリース 0.1.0」「内部テスターに公開」、
  リリース日時2026-10-19 07:36 JST、概要のversionCode `301` を確認した。
  自動CDによる内部配信まで検証済み。その後ユーザーによるAndroidのインストール成功報告を得た。
- 2026-10-19 08時台、ユーザーから「テスト参加はできるがインストール画面へ進めない」と報告。
  Codex内のVivaldiでも本人の参加済み表示を確認し、`Download test app` の遷移先が
  `Not Found` になることを再現した。Consoleの内部公開は有効で、本人1名のリストも保存済み。
  [Google公式ヘルプ](https://support.google.com/googleplay/android-developer/answer/9845334?hl=ja)には、
  初回公開や変更の反映に数時間かかる場合があると記載されている。
  反映待ちが候補だが原因確定ではなく、インストール可能になったことは未確認。
  同じアカウントのAndroid端末で時間をおいて再確認し、続く場合は端末・実際のエラーを切り分ける。
  この調査では設定変更・再配信を行っていない。
- 同日、その後ユーザーがAndroidの「インストールできた」と報告した。
  上記のダウンロード不可は過去時点の症状とし、インストール成功をユーザー報告として記録した。
  端末機種・インストールされたビルド番号・起動動作・性能を検証済みとは扱わない。
- Macのロック解除を確認した。操作範囲は引き続きVivaldiの **Codexワークスペース内だけ**。
  一般公開・外部テスター・収益化は今回の内部配信の承認範囲に含めない。

## 2026-10-19のiOS契約制限の経緯

以下は10月19日時点の履歴。10月20日に作成制限は解消しており、最新状態は冒頭「現在地」を参照する。

- **iOSはASCアプリレコード作成で停止中**。2026-10-19 06:17 JSTの再読込でも、
  Developer portalではDPLAの2026-10-14版を10月18日受諾済み、ASCでは無料アプリ契約に
  「新規契約が利用可能」が残り、新規アプリのダイアログが契約更新の案内で止まった。
  ASCアプリレコードとTestFlight内部グループは未作成。署名IPAの生成・アップロードも未実施。
  契約受諾日・Team・再現状況を説明するApple Developer Support向け本文を提示した。
  ユーザーが「自分で問い合わせる」と指定し、本人の問い合わせと契約解消を待つ。
  こちらからは送信しておらず、代理送信しない。
  新APIキーで当該Bundle IDだけに絞った `GET /v1/apps` を実行するとHTTP 403、
  `FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED` が返った。
  Appleの応答も必須契約が未締結または期限切れとして制限している。
  role不足やアプリ不存在と断定せず、契約解消後にキーと当該アプリの取得を再確認する。
  同日09:55〜09:56 JSTにも再確認したが、制限は継続した。
  Developer portalを再読込しても同じTeamで10月14日版に10月18日同意済みと表示され、
  ASCの再読込後の新規アプリ作成は「契約の更新」で停止した。
  当該Bundle ID限定のAPI GETも同じHTTP 403 / 必須契約エラーだった。
  新たな契約受諾・アプリ作成・配信の変更は行わず、Appleへの本人の問い合わせ方針を維持する。
  ユーザーのSNS調査依頼で、直近のRedditにも同意済みDPLAとASCの契約更新表示が食い違う
  [本人報告](https://www.reddit.com/r/appledevelopers/comments/1x8nmta/signed_apple_developer_agreement_xcode_cloud/)と、
  無料アプリ契約が有効・新規契約ありなのに同意画面が見つからない
  [別の本人報告](https://www.reddit.com/r/iOSDevelopment/comments/1x8lq90/appstore_connect_says_i_have_agreements_to_agree/)を確認した。
  [Apple Developer Forumsの過去例](https://developer.apple.com/forums/thread/649809)には、
  翌日表示が変わったという投稿と24時間後も続いたという投稿がある。
  同期の遅延・不整合は候補になるが、SNSの体験談を今回の原因確定やAppleの障害認定とは扱わない。
  公式の反映期限も確認できていないため、時間をおいた再確認と本人の問い合わせ方針を維持する。

## 2026-10-18の登録・初回生成の経緯

以下は10月18日時点の記録。承認待ち・未実施だった項目の最新状態は上記「現在地」を参照する。

- 2026-10-18にユーザーが正式アプリ名を **Dear Mars** に決定した。
  Android / iOSの表示名を合わせ、両OSの識別子は
  `io.github.yakitama5.marsterraforming` を採用した。
  PlayのアプリレコードとAppleのBundle IDは登録済み。ASCアプリレコードは別途必要。
- GitHubの `android-internal` / `ios-testflight` Environmentを作成し、配信元をmainだけに制限した。
  `MOBILE_ANDROID_ENABLED` / `MOBILE_IOS_ENABLED` は `false`。ストア初期設定後に個別に有効化する。
- 2026-10-18にユーザーがVivaldiで両ストアへログインした。
  ブラウザ操作はユーザー指定の **Codexワークスペース内だけ** に限定する。
  Play ConsoleのYakuranアカウントと、App Store Connectの個人チームを確認。
  Apple Developer画面でチームID `S935X7WSH2` を確認した。
- ユーザーが **無料** と、ポリシー・米国輸出法の申告への同意を承認。
  Dear Mars・日本語・ゲーム・`io.github.yakitama5.marsterraforming` でPlayへ新規登録した。
  [Playダッシュボード](https://play.google.com/console/u/2/developers/7909583200864332400/app/4973407121760758999/app-dashboard)で
  アプリID `4973407121760758999` を確認。内部テストトラックは作成済み、リリースなし。
- Appleの更新契約への同意操作をユーザーが承認し、実行後Developer portalの制限解除を確認。
  チーム `S935X7WSH2` にDear Marsの明示的Bundle ID
  `io.github.yakitama5.marsterraforming` を新規登録した。
  Developer accountの契約一覧で2026-10-14発効版・2026-10-18同意済みを確認した。
  一方、App Store Connectでは無料アプリ契約が「有効（新規契約が利用可能）」で、
  新規アプリ作成が契約更新の案内で止まる。再読込・強制再読込・新しいタブでも同じ。
  有料アプリ契約は「有効」。追加の有料契約への同意は行っていない。
  公式の反映時間は未確認で、受諾済み表示とASCの不一致が続く場合はAppleへの確認が必要。
- ローカルの有効な署名はApple Developmentのみ。Apple DistributionとApp Store profile、
  App Store Connect APIキー、Google Play APIの認可は別途必要。
- Android専用のRSA 4096-bit upload鍵を新規作成し、`android-internal` の上表の4 Secretsへ保存済み。
  秘密のローカル保管先は `/Users/yakuran/.config/mars-terraforming/mobile-cd/`。
  `upload.jks` と `android-upload.json` は所有者だけが読める権限で保管し、Gitには含めない。
  ストア登録後に別の鍵を生成し直さず、この一式を安全にバックアップする。
- ASCのアプリレコード作成、両ストアの初回アップロードと内部配信成功はまだ確認できていない。
- CD基盤は [PR #28](https://github.com/yakitama5/mars-terraforming/pull/28) でdevelopへ、
  [PR #29](https://github.com/yakitama5/mars-terraforming/pull/29) でmainへ通常マージ済み。
  この時点のFlutter/Web・Android/iOSのCI成功後に反映し、当時のmainは `86b8d88`。
- Android環境へ確定IDを設定し、署名4 Secretsの存在を名前だけで再確認。
  [初回AABビルド](https://github.com/yakitama5/mars-terraforming/actions/runs/39130740248)をmainから起動した。
  この初回runはrelease用プラグイン登録の不整合で失敗し、後述の修正を行った。
  Playには初回リリースの説明だけを下書き保存。AABのアップロード・リリースは未完了。
- 当時の最新反映: 修正を [PR #30](https://github.com/yakitama5/mars-terraforming/pull/30) でdevelopへ、
  [PR #31](https://github.com/yakitama5/mars-terraforming/pull/31) でmainへ通常マージ済み。
  両PRでFlutter/WebとAndroid/iOSのCIが成功し、mainは `f2ddfb2`。
  [修正後のbootstrap](https://github.com/yakitama5/mars-terraforming/actions/runs/39133132502)も成功し、
  初回用build 1の署名済みAABをArtifact `android-first-upload-39133132502-1`
  （ID `12139256098`、期限 **2026-10-21 22:54 JST**）へ保存した。
  Playへのアップロードはまだ行っておらず、内部配信成功とは区別する。
- `ios-testflight` Environmentには非秘密のVariablesとして
  `MOBILE_APP_IDENTIFIER=io.github.yakitama5.marsterraforming`、`IOS_TEAM_ID=S935X7WSH2`、
  `ASC_ISSUER_ID=96cae473-4d91-42a7-8a9e-08105f4c6c2a` を設定済み。
  配布署名・APIキーの秘密情報とprovisioning profileは未設定。両配信フラグは引き続き `false`。
- Apple Distribution証明書とAPIキーは作成フォームまで準備したが、発行・GitHubへの保存は承認待ち。
  ローカルのCSRと新しい暗号化秘密鍵は `/private/tmp/dear-mars-ios-signing/` に
  dir 0700 / file 0600で一時保管。CSRだけをAppleへ送り、秘密鍵はアップロードしない。
- Google Cloudは本人アカウントで専用プロジェクト `Dear Mars CD` / `dear-mars-cd` の作成を準備。
  UIが請求先を必須とし、同名の請求先が複数あるため選択・作成はユーザー対応待ち。
  既存の別プロジェクトや課金先は変更していない。WIF・Play API権限はまだ未設定。
- 内部テスターはPlayの既存「自分」リストとASC本人だけを提案し、対象の回答待ち。

## 配信経路

`.github/workflows/mobile-internal.yaml` を使う。mainへのpushで、有効化したOSだけを配信する。
手動実行では `platform=android` / `ios` / `both` を指定できる。main以外からは実行しない。
配信前に `tools/check.sh` を実行し、releaseでは `DEV_TOOLS=false` を明示する。
既存のPages配信・Webの保存枠は変更しない。
PRでは別の `mobile-builds.yaml` でAndroid debug / iOS Simulatorのビルドと
署名なしreleaseの拒否、iOSのmanifest同梱を確認する。ストア資格情報は使わない。

- Android: release AAB → Google Playの `internal` トラック。
- iOS: 署名archive / IPA → TestFlightの内部グループ。
- productionトラック、App Storeの審査提出、外部テスターへの配信は行わない。

初期設定が済んでいないpushは配信をskipする。手動で未設定のOSを指定した場合は、
設定不足として失敗させる。skipしたrunを配信成功の証拠にしない。
ビルド番号・再実行の扱い、資格情報の検証は `tools/mobile_cd.py`、配信は `fastlane/Fastfile` に置く。

採用版はFlutter 3.47.7、Ruby 3.4.11、Bundler 4.0.16、fastlane 2.240.1、CocoaPods 1.17.0、
Temurin 17.0.19+10、CIのXcode 26.2（ローカルの26.1.1は維持）。Ruby / runnerはワークフロー、Ruby依存は `Gemfile.lock`、
Flutter / Dart依存はmise・pubspec・pubspec.lockで固定する。ActionsもコミットSHAを固定する。

初回Console用のAndroid buildは1、CDではAndroid=`run_number * 100 + run_attempt`、
iOS=`run_number.run_attempt`。再実行時にも別番号を使い、既存ストア番号以下なら拒否する。
run_numberは1〜9999、attemptは1〜99。それを超える前、またはワークフローの作り直し時には採番方式を移行する。
配信を直列化し、アップロード直前に現在のmainとSHAが違えば中止する。
古いrunの再実行で新しいビルドへ戻さず、最新mainで新しいrunを起動する。

## GitHubの設定

両環境で `MOBILE_APP_IDENTIFIER` にストアで確定したIDを設定する。
ソースのapplicationId / Bundle IDと一致しなければ停止する。
公開リポジトリのため、資格情報をGit・Issue・PR・会話へ貼らない。

| Environment | Variables | Secrets |
| --- | --- | --- |
| android-internal | `MOBILE_APP_IDENTIFIER`, `GOOGLE_WORKLOAD_IDENTITY_PROVIDER`, `GOOGLE_PLAY_SERVICE_ACCOUNT` | `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` |
| ios-testflight | `MOBILE_APP_IDENTIFIER`, `IOS_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `IOS_TESTFLIGHT_GROUP` | `IOS_DISTRIBUTION_P12_BASE64`, `IOS_DISTRIBUTION_P12_PASSWORD`, `IOS_PROVISION_PROFILE_BASE64`, `ASC_PRIVATE_KEY_BASE64` |

有効化フラグ `MOBILE_ANDROID_ENABLED` / `MOBILE_IOS_ENABLED` はrepository Variables。
OSごとの初期設定を終え、実際に配信できることを確認する段階で `true` にする。
配信用ファイルはrunnerの一時領域へ権限を制限して展開し、処理後に消す。
Androidの長期サービスアカウントJSONキーは使わず、GitHub OIDC / Google Workload Identity Federationを使う。

## Google Playの初回手順

1. 所有者のPlay Consoleへログインし、新規のゲームとして日本語のアプリを作成する。
   「無料／有料」が必要になったら、未決定の収益化方針をユーザーへ確認する。
   内部テストのためだけに無料の公開設定を確定しない。有料アプリも内部テスターは無料で利用できる。
2. 専用upload鍵で最初のrelease AABを作る。debug署名は使わない。
   同じ鍵・alias・passwordを維持し、ローカルの秘密保管先もバックアップする。
   ローカル容量が不足する場合は、main上の `android-bootstrap.yaml` を手動実行する。
   必要なのは確定IDと署名の4 Secretsだけで、Google APIや配信の有効化フラグは不要。
   build 1のAABを3日間のArtifactに保存し、ストアへはアップロードしない。
   このAABをダウンロードして初回登録に使用する。以降は通常CDの新しい番号を使う。
3. Consoleで最初のAABをアップロードし、Play App Signingの設定を確認する。
   利用規約への同意、署名権限の新設などは、その時点で内容を提示し必要な確認を取る。
4. 内部テストの対象者を設定し、初回リリースを開始する。
   テスターの宛先は所有者に確認し、他プロジェクトのアドレスを流用しない。
5. Google CloudでAndroid Publisher APIを有効化し、配信専用service accountとWIFを用意する。
   GitHub側のrepository、main、Environmentに信頼対象を制限する。
   WIFの属性条件には不変のrepository ID `1381473822` とowner ID `14286444`、
   `assertion.ref == 'refs/heads/main'`、内部配信Environmentを組み合わせる。
   GitHubのOIDC subjectは旧形式とID付き形式があるため、未確認の旧subject完全一致を固定しない。
   例は `assertion.repository_id == '1381473822' && assertion.repository_owner_id == '14286444' && assertion.ref == 'refs/heads/main' && assertion.sub.endsWith(':environment:android-internal')`。
   この条件と `attribute.repository_id` のprincipalSetを専用SAのWorkload Identity Userに限定する。
   SAにはProject Owner/Editor等を付けない。
   Play Consoleでは対象アプリのテストトラックへ必要な権限だけを与える。
   現laneで必要なのはDear Marsのアプリ情報閲覧とテストトラックへのリリースで、
   製品版・テスター管理・売上/課金・ストア掲載情報の権限は付けない。
6. 上表を設定してAndroidを有効化し、mainから手動実行する。ConsoleでversionCodeと
   `internal` リリースの状態を再確認して、テスト参加URLを記録する。

Play APIを使う前に少なくとも一度Consoleからビルドを登録する必要がある。
API経由でdraftアプリの最初のcompletedリリースを完了できるとは仮定せず、
Consoleで初回内部リリースまで済ませる。以降のbuildでCDを検証する。
[fastlaneの初回要件](https://docs.fastlane.tools/actions/upload_to_play_store/)と
[Googleの内部テスト手順](https://support.google.com/googleplay/android-developer/answer/9845334)を参照。
OIDC形式は[GitHubのimmutable subject仕様](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims)、
Cloud設定は[GoogleのWIF手順](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)を参照。

## App Store Connectの初回手順

1. 有効なApple Developer Programの所有者／権限を持つアカウントでログインする。
   既存XcodeのTeam IDを無条件に今回の所有者として採用しない。
2. 確定Bundle IDをDeveloper portalへ登録し、App Store Connectへ新規アプリを作成する。
   日本語・iOS、SKUは他アプリと衝突しない値にする。
3. Apple Distribution証明書の秘密鍵付きP12と、そのBundle ID向けのApp Store profileを用意する。
   既存証明書をむやみに失効させず、必要なものだけを追加する。
4. App Store Connect APIキーを用意し、アップロードと内部グループの管理に必要な権限を設定する。
   `.p8` は一度だけ取得できる秘密情報として扱い、GitHub Environment Secretへ保存する。
5. TestFlightに内部グループ（例: `Internal`）を作成し、意図した内部テスターを追加する。
   ASCユーザーの新規招待・権限付与が必要な場合は、対象者と範囲を先に確認する。
6. 上表を設定してiOSを有効化し、mainから手動実行する。
   アップロードだけで完了とせず、Appleの処理後に対象ビルドが内部グループで利用可能な状態まで確認する。

[新規アプリ登録](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)、
[App Store profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)、
[TestFlight内部配信](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)を参照。

## iOSの申告と残る製品準備

現在はセーブのSHA-256整合性検知とローカル機能だけで、独自の暗号通信・暗号化を実装していない。
実装と依存の確認に基づき `ITSAppUsesNonExemptEncryption=false` を明示する。
Googleバックアップ等を追加する際は再評価する。
[Appleのキー仕様](https://developer.apple.com/documentation/BundleResources/Information-Property-List/ITSAppUsesNonExemptEncryption)を参照。

`PrivacyInfo.xcprivacy` は追跡なし・収集なしとし、セーブファイルのメタデータ参照を
`FileTimestamp / C617.1`（アプリコンテナ内）として宣言する。
Flutter SDK自身のmanifestは維持し、SDK専用理由をアプリへコピーしない。
署名archiveのPrivacy ReportとASCの検証は、配信資格情報の準備後に実施する。
[Appleの必須理由API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)を参照。

アイコンは現時点ではFlutter雛形。正式アイコン、掲載用素材、実機性能、ストアの一般公開、
課金・広告・価格は今回の内部配信設定で完成したことにしない。
従来の `com.example` でインストール済みの試作とは別アプリになるため、旧ネイティブセーブは自動移行しない。
Webのセーブは今回のID変更の対象外。

## 検証記録

以下は段階ごとの実施履歴。各時点の未実施・確認予定を現在の保留事項と混同せず、
最新の配信状態は冒頭「現在地」とこの節末尾を参照する。

- `mise exec -- bash tools/check.sh`: 依存方向・整形・静的解析と434テストが成功。
  既知の `agency_widget_test.dart` の画面外tap警告はあるが、失敗はない。
- 候補Bundle IDでiOS Simulatorのdebugビルド成功。privacy manifest追加後は再検証する。
- CDガードのPython6件、実fastlane 2.240.1のRuby4件・8 assertions、actionlint、
  Ruby構文、依存解決・lane読込、plist構文が成功。
  ローカルRubyは4.0.6。CIの3.4.11での実行は別途Actionsで確認する。
- Android debugビルドは初回のGradle 9.3.1依存生成中にホストの空きが383MiBまで低下したため中断
  （assembleDebug終了130）。コンパイル成功・失敗の判定は未完了。
  今回生成した同版のGradleキャッシュと再生成可能な検証出力を整理し、1GiB以上へ回復した。
  Android / iOSの残るビルドはPRのGitHub Actionsで確認する。
- 初回ActionsではFlutter解析・434テスト・Web releaseが成功。
  Android debug APKもビルド成功。release拒否の検査はrunnerにripgrepがなかったため検査側が失敗し、
  標準Pythonで照合するよう修正した。
  iOSではRuby 3.4.11によるPython5件 / Ruby3件も成功したが、locked Pod installが失敗した。
  既存lock生成版1.17.0に合わせ、Flutter 3.47.7の既定SwiftPM有効化をCIだけ明示的に無効化する。
  これにより既存のCocoaPods構成を維持し、lockを勝手に書き換えない。
  SDKのpodhelperはSwiftPM有効時にPackage.swiftのある2プラグインをPodから除外するため、
  既存lockと不一致になっていた。config-onlyはPod installを呼ぶため、その前処理には使わない。
- 修正後のlocked Pod installは成功。Xcode 26.1.1でのSimulator設定取得は失敗したため、
  runnerに対応runtimeがある26.2へCI/CDの固定値を揃え、診断付きで再確認する。
  runnerのXcodeとSimulator runtimeは独立して搭載されるため、Xcodeの存在だけでは選ばない。
- 2回目のAndroid CIはdebug APKと署名なしreleaseの拒否が両方成功。
  [確認run](https://github.com/yakitama5/mars-terraforming/actions/runs/38897437582)のAndroid jobを参照。
- [両OS成功run](https://github.com/yakitama5/mars-terraforming/actions/runs/38898044310)
  （コード `3edcbfc`）でAndroid APK・署名必須チェック、Xcode 26.2によるiOS Simulatorビルド、
  privacy manifestの同梱・Bundle ID一致が成功。Ruby 3.4.11での4件・8 assertionsも成功した。
  Xcodeの選択と利用可能destinationを揃えることで解消したが、26.1.1の失敗の内部原因は未確定。
- 初回AABワークフローはactionlintとPythonのbuild-only検査を実施。署名AABの実生成は、
  確定IDを設定してmainへ反映した後に実行する。
- [最終追加分のCI](https://github.com/yakitama5/mars-terraforming/actions/runs/38898962195)
  （コード `3a6881f`）も両OS成功。Python6件・Ruby4件、Android APKと署名拒否、
  iOS Simulatorとmanifest同梱が成功し、同じSHAのFlutter/Webチェックも成功した。
- 2026-10-18のDear Marsへの名称変更: Androidラベル、iOS表示名、Flutterタイトル/HUD、
  Web/PWAタイトルとREADMEを更新。`tools/check.sh` のPython6件・依存方向・整形・静的解析・
  Flutter434テスト、plist / Manifest XML / Web manifest JSON / HTMLの構文と名称照合が成功。
  進行値・保存ID・アプリ識別子は変更していない。
- 名称変更後のSHA `5c31c51` は[Flutter/Web検証](https://github.com/yakitama5/mars-terraforming/actions/runs/39085752746)と
  [Android/iOS検証](https://github.com/yakitama5/mars-terraforming/actions/runs/39085752727)が成功。
  Android APK・署名なしrelease拒否、locked Pod install、iOS Simulator、privacy manifestとIDの照合まで確認。
  main反映前のPR #29も[Flutter/Web](https://github.com/yakitama5/mars-terraforming/actions/runs/39130063573)と
  [Android/iOS](https://github.com/yakitama5/mars-terraforming/actions/runs/39130063348)が成功した。
- mainの初回署名AAB生成run `39130740248` は、releaseのJavaコンパイルで失敗した。
  `integration_test` が開発用の生成登録コードに残る一方、Gradleはrelease依存から除外するため、
  `IntegrationTestPlugin` が見つからなかった。成果物の生成・アップロードには到達していない。
  採用Flutter 3.47.7の実装を確認すると `--no-pub` はrelease用登録コードの再生成も省略する。
  Androidのbootstrapと通常配信から同オプションを外し、SDKにrelease用コードを再生成させる。
  最初のpub getは引き続きlockを強制し、PRでは破棄可能なCI専用鍵による本物のrelease AABと
  テストplugin除外・lock不変を検査する。配布用の秘密鍵はPRに渡さない。
  修正後のactionlintと `tools/check.sh`（Python6件・依存方向・整形・静的解析・Flutter434テスト）は成功。
  ローカルの初回検証はSDKキャッシュへの書込制限で開始できず、承認された権限で再実行した。
  修正後のnative release AAB生成はCIで確認する。未生成の成果物を配信成功として記録しない。
- 修正後のPR #30は[Flutter/Web](https://github.com/yakitama5/mars-terraforming/actions/runs/39131662182)と
  [Android/iOS](https://github.com/yakitama5/mars-terraforming/actions/runs/39131662206)、
  main反映前のPR #31も[Flutter/Web](https://github.com/yakitama5/mars-terraforming/actions/runs/39132466699)と
  [Android/iOS](https://github.com/yakitama5/mars-terraforming/actions/runs/39132466643)がすべて成功した。
  Android debug・署名なしrelease拒否に加え、破棄可能なCI専用鍵による実release AAB生成、
  `IntegrationTestPlugin` の除外、lock不変を確認。iOS Simulatorとprivacy manifest / ID照合も成功した。
  修正はmain `f2ddfb2` へ反映済み。
- 2026-10-18の[bootstrap run `39133132502`](https://github.com/yakitama5/mars-terraforming/actions/runs/39133132502)は、
  同じmain `f2ddfb2` で434テストを含むチェック、初回release AAB生成、lock不変、署名検証、
  Artifact保存、署名材料の後片付けまで成功。
  Artifact名は `android-first-upload-39133132502-1`、IDは `12139256098`、
  保存期限は2026-10-21 22:54 JST。ストアへのアップロード・配信はこのrunの対象外で未実施。
- 同Artifactを `/private/tmp/dear-mars-first-upload/android-first-upload-39133132502-1/app-release.aab`
  へ取得し、bundletool 1.18.3のmanifest読取とvalidateが成功。
  packageは確定ID、表示名はDear Mars、versionNameは `0.1.0`、versionCodeは `1`。
  83,945,230 bytes、AABのSHA-256は
  `4b407a60368997f4b5de219dac4f90e6e49bbda715dddf7b5635d6b2d88bae6a`。
  jarsigner検証が成功し、署名証明書は保存済みupload鍵と一致。
  ローカルJDK 21ではJarInputStreamとJarFileの読取結果が異なるという警告も出たが、
  検証終了コードは0、bundletoolの検証も成功。
  実ファイルのmanifestは末尾にあり、重複エントリはない。
  [JarInputStreamの仕様](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/jar/JarInputStream.html)は
  manifestが先頭付近にある場合にstream署名検証するため、この配置での警告と整合する。
  警告を消すための再梱包・再署名は行わず、この時点ではPlay側の受理を次の確認事項として残した。
- 10月18日の続行時にMacがロックされており、UI操作を停止してユーザーへロック解除を依頼した。
  10月19日に解除を確認した。
  操作範囲は引き続きVivaldiのCodexワークスペースだけとする。
- 2026-10-19: Playが同じ初回AABを受理し、本人リストだけの内部テスト公開が成功。
  06:20 JSTにbuild `1 (0.1.0)` の「有効」「内部テスターに公開」と参加リンクの有効化を確認した。
  署名済みAABの生成成功から、Consoleでの初回公開確認へ進んだ。
  この時点では自動CD・実機インストールは未検証だった。後続の自動CD結果は以下に記録する。
- 2026-10-19: Apple Distribution / profile / P12とASCチームAPIキーの形式・保存を検証。
  iOSの配信資格情報は揃ったが、06:17 JST時点でASC新規アプリ作成の契約更新制限が続いている。
  この記録更新ではビルドを再実行せず、文書の差分検査だけを行った。
- 2026-10-19: ユーザーのCloud SDK権限の明示許可後、隔離CLIで本人認証が終了0で成功。
  専用projectの作成、請求先未関連付けの実query、5 API有効化、SA / WIF設定、
  GitHub Variablesの保存まで完了した。続いてユーザー承認後、専用SAへDear Marsだけの
  アプリ情報閲覧・テストリリース権限を期限なしで付与し、対象アプリ1件を確認した。
  Androidフラグだけを有効化し、07:28 JSTにmain `f2ddfb2` から
  [run `39172360969`](https://github.com/yakitama5/mars-terraforming/actions/runs/39172360969)を手動起動。
  runが成功し、実WIF認証、build `301 (0.1.0)` のfastlane配信、internalトラックの
  status `completed` / versionCode `301` の再確認、配信記録Artifactの保存、署名材料とWIFのcleanupまで成功。
  完了後のPlay Console再読込でも「有効」「最新リリース 0.1.0」「内部テスターに公開」と
  2026-10-19 07:36 JSTのリリース日時、概要のversionCode `301` を確認した。
  請求先なしでAndroidの自動内部配信を実証した。実機インストールは未実施。
  Apple Supportは本人が問い合わせる指定へ更新し、こちらからの送信は行っていない。
- Androidのストア経由インストールは、その後ユーザーから成功報告を得た。
  実際のビルド番号・端末機種・起動と性能の検証、およびiOSの署名済み配信は未実施。
- 2026-10-20: 当該Bundle ID限定のAPI GETがHTTP 200 / アプリ0件となり、契約による作成制限の解消を確認。
  UIでASCアプリ `6824716143`（iOS / Dear Mars / `ja` / SKU `dear-mars-ios`）を作成した。
  「アクセス制限あり」を選び、対象として本人1名を指定し、既定のBundle IDを使用する。
  DPLA警告は消えた。Paid Applications Schedule更新バナーは残るが、今回新たな契約同意は行っていない。
  内部グループ `Internal` を作成し、本人1名を保存。全Xcodeビルドの自動配信はoffとした。
  `IOS_TESTFLIGHT_GROUP=Internal`、`MOBILE_IOS_ENABLED=true` を設定・照合し、Androidもtrueを維持する。
  main `f2ddfb2` から[run `39346520536`](https://github.com/yakitama5/mars-terraforming/actions/runs/39346520536)をiOSだけで起動した。
  09:27 JSTにアップロード、09:36 JSTに処理と内部配信が成功。独立したAPI確認でも
  0.1.0 (4.1)、`VALID`、非期限切れ、`IN_BETA_TESTING`、指定グループへの双方向所属を確認した。
  fastlane 2.240.1の `ready_for_internal_testing?` は配信後の `IN_BETA_TESTING` をfalseとするため、
  後続の独自検証だけでrunが失敗した。配信記録Artifactは0件。keychain・署名材料の削除は成功した。
  配信済み4.1を重複アップロードせず、判定と回帰テストを修正する。
  確認処理をヘルパーへ分け、`READY_FOR_BETA_TESTING` と `IN_BETA_TESTING` を許可しつつ、
  `VALID`・明示的な非期限切れ・要求ビルド番号・指定グループへの実所属を毎回APIから再確認する。
  未成立時は秘密値を含まない処理状態と所属有無を記録する。
  ローカルでは依存方向・Python 6件・122ファイル整形・静的解析・Flutter 434件が成功。
  既存の画面外tap警告1件は残る。固定gemでRuby回帰8件40 assertions、Fastfile読込・構文検査も成功。
  ローカルRubyは4.0.6 / Bundler 4.0.16で、採用Ruby 3.4.11の確認と修正後の実自動配信はCIに残る。

登録名はDear Mars、Playの本人向け内部テストとWIF経由の自動CDは確認済み。
Androidはユーザーによるインストール成功報告済み。端末機種・実際のビルド番号・起動動作・性能は未報告。
iOSはASCアプリと本人1名の内部グループが作成済みで、0.1.0 (4.1) は内部配信済み。
次はCDの完了判定を修正し、新しいビルドで自動配信・配信記録・後片付けまで正常終了することを検証する。
Android / iOSの配信は両方有効。請求先の関連付けは行わず、Appleへの問い合わせはこちらから送信しない。
