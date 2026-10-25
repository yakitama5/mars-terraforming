# タイトルの宇宙機素材

2026-10-26。タイトルの従来の手作り機体では品質が不足しているというユーザー評価を受け、
NASAが公開する詳細な実モデルへ置き換える。タイトル専用の視覚素材であり、ゲーム内の
機体性能・建設・研究・輸送費・保存形式は変更しない。

## 採用した原素材

NASA公式の [3D Resources](https://science.nasa.gov/3d-resources/) と
[NASA-3D-Resources](https://github.com/nasa/NASA-3D-Resources) を取得元とする。
取得元コミットは `11ebb4ee043715aefbba6aeec8a61746fad67fa7` に固定した。

| 素材 | 原モデル | クレジット | 造形・画像 |
| --- | --- | --- | --- |
| 火星探査機 | [Mars Reconnaissance Orbiter (MRO) (A)](https://science.nasa.gov/3d-resources/mars-reconnaissance-orbiter-mro-a/) | NASA / NASA 3D Resources。個人の作者名は当該ページで確認できていないため推定しない | 124,062三角形、6メッシュ、11材質、1600×1600色アトラス。展開した太陽電池、断熱箔、通信皿、支柱、観測機器を含む |
| ロケット | [Saturn V](https://science.nasa.gov/3d-resources/saturn-v/) | NASA/Michael D. Carbajal | 34,814三角形、22メッシュ、13材質、1000×1000色アトラス4枚。段構成、ノズル、外部配管、外板、安定翼、上部機体を含む |
| 小惑星 | [1999 RQ36 asteroid (Bennu)](https://science.nasa.gov/3d-resources/1999-rq36-asteroid/) | 形状: NASA/Christopher R. Meaney。画像: NASA/Goddard/University of Arizona | 18,240三角形のNASA公開形状へ、1041×521の全球実測モザイクと控えめな補助normalを埋め込む。派生GLBは2.45MB |

Saturn Vは歴史上の打ち上げ機の造形をタイトルの航行イメージとして使う。
実在のSaturn Vがその姿のまま火星周回を行う、火星へ人を運んだ、という説明にはしない。
MROの機器配置はNASA公開モデルに従うが、タイトルの縮尺・速度・軌道は演出用である。

Bennuの色画像は [Bennu in Unprecedented Detail](https://www.nasa.gov/image-article/bennu-unprecedented-detail/)
で公開された全球モザイクの縮小版。NASAは2019年3〜4月に取得した2,155枚のPolyCam画像を
合成したものと説明している。本作は球面UVで配置し、正確な地物の位置合わせや色校正までは行わない。
採用した軽量形状の観測版・解像度は公開ページで確認できないため、最新OLAレーザー実測形状と同等とは扱わない。
[NASA SVS 5069](https://svs.gsfc.nasa.gov/5069/) にはOLA v20/v21の詳細形状があるが、
今回の環境では配布hostへの接続がタイムアウトし、取得できなかった。

比較した [MRO (C)](https://science.nasa.gov/3d-resources/mars-reconnaissance-orbiter-mro-c/) は
14,753三角形で、より細かな機器が残るAを選んだ。
[SLS Block 1](https://science.nasa.gov/3d-resources/space-launch-system-block-1/) は大きな
MAX等のアーカイブが中心で、直接読み込めるGLBが取得元にないため今回採用しない。

## 利用条件とクレジット

[NASA Images and Media Usage Guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)
は、3Dモデルのポリゴン・テクスチャを含むNASAメディアの一般的な利用条件を定めている。
NASA出典の表示、推薦を示唆しないこと、NASA識別標章や第三者著作物の条件を別に扱うことを維持する。
本作MITをNASA原素材へ適用せず、素材フォルダの `NOTICE.md` にクレジットを置く。
リポジトリ全体の `meta.json` にはNASA Open Source Agreement 1.3という記載もあるが、
このモデルを本作MITのソフトウェア資産へ読み替えず、上記のNASAメディアとして出典・変更を明示する。

原アトラスとBennu全球画像を目視し、NASA Insignia/Logotypeは見つからなかった。
Saturn V原素材のUSA/UNITED STATES表記・米国旗は保持した。
NASAによる本作の承認・推薦を意味する文言や、NASAロゴを冠した商品表示は追加しない。
NASA職員や宇宙飛行士の肖像、商用配布サイトからの再配布素材は使用していない。

## 本作での変更

`prepare_assets.py` は原GLBのSHA-256を検証した後、glTFの材質と補助normalだけを変更する。
MRO/Saturn Vの頂点、法線、インデックス、UV、色アトラス、ノードの機器配置は原データを保持する。
Bennuは原三角形の各頂点座標・法線を保持し、球面UVの継目だけ頂点を複製して画像を貼る。

- MROの金色断熱箔はmetallic 0.76 / roughness 0.40、銀色支柱・ノズルは材質別に設定する。
  太陽電池と塗装・光学機器を同じ金属値へ置き換えない。
- 断熱箔の色アトラスから1024×1024の微細normalを作り、箔だけへ強度0.30で適用する。
  これは照明でしわを補う演出であり、NASA測定の凹凸データではない。
- Saturn Vは塗装面と金属面のmetallic/roughnessを分ける。原色アトラスは改変しない。
- MROの原Draco圧縮・埋込画像を保持する。原GLBの画像はすべて端末内に含まれ、外部URIを持たない。
- Bennuは元の一様色へ実測モザイクを追加し、非金属/roughness 0.96とする。
  画像から作ったnormalの強度は0.18。原形状に存在しない岩を幾何形状として追加しない。

`TitleSpacecraftModels.load()` は `fs.loadScene` でビルド済み素材を読み込む。
原点からずれた原モデルをAABB中心へ戻し、MROは最大幅6、Saturn Vは長さ8へ等比で整える。
MROのZ方向の長い翼を横へ見せるため、内部の姿勢だけY軸90度回転する。
Bennuは最大幅2へ整える。
外側の根は原点・等倍・回転なしとし、タイトル側が軌道とスケールを適用する。
原GLBとSceneの生成binaryをアプリへ二重同梱せず、build hookの生成物を実行時に使用する。

## チェックサムと再生成

| ファイル | 原素材SHA-256 | 派生素材SHA-256 | 派生容量 |
| --- | --- | --- | --- |
| `nasa_mro.glb` | `b195c566d227dec8e42ca2fafcc2a8cc26a127e04ed577e4b9515199d2002d9e` | `3e7c81d358d46e5851226b0d145c8aed9f57ed167e4ad0b3e7a2a09065b47df0` | 3,980,612 bytes |
| `nasa_saturn_v.glb` | `6c44497bce54ee0b09d0edb8e33a6f484762a320dab1c54b383e434f5bba06b5` | `b9b55011074b60b6d42e0fb05b02bc86b802f3cb60479ae6bec5614ba9051afb` | 927,312 bytes |
| `nasa_bennu.glb` | `644af15678447df90c2d9e85674809c7fc70f439e0865418aa6618a8483b7958` | `6415dd543e59bf2b1238d03727e5f7b25f0f856c173e66540a66eda219799f5a` | 2,447,592 bytes |

Bennuの`asset.extras.changes`も、原頂点/法線の保持、継目用の頂点複製と球面UV、実測モザイク・
補助normalの追加、PBR調整を示す専用文へ更新した。固定キャッシュから再生成し、
MRO/Saturn Vの全バイトとBennuのBINチャンクが変更前と一致することを確認した。
BennuのJSONはこの変更説明以外を変えていない。

Bennu実測モザイクの原画像SHA-256は
`cc2d73cf23ca87a998db8171f67a56aec09ff94e5acbe1630108471236eeb197`。
取得元はNASA本体の
[縮小版PNG](https://www.nasa.gov/wp-content/uploads/2023/03/bennu_global_mosaic_reduced_size.png)。
原画像のピクセルは派生GLBへそのまま埋め込み、補助normalは別の画像として追加する。

原素材を再取得する処理は開発用で、ゲーム起動時には実行しない。
PillowとNumPyのあるPythonで `assets/title/spacecraft/prepare_assets.py` を実行すると、
固定コミットの原素材を一時キャッシュへ取得してSHAを検証し、派生GLBと
`asset-manifest.json` を再生成する。原GLBの二重保存はしない。

## 確認範囲

実施: NASA一次公開ページ・公式リポジトリと利用条件の確認、原GLBの取得元固定とSHA照合、
glTF 2.0ヘッダー・チャンク長・三角形数・埋込画像・材質・原アトラス/実測モザイクの目視、派生GLBの生成。
原形状・色画像の維持と外部URI非使用は、生成後の構造比較で確認する。

この文書の素材担当作業時点では、アプリ内のGPU読込、照明・露出・構図、iOS/Android実機の
性能・メモリ・長時間稼働は未確認。実際の読込と見た目はタイトル統合後の検証記録へ追記する。
三角形数や原アトラスの細かさだけで、最終画面の品質達成を確定しない。
