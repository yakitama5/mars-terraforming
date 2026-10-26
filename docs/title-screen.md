# 火星と宇宙のタイトル画面

更新: 2026-10-26。毎回のコールド起動で、OPより前にタイトル画面を表示する。
上にDear Mars、下に火星の地平線を置く構図は
[Figmaの絵コンテ](https://www.figma.com/design/0vWrMkGgHBny1U76P0b2J2/Untitled?node-id=1-2)を基準とする。
Figmaの原稿は変更していない。

初稿の手作りの地形・機体・星には、ユーザーから品質が不足しているとの評価があった。
NASAの観測画像と実測標高、詳細な宇宙機モデル、ESOの全天写真を使う写実寄りの表現へ作り直し、
ユーザーから「モデルはすごくいい」と採用評価を得た。追加依頼で運動と読込中の操作を変更し、
ゲーム内の全球表示にもモデルを共有する。都市開発の近接箱庭は現在のトゥーン調を維持する。
続く「めっちゃいい」との評価を受け、火星の地表も自転して見える視点へ変更し、木星と土星を遠景へ追加する。
その後のサイズ感の見直しで、遠景の角径は実半径・実距離へ合わせる。従来の大きな惑星円盤は履歴として区別する。
[見かけの大きさの基準](title-apparent-scale.md)のとおり、現在は地球/木星/土星が小さな光点となる。

## 起動と操作

- 保存の読み込みと初回保存が成功した後に表示する。破損・未知形式・別タブの停止を迂回しない。
- タイトル・開始案内・開始操作は天体や宇宙機の読込を待たずに表示する。
  ロード中のタップ/キー入力でも開始でき、破棄後に届くready/errorで画面を更新しない。
- 背景だけを黒から900msでフェードインする。タイトル/CTAは背景のfadeに含めない。
  動きを減らす設定では背景も即時表示。描画失敗時も開始操作を妨げない。
- 画面全体のタップ/クリック、Enter/Spaceで開始する。通常は400msの暗転を挟み、
  連打・キーの押しっぱなしでも開始を一度だけ行う。動きを減らす設定では暗転を待たない。
- 新規世界はタイトル→既存の3D序章/会話/命名→ゲーム。既存世界はタイトル→ゲーム。
- タイトルを見たという値は保存しない。コールド起動のたびに表示し、背景復帰だけでは戻さない。
- 新規世界の導入前の資金保護は既存Controllerを使う。既存世界は従来どおり放置進行・自動保存する。
- 描画の準備に失敗した場合は説明と開始操作を残す。説明は開始案内に重ならない下側へ表示し、
  セーブを初期化して回避しない。
- 下端に星空の出典 `ESO/S. Brunier` と `Credits` を表示する。
  素材クレジットは開始操作と独立して開き、同梱の文面で原URL・CC BY 4.0・表示時の変更、
  NASAの天体/宇宙機の出典を確認できる。閲覧に通信は必要ない。

## 天体・星空・宇宙機

惑星の観測画像は、球体と実測地形へ貼る3Dテクスチャとして使う。
太陽、惑星、探査機、ロケット、小惑星は独立した3D物体で、静止画1枚をタイトル全体として表示しない。
星空はESOの全天パノラマを視線方向に応じて参照するSkyboxシェーダー。
Figmaやゲームのスクリーンショットは描画素材に使わない。

| 対象 | 現在の表現 |
| --- | --- |
| 火星 | Vikingの4096×2048カラー、MOLAの実測標高から変位させた192×320分割の球体、同標高由来の2048×1024法線。初期はValles Marinerisが見える姿勢で、地形と施設が一体で自転 |
| 火星の地形 | 61,953頂点・122,240三角形。標高を1.5倍、法線の勾配を2倍にした視認用の誇張。架空の峡谷・火山・クレーターは追加しない |
| 地球 | Blue Marbleの昼、Black Marbleの夜、独立した雲の各2048×1024画像。自転、太陽方向に応じた明暗境界、夜の都市光と海面反射 |
| 木星 | NASA VTADの公式モデルに含まれる雲画像を球面へ再投影したテクスチャと扁平な球体。自転と公転で見える面が変わる |
| 土星 | NASA VTADの雲画像と半径方向の環画像。扁平な球体、傾斜した立体の環、球体と環の前後関係・相互影 |
| 大気 | 球殻と専用シェーダーによる薄い縁、太陽側の散乱光。美術上の簡略表現で、厳密な多重散乱計算ではない |
| 星空 | ESO/S. Brunierの6000×3000全天写真をGPU読込時4096×2048へ縮小。低輝度のノイズを持ち上げず、控えめな露光・彩度で星と銀河を表示 |
| 太陽 | HDR発光の球体、周縁減光と粒状模様、別メッシュの加算光コロナ・ストリーマー・弱い光芒 |
| 探査機 | NASA公開のMars Reconnaissance Orbiter (MRO) (A)。通信皿、太陽電池、機器、支柱、断熱箔の詳細モデル |
| ロケット | NASA/Michael D. CarbajalのSaturn V。段構成、配管、ノズル、外板を保持し、タイトルの航行イメージへ使用 |
| 小惑星 | NASA公開のBennu形状に全球実測モザイクを貼り、補助normalを加えたモデル |

Saturn Vがそのまま火星へ飛んだ、という歴史上の説明は追加しない。
遠景の角径は実半径・実AU距離へ合わせる。公転/自転の周期と初期配置、機体の縮尺・経路・速度、未来の開発はタイトルの演出である。
NASA/ESOの原素材へ本作のMITを適用せず、各素材の条件とクレジットを保持する。

出典、画像の座標/変換、同梱ファイルのSHA-256、変更範囲は以下を参照する。

- [天体のカラー・実測標高・昼夜・雲](title-assets.md)
- [ESOの全天写真・サンプラー・太陽](title-cosmos-assets.md)
- [NASAの宇宙機・Bennu・派生GLBの再生成](title-spacecraft-assets.md)
- [木星・土星と立体の環](title-gas-giant-assets.md)

## 演出の動きと負荷の扱い

火星の中心とカメラの構図は固定し、自転とカメラの周回を分ける。
火星と同じ速さで回る旧視点は地表の自転が見えなかったため、カメラは火星自転の25%の速さで回る。
地表・施設の灯り・大気を含む火星全体を回し、地形が画面の中を流れる様子を見せる。
太陽中心の共通慣性系で地球・火星・木星・土星を公転させ、
カメラ周回・軸傾斜の逆変換で見かけの天体方向を求める。星空は同じ変換で視線を戻して参照する。
地球と太陽は常時画面へ固定せず、視錐台と火星による遮蔽で自然に現れたり隠れたりする。
地表の明暗も画面内の太陽と同じ方向へ合わせる。地球と太陽の自転、独立した雲も継続する。
木星・土星も同じカメラ座標で公転させ、初期の画角では巨惑星を望める配置にする。
両方とも常時表示する貼り絵にはせず、画角と火星の遮蔽で出入りする。
木星・土星の球体をそれぞれの軸で自転させ、土星の環は球体と同じ赤道面へ合わせる。
木星・土星を開発可能な天体や選択先へ追加するものではない。

ロケット・MRO・小惑星は火星中心を焦点とする傾斜楕円を途切れず周回する。
位置と解析速度を同じ離心近点角から求め、ロケット/衛星の+Yを接線へ向ける。
小惑星は周回姿勢に自転を重ねる。全軌道が最大地形半径の外を通り、カメラへ接近しすぎない。
旧版の時間窓による出現/消失と直線の横切りは撤去する。機体/小惑星は従来より縮小する。
周期・距離・縮尺は見える運動へ圧縮した美術仕様で、精密な天文暦や実際の機体の軌道ではない。
演出は表示用の単調時刻を使い、ゲームの時計・乱数・保存と分離する。

休止・非表示・動きを減らす設定ではTickerを止め、復帰直後の巨大な時間差を演出へ適用しない。
通常の描画は最大30fps、Sceneの描画倍率は端末倍率を1〜2に制限する。
形状・画像はロード時に用意し、通常フレームでは姿勢・位置・表示用の材質パラメーターを更新する。
完成施設など保存由来の外観が変わったときだけ、火星の表示ノードを差し替える。

星空はmipmapを持つTexture2Dを使う。min/magをlinear、mipをlinear、
経度をrepeat・緯度をclampに明示し、拡大された色付き画素や縮小時のちらつきを抑える。
物体の環境照明とは分離し、恒星カタログ画像の暗部ノイズを増幅した初稿の方法は使わない。
元JPEGは6000×3000のまま保持し、GPU側の最大辺を4096へ制限する。
星空のRGBA8容量はmipmap込み約42.7MiB。古いGPUのテクスチャ寸法上限と初期負荷に配慮した設定である。

露光・ACES・Bloom・SMAA、機体の影と補助光、接地陰影をタイトルSceneで調整する。
天体用のシェーダーは太陽とカメラの位置を受け取る。これらは美術上の設定であり、ゲームの生産計算ではない。
30fpsと倍率上限を設定したことだけで、Android実機での性能達成とはしない。

## ゲーム内の全球と近接表示

惑星マップのBaseSceneでは地球/火星を採用済みモデルへ置換し、同じHDR太陽を周辺に表示する。
全球モデルの根は地理座標と一致させ、タイトルの撮影用回転を適用しない。
完成した火星施設のsnapshotはpresentationで既存と同じ写像を使う。別の進行式を描画へ導入しない。
既存の都市と選択マーカーを維持し、火星の都市の地盤はMOLA標高へ合わせる。
地球/火星の画像と地形は生存Scene間の弱参照cacheで共有し、光や雲の材質は各Sceneで独立する。
太陽だけの利用でESO全天画像を読み込まない。惑星切替やzoomで画像/地形を再生成しない。
近接した都市開発は別のCitySceneへ移る既存境界を維持し、現在のトゥーン箱庭を残す。月は旧モデルを維持する。

## セーブ進捗の反映と境界

`presentation/title_scene_data.dart`がGameStateを読み取り、
`rendering/title_scene_snapshot.dart`の値へ写像する。描画からdomainへの依存は追加しない。
完成した火星の地区/施設と居住人口に応じて、拠点・無人設備・灯り・限定的な緑や薄雲を重ねる。
研究の解放だけ、地球/月の施設、建設予約中のものを完成した火星へ反映しない。
旧形式の居住と地区の二重計上を避け、休止施設の実体は残す。

現行ゲームには全球の気温・気圧・大気の保存値がない。
色・大気光・薄雲は居住/温室/現地の水・ガス設備を根拠にした**タイトル限定の未来の印象**。
全球の環境計算や呼吸可能判定、新報酬、全球ED、復元、周回のルールは追加しない。
正式な環境状態が実装された場合は同じsnapshotへ接続する。
保存形式、content版、費用、期間、既存の解放条件を変更しない。

## ビルドと素材

Flutter 3.47.7 / Dart 3.13.5 / FlutterScene 0.24.3を維持し、
build hook用に`hooks: 2.0.2`を固定採用する。`hook/build.dart`で
`buildScenes`と`buildMaterials`を呼び、GLBと`.fmat`を対象環境のScene素材・シェーダーへ事前変換する。
Dartのアプリコードを自動生成する仕組みではない。

画像、標高、変換済みScene、シェーダーは配布物へ同梱し、ゲーム起動時にNASA/ESOへ取得しにいかない。
原GLBと変換済みのScene binaryはアプリへ二重同梱しない。
MROは元GLBが約4MB、変換後のScene binaryが約39MBで、配布物では後者を使う。
星空・惑星・機体・ポスト処理を合わせたAndroidのピークメモリは未測定で、元GLBの容量から推定しない。
通常ビルド・素材の再生成・検証の入口は[開発手順](development.md#タイトルの素材とbuild-hook)を参照する。

## 検証の現在地

### 2026-10-26: 遠景の角径を実半径・距離へ合わせる

- 全684テスト・整形・静的解析・依存/内容検査が成功。実角径/圧縮距離/元球半径の換算を含む10件を追加。
- 初回のiOS実GPUは3ケースと後片付けが成功、exit0。実globeのworld半径とカメラ距離からの角径を、
  観測者高度を含む実AUの角径へ4時点で独立照合。地球の元半径3.1、土星環比2.330901も一致。
- 遠景の自己深度で光点が欠けないよう、画面平行の点像面を外接球の手前へ出す。
  実pixelRatioによるsupport幅・高さとこのclearanceの実投影検査を追加した。
  最終iOS実GPU試験も全ケース成功・exit0、PNG12枚と結果JSONを保存した。
  最終Simulatorの初回pipeline警告は最大539ms。実機性能は未測定。
- モデルの形状/画像、主火星の自転/施設、ゲームの全球/近接表示、開始/再開/保存は既存の検査を維持。
- Web release/独立Chromeで大小画面、実描画、動き、クリック/キー開始、既存継続、オフライン/保存維持、外部取得なしが成功。

今回の実表示: [iOS・初期](screenshots/title-angular-ios-pristine.png)、
[iOS・太陽の位相](screenshots/title-angular-ios-phase.png)、
[Web](screenshots/title-angular-web.png)、[Web小画面](screenshots/title-angular-web-small.png)。

詳細と一次資料は[遠景の見かけの大きさ](title-apparent-scale.md)を参照する。
下記の数度の円盤が見えるスクリーンショットは前回の演出サイズの履歴である。

### 前回: 自転する火星と木星・土星

- 整形・静的解析・依存/内容検査と全674テスト成功。
  運動の14件はカメラ座標と自転の分離、Quaternion入力の保持、共通の慣性系、可視時間を検証する。
  環の6件は実測半径、面積・面の向き、半径UV・接空間・継ぎ目、属性とindices、不正入力を検証する。
- NASA元GLBからの再投影を元の三角形UVへ照合し、上下/左右の方向と欠落がないことを確認。
  環の半径とUVは最大差4.8e-7で元meshに一致。画像3点のSHAは素材台帳と一致した。
- iOSの最初の実GPU試験は全3ケースと後片付けが成功し、12枚のPNGを保存。
  その後SDK標準の結果JSONが全画像byteを再保存する段階で作業ディスク不足となった。
  画像は独立PNGとして保存済みなので、共通driverはJSONに画像名とbyte数だけを記録するよう修正した。
  再試験も全ケース成功・exit0で正常終了し、12枚のPNGと1.4KiBの結果JSONを保存した。
- 実GPUの地表と施設のworld変換が動き、地表に対する施設の相対変換は不変であることを検証。
  火星の中心・縮尺・カメラの構図は不変。木星/土星/環の実meshと自転も確認した。
  巨惑星と太陽の撮影は実nodeの画角・火星の遮蔽を確認して行い、固定時刻の空振りを採用しない。
  既存の開始・再開・保存・二重付与なし、全球/近接Sceneの検証も通過した。
- 最終Simulatorの初回pipeline作成警告は最大558ms。30fps上限を実機の性能達成とは扱わない。
- Web releaseと独立Chromeでも成功。大小画面・自転する背景・クリック→OP・既存継続・Enter/Space・
  オフライン/保存維持・外部取得なしを確認し、木星・土星/環と火星を実画像でも確認した。

今回の実表示: [初期の木星・土星](screenshots/title-giants-ios-pristine.png)、
[火星の自転](screenshots/title-giants-ios-rotation.png)、
[地表に付いて回る施設](screenshots/title-giants-ios-facilities.png)、
[巡って現れた地球・太陽](screenshots/title-giants-ios-solar-phase.png)、
[Web](screenshots/title-giants-web.png)、[Web小画面](screenshots/title-giants-web-small.png)。
Android実機・長時間の熱/電池/ピークメモリ・Safari/Firefoxは未確認。

### 前回の即時開始・周回・全球モデル共有の検証

- `mise exec -- bash tools/check.sh`で依存方向・内容検査・整形・静的解析・全665テストが成功。
  UI試験は背景未準備のままTap/Enter/Space/Creditsが使えること、背景だけの900ms fade、
  減motion、開始後/破棄後のready/error、初回保存ゲートを確認する。
- 軌道の11テストで位置・解析速度・接線姿勢・周期の連続性、極端な時刻、火星地形との非交差、
  カメラからの距離、実際の画角と火星遮蔽を含めた可視率を確認。
  旧い低傾斜候補では一部が常時火星に隠れたため、カメラに対して見える傾斜へ調整した。
- iPhone 17 Pro Max / iOS26.1 SimulatorのGPU試験は3ケースと後片付けが全成功。
  最初の独立ケースでNASA3機体のload成功後のtemplate claimが返却済みであることを公開APIで確認。
  デフォルトload成功時だけreleaseし、実nodeが表示中の素材を保持する。失敗したloadの自動解放と重複しない。
  初回OP音声の非同期終了を待ってから試験を終えるようハーネスも整備した。
- 起動直後の開始→OP、新規/発展景観、固定火星/カメラ、約1分後の地球/太陽の出現と明暗変化、
  小さい宇宙機、背景復帰/再起動・保存・報酬の二重付与なしを実GPUで確認。
- 全球Earth/Marsのリアルモデル、緯度経度と都市ピン、拡大/選択、旧Moon、Earthのトゥーン都市を確認。
  都市はWidgetの存在だけでなく内部SceneViewとfallback表示の不存在を確認する。
- Web releaseと独立Chromeで大小画面・実描画・開始・既存継続・オフライン/保存維持・外部取得なしを確認。
  開始案内が先に出るため、描画撮影のハーネスは画面下部の火星の実画素を待ち、黒背景を描画成功と扱わない。

現在の配信前証拠: [読込中の即時タイトル](screenshots/title-web-loading.png)、
[初期の昼側](screenshots/title-ios-pristine.png)、[巡って現れた地球と太陽](screenshots/title-ios-orbital-phase.png)、
[ゲームの全球Earth](screenshots/title-ios-game-earth.png)、[全球Mars](screenshots/title-ios-game-mars.png)、
[近接の都市](screenshots/title-ios-game-city-toon.png)。
Android実機・長時間のGPU負荷/メモリ/熱/電池・故障注入は未実施。所有の解放を、実機メモリ計測と混同しない。

### 前回のモデル採用版の検証履歴

初稿では全648テスト・静的解析・Web/iOSタイトル試験が成功したが、その後にユーザーが
造形と星空の品質不足を指摘した。648件の結果は**作り直し前の初稿**の記録であり、
現在の実測素材・シェーダー構成の最終検証結果へ引き継がない。

作り直し後は、次の確認が一度成功している。

- ネイティブの`integration_test/title_screen_test.dart`で、iOS Simulatorの実GPU読込、
  新規/発展fixture、固定カメラ/火星と動く星空/機体、OP前の順序、既存継続、
  背景復帰・再起動、GameEngineとの一致と完了済み受注の二重付与なしを確認。
- Web releaseと独立Chromeの`tools/title_smoke.cjs`で、1440×810/568×320の表示、
  待機中の動き、初回の資金保護、クリック→OP入口、既存世界のEnter/Space、
  オフライン再開、同じworldId、外部取得なしを確認。
- 原素材の公式出典、利用条件、寸法とチェックサムを確認。天体の標高/画像の座標方向、
  宇宙機の埋込画像・形状・材質・外部URI非使用を素材担当の検査で確認。

現在の素材・シェーダー構成で、`mise exec -- bash tools/check.sh`が成功した。
依存方向・研究/施設の検証・整形・静的解析と**全652テスト**を通過した。
衛星の姿勢・反射光と4096px星空を反映した最終構成でも、Web releaseと同じスモークが成功。
iPhone 17 Pro Max / iOS 26.1 Simulatorで最終のGPU通し試験が成功し、5枚を更新した。
カメラ/火星の固定、実際のsky shaderの回転、地球/衛星の動き、OP前の順序、既存継続、
背景復帰/再起動と保存・二重付与なしを確認。通常のユーザーセーブは使っていない。
素材台帳の10ファイルのSHA、宇宙機manifest、埋込画像、配布物のraw GLB非同梱も独立検査で一致した。

実表示: [iOS・無人](screenshots/title-ios-pristine.png)、
[iOS・発展後](screenshots/title-ios-developed.png)、[iOS・航行](screenshots/title-ios-passage.png)、
[Web](screenshots/title-web-pristine.png)、[Web小画面](screenshots/title-web-small.png)。
撮影用の発展fixtureは、通常時間での到達や全球居住の実証ではない。

縮小プレビューで文字欠けを疑い反映を一時保留したが、元PNG全5枚のタイトル8字の
範囲・白画素量が一致し、原寸確認とOS側の撮影でも欠けは再現しなかった。
撮影処理を省いた比較試験も成功。未確認の描画エンジン不具合と断定せず、アプリへの回避策は追加しない。

未実施: Android/iOS実機のフレーム時間・起動待ち・熱・電池・GPUメモリと長時間稼働、
端末上での描画初期化失敗の故障注入、Safari/Firefox。初稿では初回のシェーダー生成に
約2.48秒の停止警告があった。最終Simulator試験でも初回pipeline作成に最大790msの警告があり、
現在の素材構成での実機起動時間は未測定。

## 反映と次の確認

### 遠景の実角径への反映（今回）

全684テスト、Web/Chrome、最終iOS実GPUと結果保存を確認し、develop→mainの順に反映する。
確定HEADのCI・差分・CLEANを確認し、内部配信は配信先の状態とbuild/commit/runを照合する。
確定記録は両PR本文とローカルdocsへ追記し、記録だけの追加main pushはしない。

### 前回の火星の自転と木星・土星の反映

全674テスト、Web/Chrome、iOS実GPUと結果保存まで確認後、develop→mainの順に反映した。
[PR #52](https://github.com/yakitama5/mars-terraforming/pull/52)の確定HEAD
`648ea0de2bd2a28be7908eab9a7d65d3a97d1afe`で全4check成功・CLEAN後、
develop `10152bb5507a1ac9e4ea4b7c57cc5bedf7c610e0`へ反映した。全ファイルtreeは検証featureと一致。
[PR #53](https://github.com/yakitama5/mars-terraforming/pull/53)も全6check成功・CLEAN後にmainへ反映した。
main `402ff2cc4461b0ed2650b9f276ad7ddd8525db79`と検証feature/developの全ファイルtreeが一致。
mainの[Prototype run40264062532](https://github.com/yakitama5/mars-terraforming/actions/runs/40264062532)と
[Pages run40264062404](https://github.com/yakitama5/mars-terraforming/actions/runs/40264062404)が全job成功。
各headと公開deployment.jsonのmain/develop/runも上記SHAと40264062404に一致。
公開通常版・試遊版で独立Chromeのタイトル実描画・大小画面・動き・開始/継続・オフライン/保存試験が成功した。
公開試験は通常版`mars_terraforming.save.mars-terraforming-main_normal`、
試遊版`mars_terraforming.save.mars-terraforming-develop_development`を指定する。
初回の試遊版検証はローカル用のkeyを誤指定して保存の取得で失敗し、正しいnamespaceで再実行して成功した。
[内部配信run40264062399](https://github.com/yakitama5/mars-terraforming/actions/runs/40264062399)も全4job成功。
headは上記main全SHAと一致。run15/attempt1の両配信記録を照合した。

- Android **1501**: Play internal/completed/versionCode1501をfresh readで確認。
  recordのplatform・app ID・main全SHA・run・build・配信先が一致。
  確認時刻2026-10-26T03:34:37Z（12:34:37 JST）。artifact12626175769のZIP/API/uploadログのSHA-256が
  `d4388afef167256b36b36fbc29e21a8f8521619859a1e8447c6c9cfcccc24bab`で一致。
  署名材料削除・WIF credential cleanup成功。実機動作は未確認。
- iOS **0.1.0 (15.1)**: CIのfresh照合と独立したApple直GETで
  VALID / IN_BETA_TESTING / expired=false / Internal所属を確認。
  recordのplatform・app ID・main全SHA・run・build・配信先が一致。
  record時刻2026-10-26T03:39:04Z（12:39:04 JST）、独立GETは03:40:27Z。
  artifact12626560361のZIP/API/uploadログのSHA-256が
  `7a408f1f243fbf48c472f9570034ee84e91f1c0ee13998f6bdb85725a3580467`で一致。
  一時keychain/profile/p12/API鍵のcleanupも成功。実機動作は未確認。

次の確認はユーザーによるAndroid1501の実機評価。地表の自転・環の見え方と、
起動/復帰・長時間の負荷/熱/電池を確認する。内部配信の照合を実機性能の検証とは扱わない。
内部配信は配信先の状態とビルド/commit/runを照合する。
配信後の確定記録は両PR本文とローカルdocsへ追記し、記録だけの追加main pushはしない。

### 前回の即時開始・周回・全球モデルの反映（2026-10-26）

[PR #50](https://github.com/yakitama5/mars-terraforming/pull/50)の確定HEAD
`35ba92803d313d11d996ee2775d58fefca4fb6dd`で全4check成功・CLEAN後、
develop `32e17abf4780542e0fbb8ff52f8018426ffe840a`へ反映。
[PR #51](https://github.com/yakitama5/mars-terraforming/pull/51)は全6check成功・CLEAN後にmainへ反映した。
mainは`71e8bbeb9cbf44ab70c658f35b72a44cbf84bb83`。検証したfeatureとtree全体が一致。

- main [Prototype checks](https://github.com/yakitama5/mars-terraforming/actions/runs/40255780393)、
  [Pages](https://github.com/yakitama5/mars-terraforming/actions/runs/40255780263)、
  [Mobile internal distribution](https://github.com/yakitama5/mars-terraforming/actions/runs/40255780307)が全job成功。
  各runのheadが上記main全SHAと一致。内部配信はrun14/attempt1。
- Android **1401**: Play internal/completed/versionCode1401をAPI再取得で確認。
  recordのplatform・app ID・main全SHA・run・build・配信先・UTC時刻が一致。
  確認時刻2026-10-26T01:55:44Z（10:55:44 JST）。artifact12622397884のZIP/API/uploadログのSHA-256が
  `7eeafbeca08f35b532aaeede0dba15140c4b918322c9fcb63ab47a1473c451e0`で一致。
  署名材料削除・WIF credential cleanupも成功。
- iOS **14.1**: Apple実照合でVALID / IN_BETA_TESTING / expired=false / group_member=true。
  record全項目が一致し、確認時刻2026-10-26T01:58:04Z（10:58:04 JST）。
  artifact12622363127のZIP/API/uploadログのSHA-256が
  `10a5d6fb949c0b17cb6ee05619ed453857897c1f5a235cbd325325ad85fd4644`で一致。
  一時keychain/profile/p12/API鍵のcleanupが成功。
- 公開deployment.jsonのmain/develop/runが上記SHAと40255780263へ一致。
  公開通常版・試遊版で独立Chromeの開始/背景/保存/オフライン試験が成功し、
  BaseSceneの準備完了後のsemanticsと実画像で全球地球のGPU表示も確認した。

Android実機と長時間の負荷/熱/電池/ピークメモリはユーザー確認予定。
配信記録の照合を実機での動作確認と混同しない。結果は両PR本文とローカルdocsへ追記し、記録だけの追加main pushはしない。

### 前回のモデル採用版の配信履歴

以下の#48/#49・Android1301/iOS13.1は前回のモデル採用版の配信記録。

2026-10-26、[PR #48](https://github.com/yakitama5/mars-terraforming/pull/48)の
確定HEAD `50a12ad3e0dba176445f01e2387b4330ed0fabe3`で全4チェック成功・CLEAN後、
develop `37317aa394a03007d148ddaff928322486562778`へ反映した。
[PR #49](https://github.com/yakitama5/mars-terraforming/pull/49)でも全6チェック
（flutter 2件、Android、iOS、Pages build/deploy）成功・CLEAN後にmainへ反映した。
mainは`fdbd04f247dfc5f8c4185aed7c511409c87daa59`。
検証したfeatureの全ファイルとmainのtreeが一致することを確認した。

mainの内部配信runは[40213851837](https://github.com/yakitama5/mars-terraforming/actions/runs/40213851837)、
Pagesは[40213851869](https://github.com/yakitama5/mars-terraforming/actions/runs/40213851869)、
Prototype checksは[40213851847](https://github.com/yakitama5/mars-terraforming/actions/runs/40213851847)。
全3 workflowが成功し、内部配信はprepare/checks/android/iosの全4 job成功。
各runのheadが上記main SHAと一致した。

- Android **1301**: Google Play internalの`completed`を新規readで確認後、
  `android-release.json`のapp ID・main全SHA・run・build・配信先を照合。
  検証時刻は2026-10-25T17:05:36Z（2026-10-26 02:05:36 JST）。
  artifact `android-internal-1301`（ID12606514143）の取得ZIPとAPI digestのSHA-256が
  `14108ac4dd45374846c6a49469aa20b7d58a1b233d7e7eb40d6da7ea0d12bff9`で一致。
  Remove signing materialとPost Authenticate to Google Play through WIFが成功し、
  一時credentialの削除ログも確認した。
- iOS **13.1**: Apple実照合ログで`processing=VALID, internal=IN_BETA_TESTING,
  expired=false, group_member=true`。Internal testersへの配信を確認。
  `ios-release.json`のapp ID・main全SHA・run・build・配信先が一致。
  検証時刻は2026-10-25T17:08:23Z（2026-10-26 02:08:23 JST）。
  artifact `ios-testflight-13.1`（ID12606838885）のZIP/API/uploadログのSHA-256が
  `75ab23aebaa0af0d7ccc50be0a6517c149a7ece4ca7a435b805b7ac620ac40ff`で一致。
  一時keychain削除、profile削除を含むlaneと、p12/profile/asc.p8のtempdir削除が成功。
- 公開`deployment.json`のmain/develop/runが上記SHAと40213851869に完全一致。
  公開通常版・試遊版の両方で独立Chromeのタイトル試験が自然終了0。
  大小画面・実3D・クリック→OP入口・既存再開・Enter/Space・オフライン/保存維持・外部取得なしを確認した。

記録だけのmain再pushによる追加配信を避け、配信後の補足はローカル記録とPR本文にも残す。

Android実機での最終試遊はユーザーが行う予定。まず更新されたビルドを確認し、
起動時のタイトル、長めの待機と航行物、再起動と既存セーブ継続、発展した火星の見え方を評価する。
負荷・熱・電池・メモリは、表示の正しさと分けて確認する。
