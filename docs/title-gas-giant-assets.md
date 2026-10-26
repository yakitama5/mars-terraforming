# タイトルの木星・土星素材

2026-10-26。既存の火星・地球・太陽・宇宙機の品質と保存仕様を保ち、
タイトルだけに木星・土星を追加するための素材台帳。

## 出典と利用条件

本体の雲画像と環のRGBAプロファイルは、NASA Scienceが公開する次のモデルから抽出した。

- [Jupiter 3D Model](https://science.nasa.gov/resource/jupiter-3d-model/)
- [Saturn 3D Model](https://science.nasa.gov/resource/saturn-3d-model/)

両ページのクレジットは **NASA Visualization Technology Applications and Development (VTAD)**。
ゲーム内Creditsにもこの表記を含める。NASAがゲームを推奨・承認しているとは表示しない。
NASAのロゴ・人物画像は使用していない。

[NASA Images and Media Usage Guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/) は、
テクスチャ・polygon dataを含むNASAの3D用素材は、米国では一般に著作権の対象ではないと説明し、
NASAへの出典表示、推奨と誤認させないこと、別途表示された第三者権利を守ることを求めている。
採用ページにはVTAD以外の権利者や追加の制限表示はなかった。
本作品のMITライセンスへ置き換えず、NASAの素材条件とクレジットを維持する。

これはNASA公式の可視化用テクスチャであり、元の観測機・撮影日・加工手順が
個別画像へ付記された科学データセットではない。雲の現在位置・風速・分光特性の実測値とは扱わない。

## 原本

取得した元GLBは再配布物のサイズを抑えるためアプリへ含めず、必要な画像だけを抽出した。
GLBのgeometryをそのまま使わず、既存の球メッシュと独立した環メッシュへ適用している。

| 元データ | 直接URL | bytes | SHA-256 |
| --- | --- | ---: | --- |
| Jupiter GLB | [Jupiter_1_142984.glb](https://assets.science.nasa.gov/content/dam/science/psd/solar/2023/09/j/Jupiter_1_142984.glb) | 11,479,456 | `8edc4e9b88b73ca1b125a258f0ecaef7fc6494a7cadda37704af459a119f4870` |
| Saturn GLB | [Saturn_1_120536.glb](https://assets.science.nasa.gov/content/dam/science/psd/solar/2023/09/s/Saturn_1_120536.glb) | 5,476,584 | `8dbfde533b13e938408d8aded1d1ce48a084806233f67775371d83013dba7d38` |

Jupiterの`images[0]`（name `jupiter_diff.jpg`、実体PNG）は4096×3072 RGBA。
Saturnの`images[0]`（`saturn_diff.jpg`、実体PNG）も4096×3072 RGBA、
`images[1]`（`saturn_rings_25sat_outterRings.png`）は4096×16 RGBAだった。
本体画像は2:1経緯度画像ではなく、上下極の面を含む4:3 cube atlas。
そのまま球へ巻くと白い空白や継目が現れるため、以下のUV変換を行った。

## アプリ内画像と変換

| ファイル（assets/title/giants/） | 画像寸法 | bytes | SHA-256 |
| --- | --- | ---: | --- |
| `jupiter_vtad_2k.jpg` | 2048×1024 RGB | 792,898 | `991ceeb3367f42c2cb34b5f2eb20a5a125ac39e8a9d47f303e2efe8b7af0af30` |
| `saturn_vtad_2k.jpg` | 2048×1024 RGB | 378,215 | `84d76932e3852d2998bc743512c799e4cb7cc4349c1080fa67b001282300beec` |
| `saturn_rings_vtad_2k.png` | 2048×128 RGBA | 5,627 | `9f4dab45476b8c00279ec49822f68c76214ea97b6ecef15030e61cd0604723c5` |

本体は元GLBの1649頂点・三角形・TEXCOORD_0を読み、Yの扁平率を除いた
方向ベクトルでcubeの6面を識別。各面の1024×1024 lookupへ元UVを
三角形のbarycentric補間で写し、2:1経緯度の各画素方向から元画像をbilinear samplingした。
Float32の境界誤差で面の外端が1画素未満欠ける箇所は2画素のedge extensionで補い、
面の内部に未充填画素がないことを確認した。追加の彩度・色相・シャープ化はしていない。
JPEG quality=95、chroma subsamplingなし。北が画像上、経度-180°が画像左。
元cube atlasのUVを経由するため、架空の帯模様や生成画像へ置き換えていない。

環は元のRGBとalphaを保ちLanczosで2048×128へ変換した。
周方向の変化を追加したものではなく、同じ半径方向プロファイルを縦に保持している。
高さを128にしたのは、FlutterSceneのmip数が画像の小さい辺にも制限されるため。
元の16pxのままだと遠景で細い筋がちらつきやすくなる。

再生成スクリプトは `tools/prepare_title_gas_giants.py`。
Pythonの開発用画像処理環境（検証時NumPy 2.3.5 / Pillow 12.3.0）で次のように実行する。
Flutterアプリの依存には追加していない。

```sh
python3 tools/prepare_title_gas_giants.py
```

固定URLから原GLBを取得し、上記SHAを確認してから画像を抽出する。
変換画像3点も固定SHAと照合し、全点一致してから出力先へ保存する。
原本やencoder差による不一致時は既存の採用画像を変更しない。
既存cacheで通信を行わず再生成する場合は、以下のように別の出力先を指定できる。

```sh
python3 tools/prepare_title_gas_giants.py \
  --source-dir /private/tmp/mars-gas-giant-sources \
  --output-dir /private/tmp/mars-gas-giant-regenerated \
  --no-download
```

## 形状・光・環の境界

木星・土星本体の赤道半径は1、回転軸はlocal +Y。
極半径比は [Jupiter Fact Sheet](https://nssdc.gsfc.nasa.gov/planetary/factsheet/jupiterfact.html) の
66854/71492と、[Saturn Fact Sheet](https://nssdc.gsfc.nasa.gov/planetary/factsheet/saturnfact.html) の
54364/60268を使用する。球meshはradius:1を明示し、globe子のYscaleで一度だけ扁平化する。

環はXZ平面のannulusで、半径は元VTAD ring meshを赤道半径500で割った
**内縁1.232301・外縁2.330901**。UV.uを内縁0→外縁1、UV.vを周方向とする。
これは元画像との対応範囲であり、[NASAの環の諸元](https://nssdc.gsfc.nasa.gov/planetary/factsheet/satringfact.html) の
個々の半径境界を科学測定の精度で再現したとは扱わない。主にC〜F環を表し、D/G/E環は追加しない。

- opaqueな球のdepthで環の奥側を隠し、環は両面alpha描画。環自身を重複した表裏meshにしない。
- 球から光源へのrayと環平面の前方交差で、環のalphaを光学厚へ換算した影を本体へ落とす。
- 環から光源へのrayと軸比(1, polarRatio, 1)の楕円体の最近接距離で、本体の影を環へ落とす。
  いずれも光源より手前の交差だけを対象にし、root逆変換とY扁平率を二重適用しない。
- 環の観測側/照明側、見る角度、光学厚から反射と透過を簡略化して描く。
  alpha=0の場所は本体へ影を落とさない。ごく薄いambientは夜面を読めるようにする映像上の仮定。
- shaderのpenumbra、光学厚係数0.45、sunlight/ambientはタイトルの既存ACES露出へ合わせる描画値。
  有限の太陽円盤・粒子単位の多重散乱・実測のphotometryを解いた物理シミュレーターではない。

遠い惑星が既存shadow atlasの範囲から外れても自己/相互影が失われないよう、
この影は各専用shader内で解析する。頂点由来の局所位置をfragmentへ渡し、
大きいworld座標から毎pixelで中心を引く際の精度落ちを避けた。
`updateView(sunPosition:, cameraPosition:)` はrootの位置・傾斜・自転を反映した後に呼ぶ。

## 資源と検証範囲

追加画像は圧縮計1,176,740 bytes。GPUのRGBA8 baseは17 MiB、mip込み概算22.7 MiB。
木星/土星は8385頂点の球bufferを共有し、環は514頂点/512三角形。
画像とgeometryは生きているSceneのモデルが保持し、静的cacheはWeakReferenceのみ。
同時ロードのFutureは完了/失敗時に解放し、材質パラメータはSceneごとに独立する。
フレーム中に画像ロードやgeometry再生成はしない。

素材の原寸確認・再投影の未充填検査・ハッシュ確認は実施。
shaderコンパイル、全体解析/全674テスト、iOS GPUの初期表示・自転・環の遮蔽/影を
統合担当が直列で確認した。Webと配信の最終記録は[タイトル画面](title-screen.md)を参照する。
実機負荷・電池・長時間GPUメモリは別途確認対象。
