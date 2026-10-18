# Dear Mars

地球の都市・産業で資金を作り、共用設備を研究・製造・輸送へ配分して、
火星の複数都市へ進むFlutter / FlutterSceneの戦略試作です。
球体の惑星から円形に切り出した都市の3D地形を開き、各都市25区画の配置・隣接効果、3系統の研究を操作できます。
施設を選び、地形上の六角タイルで立地と隣接効果を比較して予約します。
住宅街・研究施設群・工場・発電設備が同じ地図へ現れ、隣接する地区が道路でつながります。
地球では川と橋、火星では枯れ谷を眺めながら、箱庭の全景と市街への接写を切り替えられます。
上部の国力HUDと下部の開発指令から、地図・研究・設備・機関運営を操作します。
住宅は基本5分から。既存地区の増強と別都市への展開を「比較に保存」で比べられます。
都市基盤研究から住宅Lv.2や短い応用研究を選べ、設備画面の「予約の見通し」で離席後を試算できます。
画面下の「ガイド」から最初の1時間の手引きと状況別Tips、「通知」から離席中を含む完了履歴を確認できます。
予約には所要時間・未払い費用を表示し、「次に実行」で優先順を変更できます。
「機関運営」でドル表記の資金と各指標を確認し、研究者・工業員の配分や技術提携・支援を選べます。
iOS先行・Android後発、横画面・日本語・完全オフラインの方針を維持しています。
PCで操作を試せるWeb版も用意しました。UIと数値は仮仕様です。

## ブラウザで遊ぶ

- [main：通常版](https://yakitama5.github.io/mars-terraforming/)
- [develop：時間送り付き試遊版](https://yakitama5.github.io/mars-terraforming/develop/)

Chrome推奨。両方とも公開済みで、保存データは別々です。
まずdevelopで都市の配置・研究投資・設備の順番変更を試せます。初回の読み込みとキャッシュ完了後はオフラインでも再開できます。
main/developのどちらへpushしても、両方のビルドをまとめて自動更新します。
両ブランチで実pushから配信まで確認済みです。復旧手順と検証記録は [Pages運用ガイド](docs/github-pages.md) に記録しています。

## iOSで起動

```sh
mise install
mise exec -- flutter pub get --enforce-lockfile
mise exec -- flutter run --dart-define=DEV_TOOLS=true -d <iOS-device-id>
```

`DEV_TOOLS=true` で専用の保存枠と「+5分」「+1時間」「+1日」を使えます。
通常プレイではdart-defineを省きます。時間送りは通常セーブへ影響しません。

1. 「惑星マップ」で都市を選び、「都市開発」で施設→六角タイル→建設予約。地図上の「保存」「比較」から、別の区画/都市と費用・工期・収支を比べられます。
2. 「設備・進行 → 製造・受注」で資金を作り、「研究ツリー」で生命維持を実証します。
3. キット製造と火星輸送を予約。工場の無期限受注より製造を前へ動かすと、支払済みの1回の後に着手します。
4. 初輸送後、火星の居住方式を選び、アルカディアの区画へ居住地区を建設します。
5. 工業・宇宙港・温室や別都市へ投資し、次の研究の実証条件を満たしていきます。

研究費・工期・効率上限・区画数は仮値です。建設完了時24人が入居する簡略表現で、
独立した移住操作や全球の屋外居住は未実装です。設計・調整・検証記録は
[都市・惑星の戦略試作](docs/strategy-prototype.md)を参照してください。

## このPCのブラウザで試す

ChromeとWebGL2を利用します。FlutterSceneによる3D表示もWeb版で動かします。

```sh
mise exec -- bash tools/build_web_preview.sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory site-preview/dist
```

[ローカル試遊画面](http://127.0.0.1:8765/)を開いてください。
Web試遊は既定で開発用の別セーブと時間送りを使います。
初回にアプリ一式を読み込んでキャッシュした後は、同じURLでオフライン再読み込み・プレイができます。
ブラウザ保存はiOSと別で、ブラウザのサイトデータ削除やプライベートモードでは失われます。

初期版の[所有者向けSites試遊URL](https://mars-terraforming-playtest.yakuran01.chatgpt.site)も残しています。
今回の都市・惑星の改善版は、上記のGitHub Pagesで公開します。
通常時間でのビルド、保存仕様、ブラウザ自動検証、配布手順は
[Web試遊ガイド](docs/web-preview.md)を参照してください。

## 資料と検証

- [製品としての操作性・文字量・導線の改善](docs/product-usability.md)
- [最初の1時間のガイド・状況別Tips・完了通知](docs/first-hour-guidance.md)
- [プロジェクトメモリ：現在の好み・方針・再開時の要約](docs/project-memory.md)
- [円形の箱庭・川・土の断面と最新の検証](docs/circular-terrarium.md)
- [都市の接写・質感・投影影](docs/city-diorama.md)
- [六角地形へ広がる街区・施設選択](docs/district-landscape.md)
- [地域3D地形・建設反映・指令画面の初期実装](docs/terrain-command-ui.md)
- [序盤の並行開発・人員配分・提携](docs/agency-development.md)
- [序盤の増強選択・予約の見通しの検証](docs/early-development.md)
- [都市投資・序盤5分建設の基礎調整](docs/investment-pacing.md)
- [GitHub Pagesとmain/developの運用](docs/github-pages.md)
- [都市・惑星の戦略試作と改善記録](docs/strategy-prototype.md)
- [企画書](docs/game-design.md)
- [起動・操作・検証・開発状況](docs/development.md)
- [決定事項・仮値・保留事項](docs/decisions.md)
- [Web試遊ガイド](docs/web-preview.md)

検証: `mise exec -- bash tools/check.sh`。
Google連携・全球環境・ED・周回・火星復元は今後の段階です。

## ライセンス

本プロジェクトは [MIT License](LICENSE) で公開しています。
第三者のライブラリ・素材には、それぞれのライセンスが適用されます。
同梱のNoto Sans JPは [SIL Open Font License 1.1](assets/fonts/OFL.txt) に従います。
