# タイトル専用素材の出典

2026-10-26。ゲーム内の都市景観とは別に、タイトルと惑星マップの全球は実画像を主にした表現を使う。
ユーザーの「より写実的で、圧倒的な壮大さ」という評価に対応する差し替え。

## 天体

### 火星のカラーと地形

- カラー: [NASA Viking Merged Color Mosaic / ASU配布](https://www.mars.asu.edu/data/mdim_color/)。
  NASA Viking OrbiterのカラーをMDIM 1.0で鮮鋭化した64px/度、元画像23040×11520。
  `large/mars45{n,s}{225,315,045,135}.png` の8分割を正しい順に統合し、
  各5760×5760の画像をLanczosで1024×1024へ縮小して4096×2048へ配置。
  Credit: NASA/JPL/USGS, Arizona State University Mars Space Flight Facility。
- 標高: [NASA MGS/MOLA MEGDR](https://pds-geosciences.wustl.edu/missions/mgs/megdr.html)。
  [megt90n000eb.img](https://pds-geosciences.wustl.edu/mgs/urn-nasa-pds-mgs_mola_topography_derived/meg016/megt90n000eb.img)
  と[正式なラベル](https://pds-geosciences.wustl.edu/mgs/urn-nasa-pds-mgs_mola_topography_derived/meg016/megt90n000eb.xml)。
  5760×2880、符号付きbig-endian 16bit、単位m。取得ファイルの最小-8177m、最大21171mがラベルと一致。
  Credit: NASA/MGS/MOLA Science Team, NASA Planetary Data System。
- 経度0〜360°のMOLAを180°ずらして、カラーの-180〜180°、北→南と整合させる。
  1024×512の標高をbicubicで作り、`MOLA`＋uint16 LEの幅/高さ＋int16 LE標高として同梱。
  メッシュの標高は実測値を1.5倍にした撮影用の誇張。架空の峡谷・火山・クレーターは足さない。
- 法線は同じ実測標高を2048×1024へ縮小し、緯度による1pxの地表距離を考慮して中央差分で作る。
  法線上の勾配は2倍。南北の差分は端でclamp、経度はwrapする。
- 地表の球は192×320分割、61953頂点、122240三角形。位置とUVは同じ緯度経度を参照。
  頂点色は白に固定し、まだらな手続き配色を写真へ重ねない。
  実測Valles Marinerisがタイトルで見えるよう、球全体の撮影姿勢を固定する。

### 地球の昼・夜・独立雲

- 昼: [NASA Blue Marble: Next Generation — Base Map](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/base-map/)、
  [July 2004の5400×2700 JPEG](https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base/july/world.200407.3x5400x2700.jpg)。
  Credit: NASA Earth Observatory; Reto Stöckli, NASA Goddard Space Flight Center。
- 夜: [NASA Earth at Night / Black Marble — Flat Maps](https://science.nasa.gov/earth/earth-observatory/earth-at-night/maps/)、
  [Black Marble 2016 3km](https://assets.science.nasa.gov/content/dam/science/esd/eo/images/imagerecords/144000/144898/BlackMarble_2016_3km.jpg)、13500×6750。
  Credit: NASA Earth Observatory images by Joshua Stevens, using Suomi NPP VIIRS data from Miguel Román, NASA GSFC。
- 雲: [NASA Blue Marble: Clouds](https://visibleearth.nasa.gov/images/57747/blue-marble-clouds/77558l)、
  [cloud_combined_2048.jpg](https://eoimages.gsfc.nasa.gov/images/imagerecords/57000/57747/cloud_combined_2048.jpg)、2048×1024。
  Credit: NASA Goddard Space Flight Center; Reto Stöckli; enhancements by Robert Simmon。
  可視光と極域の熱赤外観測を合成した静的な雲画像。現在の気象ではない。
- 昼夜はLanczosで2048×1024へ縮小しJPEG quality94/subsampling0、雲は元解像度の輝度PNG。
  地球の回転、独立した薄い雲層、太陽方向に合わせた明暗境界、夜側の都市光、海面の反射を描く。
  惑星ごとに太陽への方向を計算する。画面内で大きく見せるため、惑星間距離と見かけの大きさは実縮尺ではない。

### 大気とセーブ進捗

`planet_atmosphere.fmat` は薄い球殻上で、フレネル型の視線角、太陽側の明るさ、
Rayleigh位相関数の形を組み合わせる。平面の外周リングは使わない。
科学計算用の多重散乱や厳密な体積積分ではなく、タイトルの美術表現。

火星の緑・雲・大気色と開発の灯りは既存の保存状態から受け取る美術上のアクセント。
NASA観測画像へ、将来の架空の開発を重ねる。現実の火星環境や全球居住の達成判定を表すものではない。

### 使用条件

[NASA Images and Media Usage Guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)に従い、
出典を明記して使用する。NASA由来の画像・3D用素材は米国では原則著作権対象外だが、
NASAのロゴや識別標章、別途権利表記のある第三者素材まで自由利用と扱わない。
本素材にはロゴや人物を含めず、NASAの推薦・公認を示す表示を行わない。
アプリのMITライセンスがNASA観測データの出典表示を置き換えるものではない。

### 同梱ファイルのSHA-256

`assets/title/planets/` 以下。

| ファイル | SHA-256 |
| --- | --- |
| mars_viking_albedo_4k.jpg | `5a42ac422cf78160fe5c4a52b0e35d27bcd972c6b6bb6afb156d94ef030b6079` |
| mars_mola_normal_2k.png | `5f97c77f81a1474c87db0052bda38dbbec56216b58e7fc3dced10830be41f17e` |
| mars_mola_height_1k.bin | `7b884fe33b6026a3a9552fd207984be6dd7eba50b7177d66af9ccb79c3bfd5de` |
| earth_blue_marble_day_2k.jpg | `c1cc245b8d3e25ef3aec26bdefc85f046c12a4e34d922b5636f62157fb2888fa` |
| earth_black_marble_night_2k.jpg | `e36e968b92a3312536001b9bf08f0f9f920bf833b0f3d4968ec16be5d39b7aad` |
| earth_blue_marble_clouds_2k.png | `9463a59636bcfd4dd24a51717d6a72dedfa3833aa7e0dc1c5758218a0c2c1104` |

### 検証範囲と制約

元画像の寸法、MOLAの型・値域、座標方向、同梱ファイルの読戻しとハッシュを確認。
元の取得ファイルは一時作業場所に保持し、アプリには縮小した6ファイルだけを同梱する。
素材の基底GPU容量は約64MiB、ミップ付きで約85.3MiB。初回の画像デコード・転送・シェーダー作成と、
実機の描画時間・メモリ・電池・長時間の安定性は、ビルド/実描画の検証と区別する。
シェーダービルド、Web/iOS描画、Android実機性能の最終結果はタイトル画面の実装記録へ残す。
