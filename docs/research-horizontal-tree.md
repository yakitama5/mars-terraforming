# 横へ深まる研究ツリー

更新: 2026-10-20。小画面対応後の本人評価により、研究の木の配置を組み直す。

## 採用した表示

同じ深さの技術を列ごとの連番で縦に詰める配置を、部分木の配置へ変更する。
研究の深さは左→右。兄弟は自分の子孫も含む帯を持ち、親を子群の中央に置く。
提示された「基礎→初級1/初級2→それぞれの中級1〜4」の形で、枝ごとにまとまりを保つ。

- `ResearchTreeLayout`は画面が渡した発見済み技術だけを使い、前提の最長深さから横位置を決める。
  枝の高さを再帰計測し、兄弟の帯の間を56px、独立した木の間を104px空ける。
  深さ間はカード幅に112pxを加え、幹と分岐のための場所を確保する。
- 既知の独立した木は淡い枠で囲む。幹から角を丸めて枝分かれする線を描く。
  子のいない研究や未発見の将来へ、空きカード・枠・枝線を先に表示しない。
- 複数前提では最も深い実在の親を主枝に選び、同深さなら同じ研究枝を優先する。
  同分野で発見済みの追加AND/OR前提も省かず、枠の外側の余白を通る細い破線で接続する。
  独立研究へ伸びる表示上の幹は、研究の新しい前提条件を意味しない。
- カタログID順と既存の入口順から配置を決め、解放順や保存再読込で兄弟の並びを変えない。
- 自動カメラは0.85倍以上を保つ。新しい親子が同時に収まらない場合は新しい子へ寄る。
  「全体表示」は明示操作として0.01倍まで縮小し、発見範囲の全体を確認できる。
  分類切替は入口へ寄り、詳細を閉じて幅が戻るときは直前の注目技術の付近を保つ。

ゲーム進行・研究前提・RP費用・保存形式の変更は含まない。
Flutter3.47.7 / Dart3.13.5 / FlutterScene0.24.3を使用し、依存の採用版は維持する。

## 検証

- `mise exec -- bash tools/check.sh`成功。依存方向、研究98件と保存・時間分割、Python6件、
  整形、静的解析、Flutter **520テスト**を通過した。
- 新しい配置の6テストで、提示された二段分岐、部分木の非交差、全前提より右の配置、
  入力順の不変性、未知の研究の参照が寸法に影響しないこと、全98技術の矩形非重複を確認した。
  カード1倍/1.4倍を対象とする。
- 小さいペインで右の子へ実ドラッグできることと、自動表示/明示全体表示の倍率を回帰確認した。
  Matrix4のZ軸固定値を倍率として読まないよう、テストは2DのX軸倍率を確認する。
  旧セーブの途中研究が保存順の先頭でも、分類切替で入口研究へ寄る回帰を追加した。
- 最初の全体検証で、木が高くなると従来の全体表示下限0.12倍では端が切れる例を検出。
  明示操作に限る下限を0.01倍へ変更し、再検証で全チェック成功を確認した。

- Web releaseビルド成功。873×393と1280×800の独立Chromeで実操作し、
  M01→M04→M14、B05→B07→B21の3列、枝の余白と枠、横ドラッグ、詳細開閉、
  分類の入口復帰、未知研究の秘匿、同一worldIdと研究の再読込保持が成功した。
  browser/contextの後片付けまで自然終了0、pageerrorは0件。
  公開GameEngine操作で6研究を解放し、正規保存を再読込した検証専用の世界を使用した。
  画面の大きいRP残高は検証fixture用であり、製品の初期残高ではない。
- Webのfont tree-shake時に未使用CupertinoIconsの警告が残るが、
  実ブラウザの日本語とMaterialIconsは正常で、画像も目視した。

- iPhone 17 Pro / iOS26.1 Simulatorの最終版通し試験が終了0。
  新研究UI、受注・輸送、都市建設・増強、投資比較、火星居住、居住編ED、
  人員・提携、保存再開まで成功し、研究画面2枚の回収とdriver終了も確認した。
  最終実行では初回Sceneのシェーダー生成に最大約0.8秒の停止警告が残る。
  `MARS_INTEGRATION_CAPTURE_PREFIX=research-mobile-ios`で対象画像だけを回収した。

実画面: [メカニクスの枝](screenshots/research-horizontal-mechanics.png)、
[バイオの枝](screenshots/research-horizontal-bio.png)、
[小画面の枝](screenshots/research-horizontal-phone-branches.png)、
[次の列へのドラッグ](screenshots/research-horizontal-phone-next.png)、
[分類の入口復帰](screenshots/research-horizontal-phone-entry.png)、
[iOSの全幅表示](screenshots/research-horizontal-ios-overview.png)。
撮影前にポインターを画面外へ退避し、Tooltipの写り込みも除いた。

Pixel 8a実機での性能・電池と、通常時間での長期バランスは未検証。
次の本人評価は、左右の深まり、枝のまとまりと余白、パンして続きを追う感触とする。

## 反映・内部配信

- 3つの意味ごとのコミットを[PR #38](https://github.com/yakitama5/mars-terraforming/pull/38)からdevelop、
  [PR #39](https://github.com/yakitama5/mars-terraforming/pull/39)からmainへ通常mergeした。
  両PRとも最新HEADの全チェック成功とSHAを確認して反映した。
- mainは `03ae7ad7853b2e080a0d679ef14699c78d37d35b`、
  developは `2e41ac63461ed55cd74df2f320cf457dd696ef74`。
  [全体CI](https://github.com/yakitama5/mars-terraforming/actions/runs/39406117048)と
  [Pages](https://github.com/yakitama5/mars-terraforming/actions/runs/39406117040)が成功した。
  公開deployment.jsonの両全SHA・runを照合し、[通常版](https://yakitama5.github.io/mars-terraforming/)も更新済み。
- [内部配信run 39406116937](https://github.com/yakitama5/mars-terraforming/actions/runs/39406116937)は全4job成功。
  Android **801**をGoogle Play internalへ19:18:42 JST、
  iOS **8.1**をTestFlight内部グループへ19:23:01 JSTに配信確認した（2026-10-20）。
  記録の固定ID `io.github.yakitama5.marsterraforming`・main全SHA・run・build・配信先を二重照合済み。
  Android Artifact `12257667582`、iOS Artifact `12257733312`。
  両OSの署名材料削除とAndroid WIFの後片付けも成功した。
- 最終結果は両PR本文にも記録済み。本節の配信完了記録はローカル文書へ追記し、
  記録のための追加main push・再配信は行わない。
- 元の作業場所へ18対象中17ファイルを更新、1ファイルは同一内容として保持した。
  全511追跡ファイルを比較して、別作業のdocs/mobile-cd.md以外は内容が一致する。
  元のブランチ・HEADと既存の未コミット作業を保持した。
