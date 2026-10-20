# 研究UIの小画面対応

更新: 2026-10-20。研究ツリー設計相談から引き継いだ版への、ユーザーの実画面評価を反映する。

## 変更

- 研究詳細は初期に選択なし。分類を切り替えながら全幅で見渡し、技術カードを選ぶと右側を開く。
  閉じる・分類切替で全幅へ戻り、同じツリーの表示状態を維持する。ガイド・通知の技術指定は直接開く。
  初期と分類切替は入口へ読みやすい倍率で寄り、自動の縮小は0.85倍を下限にする。
  短い横画面は研究ヘッダーとカードの余白を減らす。全範囲への縮小は全体表示ボタンを押したときに限る。
- 説明ラベルの固定76pxを廃止し、一行のまま幅を配分する。研究は「必要RP／保有RP／RP生産」と簡潔にする。
- ヘッダーへ共通RPを追加。研究者と工業員は「使用中／部門総数」。正確な値と意味はTooltip/Semanticsに持つ。
  小画面では国力・開発用加速をアイコン化し、大数値を万・億・兆に略記する。数値と進行自体は変更しない。
- 科学メモ・出典のボタンとダイアログをゲーム画面から外す。調査台帳・内部出典・第三者ライセンスは保持する。
  すべての購入可能98技術にオリジナルの短い創作文を付け、「未来の一景」として詳細末尾へ常時表示する。
  創作文は進行効果や達成を保証せず、未発見の技術・分岐を明かさない。
- 都市施設のパレット・選択・既存地区・見積もりを同じ研究分類色で表示する。

| 施設 | 表示分類 |
| --- | --- |
| 研究所・火星研究所・温室 | バイオ |
| 工業・宇宙港・火星居住 | メカニクス |
| 採掘 | マテリアル |
| 発電 | エネルギー |
| 住宅 | 中立色 |

配置条件、費用、工期、RP産出、人員確保、保存schema2/content district-7は維持する。
採用Flutter 3.47.7 / Dart 3.13.5 / FlutterScene 0.24.3、mise/pubspec/lockも変更しない。

## 検証と残る確認

Pixel 8aを意識した論理解像度873×393、SafeArea左右24・上8・下16、Noto Sans JP、文字1倍／1.4倍で検証する。
端末の表示倍率やナビゲーション方式による実際の論理解像度を固定仕様にはしない。
さらに568×320のヘッダー、大数値、文字1.6倍、通常／開発用の表示を回帰対象とする。

実施した検証:

- `mise exec -- bash tools/check.sh` が成功。依存方向、98研究の導入・保存・100seed時間分割、
  Python6件、全ファイル整形、静的解析、Flutter **512テスト**を通過した。
- 独立Chrome contextで873×393の実操作が成功し、自然終了0で後片付けまで完了。
  初回7操作、未選択全幅、4分類切替、カード選択と詳細を閉じる操作、分類保持、
  3つのRPラベル、末尾の創作文、都市パレットと選択色、再読込後のworldId・研究保持を確認。
  次のカードには実ドラッグで到達でき、pageerror・描画例外は0件。
- 最初の実画面確認で自動fitによる小さすぎるカードを発見し、入口へ寄る操作へ修正。
  再実行では約180×122pxのカードで技術名とRPを読め、15枚を撮り直して目視した。
- Web releaseビルド成功。フォントのtree-shake時に、未使用のCupertinoIconsの警告が残る。

実画面: [研究全景](screenshots/research-mobile-01-unselected.png)、
[RPの表示](screenshots/research-mobile-04-detail-rp.png)、
[未来の一景](screenshots/research-mobile-05-detail-flavor.png)、
[施設選択](screenshots/research-mobile-08-city-palette.png)、
[エネルギーの選択色](screenshots/research-mobile-11-city-energy-selection.png)。

- iPhone 17 Pro / iOS26.1 Simulatorの実GPUによる通し試験とdriverが終了0。
  未選択全幅→研究選択→RPラベル→閉じる、受注配分・配送・都市建設/増強・投資比較・火星居住・
  居住編ED・提携・人員・保存再開まで成功。新研究UIの画像2枚を回収して確認した。
  旧テストで未発見だったE13は、蓄積済みRPでE01を先に解放する公開操作へ更新した。
  初回の全画像回収では全assert成功後にdriver接続が切れたため正常終了扱いにせず、
  対象画像のprefix指定を追加して再実行した。最終実行は全断言・画像回収・終了コードまで成功。
  初回Sceneのシェーダー生成に最大約1.13秒の停止警告が残る。

iOS実画面: [研究全景](screenshots/research-mobile-ios-overview.png)、
[RP表示](screenshots/research-mobile-ios-detail.png)。再現は既存のprototype_test.dartに
`--dart-define=MARS_INTEGRATION_CAPTURE_PREFIX=research-mobile-ios` を付けてdriveする。
省略時は以前どおり全場面を回収する。

Pixel 8a実機の操作・性能・電池、通常時間の長期バランスは未検証。
次の本人評価は、ラベル・数値の読みやすさ、研究全景と詳細の切替、各技術の未来像の文体とする。

## 反映・配信結果

- 意味ごとの6コミットを[PR #36](https://github.com/yakitama5/mars-terraforming/pull/36)からdevelop、
  [PR #37](https://github.com/yakitama5/mars-terraforming/pull/37)からmainへ通常mergeした。
  両PRとも固定したHEADで全チェック成功を確認してから反映した。
- 最終mainは `02393fc0f0b17cb47c0af1d20bde0dba6a20f924`、
  developは `a2391c86f12cd7fc3ea0b6a445a73194e8336d25`。
- [main全体検証](https://github.com/yakitama5/mars-terraforming/actions/runs/39397506848)と
  [Pages公開](https://github.com/yakitama5/mars-terraforming/actions/runs/39397506726)が成功。
  公開deployment.jsonのmain・develop全SHAとrunが今回の反映内容に一致した。
  [通常版](https://yakitama5.github.io/mars-terraforming/)から修正後のUIを試せる。
- main CIで生成した17枚のうち、小画面の全景・詳細・文字拡大の3枚も目視した。
  CIの一部アイコン・ボタンに既知のフォント制約があるため、文字・アイコンの実表示は
  独立ChromeとiOS Simulatorで回収した画像を根拠とする。
- [自動内部配信](https://github.com/yakitama5/mars-terraforming/actions/runs/39397506671)は全4job成功。
  Android **701** はGoogle Play internalへ18:09:00 JST、
  iOS **7.1** はTestFlight内部グループへ18:11:14 JSTに配信確認済み（2026-10-20）。
  両記録のアプリID `io.github.yakitama5.marsterraforming`、main全SHA、run、build、配信先を二重照合した。
  Android Artifact `12252942004`、iOS Artifact `12252583280`。
  両OSの署名資材削除と、Android WIFの後片付けも成功した。
- 配信結果は両PR本文にも記録済み。完了後の本節はローカル文書へ追記し、
  記録のための追加main pushや重複配信は行わない。
- 検証済み41ファイルを元の作業場所へ同期して内容と差分形式を照合した。
  元のブランチ・未コミット作業を保持し、別作業のdocs/mobile-cd.mdは変更していない。
