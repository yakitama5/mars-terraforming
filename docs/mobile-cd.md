# Android / iOS の内部テスト配信

更新: 2026-10-18。今回の依頼は、両ストアへの新規アプリ登録と、内部テストまでの自動配信。
従来の「Androidは後段」から、**Android / iOSの内部配信を並行して準備する**方針へ更新する。
一般公開の時期や収益化は決定していない。

## 現在地

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
  最新のFlutter/Web・Android/iOSのCI成功後に反映し、mainは `86b8d88`。
- Android環境へ確定IDを設定し、署名4 Secretsの存在を名前だけで再確認。
  [初回AABビルド](https://github.com/yakitama5/mars-terraforming/actions/runs/39130740248)をmainから起動した。
  Playには初回リリースの説明だけを下書き保存。AABのアップロード・リリースは未完了。
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
- 未実施: 署名済みiOS archive / IPAの検証、ASCアプリレコード作成、両ストアの初回アップロード・実配信、
  実機でのストア経由インストール、Android/iOSの長時間GPU・性能・電池検証。

登録名はDear Mars、Playは無料で確定・新規登録済み。AppleはBundle ID登録済み。
次はAppleのアプリレコード作成・配布資格情報、内部テスターの設定と実配信。
