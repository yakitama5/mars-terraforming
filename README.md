# 火星開発計画

地球の都市・産業で資金を作り、共用設備を研究・製造・輸送へ配分して、
火星の閉鎖居住拠点へ進むFlutter / FlutterSceneの小さな試作です。
iOS先行・Android後発、横画面・日本語・完全オフラインの方針を維持しています。
PCで操作を試せるWeb版も用意しました。UIと数値は仮仕様です。

## ブラウザで遊ぶ

- [main：通常版](https://yakitama5.github.io/mars-terraforming/)
- [develop：開発 +5分付き試遊版](https://yakitama5.github.io/mars-terraforming/develop/)

Chrome推奨。両方とも公開済みで、保存データは別々です。
まずdevelopで設備の予約・順番変更を試せます。初回の読み込みとキャッシュ完了後はオフラインでも再開できます。
main/developのpushを起点に、両方のビルドをまとめて更新する設定です。
手動での再実行方法と検証状況は [Pages運用ガイド](docs/github-pages.md) に記録しています。

## iOSで起動

```sh
mise install
mise exec -- flutter pub get --enforce-lockfile
mise exec -- flutter run --dart-define=DEV_TOOLS=true -d <iOS-device-id>
```

`DEV_TOOLS=true` で専用の保存枠と「+5分」ボタンを使えます。
通常プレイではdart-defineを省きます。初回は外部受注を予約し、
研究→居住キット→火星輸送→居住区建設を予約、初輸送後に居住方式を選んでください。
「設備・進行」で設備ごとの進捗・予約・停止理由を確認し、前後ボタンで
外部受注と自分の開発の順番を変更できます。支払済みの現在の1回は継続します。

## このPCのブラウザで試す

ChromeとWebGL2を利用します。FlutterSceneによる3D表示もWeb版で動かします。

```sh
mise exec -- bash tools/build_web_preview.sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory site-preview/dist
```

[ローカル試遊画面](http://127.0.0.1:8765/)を開いてください。
Web試遊は既定で開発用の別セーブと「+5分」を使います。
初回にアプリ一式を読み込んでキャッシュした後は、同じURLでオフライン再読み込み・プレイができます。
ブラウザ保存はiOSと別で、ブラウザのサイトデータ削除やプライベートモードでは失われます。

Sitesの[所有者向け非公開試遊URL](https://mars-terraforming-playtest.yakuran01.chatgpt.site)へ配置済みです。
通常時間でのビルド、保存仕様、ブラウザ自動検証、配布手順は
[Web試遊ガイド](docs/web-preview.md)を参照してください。

## 資料と検証

- [GitHub Pagesとmain/developの運用](docs/github-pages.md)
- [企画書](docs/game-design.md)
- [起動・操作・検証・開発状況](docs/development.md)
- [決定事項・仮値・保留事項](docs/decisions.md)
- [Web試遊ガイド](docs/web-preview.md)

検証: `mise exec -- bash tools/check.sh`。
Google連携・全球環境・ED・周回・火星復元は今後の段階です。
