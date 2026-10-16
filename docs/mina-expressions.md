# ミナの表情と2Dアニメーション

2026-10-16。ユーザーの「めっちゃいい感じ」「これを通常絵として」に基づき、3e59910のマットなウルフカット稿を通常絵として採用した。通常画像は変更せず、同じ顔・髪・制服・メガネ・ほくろを維持した差分を内蔵 image_gen の編集モードで制作した。

## 表情の使い分け

| 表情 | 素材 | 意図 |
| --- | --- | --- |
| 通常 | [mission_control.png](../assets/images/mission_control.png) | 操作・手順の落ち着いた説明 |
| 喜 | [mina_joy.png](../assets/images/mina_joy.png) | 目を開いた明るい笑顔。初着陸・開発完了・居住編の達成 |
| 怒 | [mina_anger.png](../assets/images/mina_anger.png) | 眉と口を引き締める。反復や上限などの注意。プレイヤーを責める演出にしない |
| 哀 | [mina_sorrow.png](../assets/images/mina_sorrow.png) | 心配して寄り添う表情。資金不足・計画の停止 |
| 楽 | [mina_delight.png](../assets/images/mina_delight.png) | 目を細めた楽しげな笑顔。新しい機会や宇宙の暮らしの展望 |
| 瞬き | [mina_blink.png](../assets/images/mina_blink.png) | 通常絵の口元を維持し、目だけを閉じる動作用フレーム |

表情は表示の補助。台詞、注意の文言、アイコン、費用や進行条件は維持する。表情を読み取れなくても判断材料を失わない。最小32pxでは眉や口の細部が控えめになる。

## 方式と範囲

今回の方式はFlutter標準の画像差分と小さな移動・回転による2D演出。通常絵の瞬きと、出現/表情切替に合わせる小さな動きを用いる。円枠と周囲の文字は動かさない。画像は全て同梱し、追加SDKや常時通信は不要。

- 出現と表情変更で420msの小さなうなずき。アイドルは5秒間隔で短く揺れ、通常表情だけ120msの瞬きを挟む。
- 瞬き画像は表示時と同じ解像度・AssetBundleで先に読み込み、準備ができるまで通常絵を維持する。
- 動きを減らす設定、TickerModeの非表示、別ルート/ダイアログによる被覆、アプリ休止、Widget削除でタイマーと動作を止める。再表示時に新しく開始する。
- 差分が読み込めない場合は通常絵、それも読めない場合は案内アイコンを使い、既存の読み上げラベルを維持する。
- スクロールのキャッシュ範囲に残る顔は画面外でも短いアイドル動作が続く場合がある。視野との交差判定は今回追加していない。

「Face2d」の製品名・意図は断定していない。Live2Dのようなパーツ変形リグは導入していない。本格的なリグ化では目・眉・口・髪などを分けた素材と隠れ部分、モデルとパラメータ、ランタイムの接続が必要になる。[Live2Dの素材分割](https://docs.live2d.com/en/cubism-editor-manual/divide-the-material/)・[モデル/モーション書き出し](https://docs.live2d.com/en/cubism-editor-manual/export-moc3-motion3-files/)。

## 検証と制約

- `mise exec -- bash tools/check.sh`: 依存方向・整形・静的解析と387テストが成功。新規は動作/停止/欠損画像の10件と、説明別表情の5件。
- 表情変更、通常だけの瞬き、動きを減らす設定の途中切替、TickerMode、透明ダイアログによる被覆、アプリ休止/再開、瞬き中の削除、画像欠損を確認。説明画面では表情変更によって保存JSONが変わらないことも確認した。
- Web releaseビルド成功。オフライン配布資源は57件。専用ChromeでOPの章切替・待機・ガイドを操作し、ブラウザ例外なし。オフライン再読込後に通常＋5差分の全6画像をデコードできることを確認。
- iPhone 17 Pro / iOS 26.1 Simulatorで `integration_test/mina_portrait_test.dart` が成功し、ドライバも終了コード0。全5表情を96pxで表示し、有限動作・通常の目閉じを実描画で確認。動きを減らす切替後は6秒経っても描画領域の画素が一致した。
- 親と別担当で原画、Webの40px/34px表示、iOSの表情一覧と瞬き画像を目視確認。通常絵 `mission_control.png`、依存の採用版、lockfileは変更していない。
- iOS検証は表情コンポーネント用ギャラリー。ゲーム全体の `prototype_test.dart` は今回は再実行していない。実機での電池/長時間負荷、Android、Safari/Firefoxは未実施。
- 表情差分は内蔵生成によるPNG。パーツ分割モデル・視線追従・髪の変形・口パク・音声同期は未実装。本格的なリグが必要になった段階で別途素材分けと方式を検討する。
- ローカルに実装・検証済み。公開リポジトリへのpushと配信は引き続き未実施。

実画面: [5表情](screenshots/mina-ios-five-expressions.png)、[瞬き](screenshots/mina-ios-normal-blink.png)、[有限動作](screenshots/mina-ios-finite-gesture.png)、[動きを減らす](screenshots/mina-ios-reduced-motion.png)、[Web OP](screenshots/mina-expression-web-opening.png)、[通常説明](screenshots/mina-expression-web-normal.png)、[ガイド](screenshots/mina-expression-web-guide.png)。

## 実動作の動画

ユーザーの「いい感じ！」「実際に表情が切り替わったり、まばたきするところを動画で見せて」に対応し、[約24秒のMP4](videos/mina-expressions.mp4)を収録した。ゲームと同じ `MinaAvatar` を220pxに拡大した専用画面のiOS Simulator録画。通常→喜→怒→哀→楽→通常と切り替わり、約7秒と23秒に通常表情の瞬きが入る。説明文の横に「ゲーム内の表示を拡大」と明記している。

- 収録用の画面は `integration_test/mina_video_capture_test.dart`。全6画像を先読みし、表情ごとの実画像描画と同じWidget状態の維持を確認してから実時間で動かす。
- iPhone 17 Pro / iOS 26.1 Simulatorで `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/mina_video_capture_test.dart -d <device-id>` が成功。`MINA_VIDEO_READY` を合図に `simctl io <device-id> recordVideo --codec=h264 --mask=ignored` を開始し、`MINA_VIDEO_DONE` でSIGINTを送って保存を完了した。
- 収録後は映像の向きと解像度を調整し、H.264のMP4として保存（1280×588、24.160秒、約19MB）。原本と長さが一致し、再生速度・表情のタイミングは変更せず、生成映像の補間や音声は追加していない。
- 新規の収録用ファイルは整形チェックと静的解析を通過。動画の再生可否、長さ、全表情と2回の目閉じを抽出フレームで確認。ゲーム本体・画像素材・依存は変更していないため、上記387テスト・Web・ゲーム全体のiOS検証は今回再実行していない。
- 今回の確認対象はSimulator上の拡大表示。実機でのサイズ感や長時間負荷は未検証。次はユーザーの動画評価を受けて、動きの強さや頻度を調整する。

## 生成プロンプト

すべて `assets/images/mission_control.png` を参照する個別の編集呼び出し。内蔵生成のみ使用し、CLI/APIは使用していない。通常絵の制作履歴は [生成素材記録](generated-story-assets.md) を参照。

### mina_joy.png

Use case: identity-preserve. Asset type: one facial-expression variant of the approved 2D game adviser Mina. Input image 1 is the APPROVED BASE and exact edit target. Preserve her identity, dark wolf-cut hair silhouette and all hair locks, round navy glasses, mole beside the mouth on the viewer's right, earpiece, navy uniform, line weight, matte simple color palette, head tilt, neck, shoulders, scale, position, and square crop EXACTLY. Change ONLY the eyes, eyebrows and mouth to the expression described below. This is a matched expression sprite, not a new portrait: DO NOT move or resize the face or redraw the haircut, glasses, outfit or pose. Keep the existing simplified flat 2D drawing, no additional glossy highlights, sparkles, blush gradients, cinematic lighting, detailed textures, or accessories. One character only, no text, no emotion symbols, no decorations, no frame. Genuine transparent background with clean alpha edges. Same square canvas and full silhouette as the input. Expression JOY (喜), delighted by a successful mission milestone: open eyes with slightly raised eyebrows, brown irises without shiny points, a bright clearly open smile showing a simple white upper-teeth shape. Friendly proud happiness, more energetic than the base expression. Keep her adult chibi charm; no tears or exaggerated face distortions.

### mina_anger.png

Use case: identity-preserve. Asset type: one facial-expression variant of the approved 2D game adviser Mina. Input image 1 is the APPROVED BASE and exact edit target. Preserve her identity, dark wolf-cut hair silhouette and all hair locks, round navy glasses, mole beside the mouth on the viewer's right, earpiece, navy uniform, line weight, matte simple color palette, head tilt, neck, shoulders, scale, position, and square crop EXACTLY. Change ONLY the eyes, eyebrows and mouth to the expression described below. This is a matched expression sprite, not a new portrait: DO NOT move or resize the face or redraw the haircut, glasses, outfit or pose. Keep the existing simplified flat 2D drawing, no additional glossy highlights, sparkles, blush gradients, cinematic lighting, detailed textures, or accessories. One character only, no text, no emotion symbols, no decorations, no frame. Genuine transparent background with clean alpha edges. Same square canvas and full silhouette as the input. Expression ANGER / FIRM CAUTION (怒), a serious but caring mission adviser explaining a preventable operational problem: eyebrows angled down toward the nose, subtly narrowed slightly upturned eyes, small firm closed mouth with corners slightly down. Restrained cute sternness, not furious or aggressive, no fangs, no angry vein symbol, no flushed cheeks. She is taking the situation seriously, not scolding the player.

### mina_sorrow.png

Use case: identity-preserve. Asset type: one facial-expression variant of the approved 2D game adviser Mina. Input image 1 is the APPROVED BASE and exact edit target. Preserve her identity, dark wolf-cut hair silhouette and all hair locks, round navy glasses, mole beside the mouth on the viewer's right, earpiece, navy uniform, line weight, matte simple color palette, head tilt, neck, shoulders, scale, position, and square crop EXACTLY. Change ONLY the eyes, eyebrows and mouth to the expression described below. This is a matched expression sprite, not a new portrait: DO NOT move or resize the face or redraw the haircut, glasses, outfit or pose. Keep the existing simplified flat 2D drawing, no additional glossy highlights, sparkles, blush gradients, cinematic lighting, detailed textures, or accessories. One character only, no text, no emotion symbols, no decorations, no frame. Genuine transparent background with clean alpha edges. Same square canvas and full silhouette as the input. Expression SORROW / CONCERN (哀), gently concerned about a stalled plan: eyebrows raised at their inner ends, slightly lowered eyelids and softened eyes looking a little downward, small downturned closed mouth. Sympathy and concern, still approachable and cute. No tears, no dramatic crying, no facial color change.

### mina_delight.png

Use case: identity-preserve. Asset type: one facial-expression variant of the approved 2D game adviser Mina. Input image 1 is the APPROVED BASE and exact edit target. Preserve her identity, dark wolf-cut hair silhouette and all hair locks, round navy glasses, mole beside the mouth on the viewer's right, earpiece, navy uniform, line weight, matte simple color palette, head tilt, neck, shoulders, scale, position, and square crop EXACTLY. Change ONLY the eyes, eyebrows and mouth to the expression described below. This is a matched expression sprite, not a new portrait: DO NOT move or resize the face or redraw the haircut, glasses, outfit or pose. Keep the existing simplified flat 2D drawing, no additional glossy highlights, sparkles, blush gradients, cinematic lighting, detailed textures, or accessories. One character only, no text, no emotion symbols, no decorations, no frame. Genuine transparent background with clean alpha edges. Same square canvas and full silhouette as the input. Expression DELIGHT / RELAXED FUN (楽), enjoying the prospect of a new home in space: both eyes gently closed into upward smiling arcs behind the glasses, relaxed friendly eyebrows, a small open laughing smile. Calm warm amusement, distinctly different from the open-eyed celebratory JOY variant. No tears, no blush gradients, no symbols.

### mina_blink.png

Use case: identity-preserve. Asset type: one facial-expression variant of the approved 2D game adviser Mina. Input image 1 is the APPROVED BASE and exact edit target. Preserve her identity, dark wolf-cut hair silhouette and all hair locks, round navy glasses, mole beside the mouth on the viewer's right, earpiece, navy uniform, line weight, matte simple color palette, head tilt, neck, shoulders, scale, position, and square crop EXACTLY. Change ONLY the eyes, eyebrows and mouth to the expression described below. This is a matched expression sprite, not a new portrait: DO NOT move or resize the face or redraw the haircut, glasses, outfit or pose. Keep the existing simplified flat 2D drawing, no additional glossy highlights, sparkles, blush gradients, cinematic lighting, detailed textures, or accessories. One character only, no text, no emotion symbols, no decorations, no frame. Genuine transparent background with clean alpha edges. Same square canvas and full silhouette as the input. Animation frame: NORMAL EXPRESSION BLINK. Change ONLY the eyes to naturally closed relaxed eyelids with simple curved dark lines at the same eye positions; hide irises and pupils. The mouth, eyebrows, cheeks and every other pixel region should remain as close to the input as possible. Keep the SAME small closed smile as the base. This is a brief blink between two identical normal frames, so do not change the emotion, mouth, head position, pose, silhouette, scale or alignment.
