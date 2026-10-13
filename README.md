# 火星開発計画

地球の都市・産業で資金を作り、共用設備を研究・製造・輸送へ配分して、
火星の複数都市へ進むFlutter / FlutterSceneの戦略試作です。
球体の惑星、各都市25区画の配置・隣接効果、3系統の研究を操作できます。
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

1. 「惑星マップ」で都市を選び、「都市開発」で区画の地形・隣接効果と見積もりを比較します。
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

Sitesの[所有者向け非公開試遊URL](https://mars-terraforming-playtest.yakuran01.chatgpt.site)へ配置済みです。
通常時間でのビルド、保存仕様、ブラウザ自動検証、配布手順は
[Web試遊ガイド](docs/web-preview.md)を参照してください。

## 資料と検証

- [GitHub Pagesとmain/developの運用](docs/github-pages.md)
- [都市・惑星の戦略試作と改善記録](docs/strategy-prototype.md)
- [企画書](docs/game-design.md)
- [起動・操作・検証・開発状況](docs/development.md)
- [決定事項・仮値・保留事項](docs/decisions.md)
- [Web試遊ガイド](docs/web-preview.md)

検証: `mise exec -- bash tools/check.sh`。
Google連携・全球環境・ED・周回・火星復元は今後の段階です。
