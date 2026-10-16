import 'game_state.dart';

/// Narrative endings reuse durable habitation achievements. Viewing an ending
/// never grants rewards, resets a world, or implies global habitability.
class ColonyEnding {
  const ColonyEnding({
    required this.id,
    required this.title,
    required this.route,
    required this.condition,
    required this.scenes,
  });

  final String id, title, route, condition;
  final List<({String title, String body})> scenes;

  bool isUnlocked(GameState game) => game.achievements.contains(id);

  static const all = [
    ColonyEnding(
      id: 'dome_habitat',
      title: 'ガラス越しの朝',
      route: 'ドーム都市',
      condition: 'ドームを選び、火星の居住施設を完成させる',
      scenes: [
        (title: 'はじめての朝', body: '気密扉が閉まり、空気の循環が始まる。\n到着した人々はヘルメットを外し、互いの顔を見た。'),
        (
          title: '地球から持ってきたもの',
          body: '窓辺の栽培槽に、小さな苗を置く。\n街の税収も、工場の仕事も、研究所の夜も、この一枚の葉へつながっていた。',
        ),
        (
          title: 'ガラス越しの朝',
          body: '透明な天井の向こうには、まだ厳しい赤い荒野。\nけれど、この内側には暮らしがある。\n「ここを、私たちの街と呼ぼう。」',
        ),
      ],
    ),
    ColonyEnding(
      id: 'underground_habitat',
      title: '赤土の下の灯',
      route: '地下都市',
      condition: '地下居住を選び、火星の居住施設を完成させる',
      scenes: [
        (
          title: '掘削音が止んだ日',
          body: '掘削機が静かになり、岩盤の奥に最初の部屋ができた。\n厚い赤土に守られた空間へ、地球からの荷物を運び込む。',
        ),
        (
          title: '暮らしの音',
          body: '壁に家族の写真を掛ける。食卓から湯気が上がる。\n換気装置の低い音に、誰かの笑い声が重なった。',
        ),
        (
          title: '赤土の下の灯',
          body: '地上を砂塵が走る夜も、地下の灯は消えない。\n人は、この星の形を変える前に、寄り添って暮らす方法を見つけた。\n「この星の内側に、帰る場所ができた。」',
        ),
      ],
    ),
  ];
}
