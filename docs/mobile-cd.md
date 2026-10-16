# Android / iOS の内部テスト配信

更新: 2026-10-16。今回の依頼は、両ストアへの新規アプリ登録と、内部テストまでの自動配信。
従来の「Androidは後段」から、**Android / iOSの内部配信を並行して準備する**方針へ更新する。
一般公開の時期や収益化は決定していない。

## 現在地

- アプリ名は既存の「火星開発計画」、両OSの識別子は候補
  `io.github.yakitama5.marsterraforming` に揃える。コード上の変更はビルド検証用で、
  ストア登録前にユーザーへ確認中。登録済み・名称確保済みとは扱わない。
- GitHubの `android-internal` / `ios-testflight` Environmentを作成し、配信元をmainだけに制限した。
  `MOBILE_ANDROID_ENABLED` / `MOBILE_IOS_ENABLED` は `false`。ストア初期設定後に個別に有効化する。
- ChromeでGoogle Play Consoleの本人確認とApp Store Connectのサインイン画面を確認。
  今回のアプリを所有する開発者アカウントでのログインを依頼中。
  現在Chromeで選択されていたGoogle Workspaceアカウントを、このゲームの所有者と推定しない。
- ローカルの有効な署名はApple Developmentのみ。Apple DistributionとApp Store profile、
  App Store Connect APIキー、Google Play APIの認可は別途必要。
- Android専用のRSA 4096-bit upload鍵を新規作成し、`android-internal` の上表の4 Secretsへ保存済み。
  秘密のローカル保管先は `/Users/yakuran/.config/mars-terraforming/mobile-cd/`。
  `upload.jks` と `android-upload.json` は所有者だけが読める権限で保管し、Gitには含めない。
  ストア登録後に別の鍵を生成し直さず、この一式を安全にバックアップする。
- ストアの新規登録、初回アップロード、内部グループへの配信成功はまだ確認できていない。

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

採用版はFlutter 3.47.7、Ruby 3.4.11、Bundler 4.0.16、fastlane 2.240.1、CocoaPods 1.16.2、
Temurin 17.0.19+10、Xcode 26.1.1。Ruby / runnerはワークフロー、Ruby依存は `Gemfile.lock`、
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
3. Consoleで最初のAABをアップロードし、Play App Signingの設定を確認する。
   利用規約への同意、署名権限の新設などは、その時点で内容を提示し必要な確認を取る。
4. 内部テストの対象者を設定し、初回リリースを開始する。
   テスターの宛先は所有者に確認し、他プロジェクトのアドレスを流用しない。
5. Google CloudでAndroid Publisher APIを有効化し、配信専用service accountとWIFを用意する。
   GitHub側のrepository、main、Environmentに信頼対象を制限する。
   WIFの属性条件には不変のrepository ID、`assertion.ref == 'refs/heads/main'`、
   `assertion.sub == 'repo:yakitama5/mars-terraforming:environment:android-internal'` を組み合わせる。
   Play Consoleでは対象アプリのテストトラックへ必要な権限だけを与える。
6. 上表を設定してAndroidを有効化し、mainから手動実行する。ConsoleでversionCodeと
   `internal` リリースの状態を再確認して、テスト参加URLを記録する。

Play APIを使う前に少なくとも一度Consoleからビルドを登録する必要がある。
API経由でdraftアプリの最初のcompletedリリースを完了できるとは仮定せず、
Consoleで初回内部リリースまで済ませる。以降のbuildでCDを検証する。
[fastlaneの初回要件](https://docs.fastlane.tools/actions/upload_to_play_store/)と
[Googleの内部テスト手順](https://support.google.com/googleplay/android-developer/answer/9845334)を参照。

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
- CDガードのPython5件、実fastlane 2.240.1のRuby3件・7 assertions、actionlint、
  Ruby構文、依存解決・lane読込、plist構文が成功。
  ローカルRubyは4.0.6。CIの3.4.11での実行は別途Actionsで確認する。
- Android debugビルドは初回のGradle 9.3.1依存生成中にホストの空きが383MiBまで低下したため中断
  （assembleDebug終了130）。コンパイル成功・失敗の判定は未完了。
  今回生成した同版のGradleキャッシュと再生成可能な検証出力を整理し、1GiB以上へ回復した。
  Android / iOSの残るビルドはPRのGitHub Actionsで確認する。
- 未実施: 署名済みiOS archive / IPAの検証、両ストアの初回登録・実配信、
  実機でのストア経由インストール、Android/iOSの長時間GPU・性能・電池検証。

次の判断は、登録名・アプリID、所有者アカウント、必要なら無料／有料、内部テスターの宛先。
ログイン完了後、ストア初期設定と実配信の確認を続ける。
