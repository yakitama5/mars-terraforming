/// Narrative destinations, not completion rules or unlockable rewards.
/// Global habitability and ending conditions still require a design decision.
class ResearchFrontier {
  const ResearchFrontier({
    required this.id,
    required this.title,
    required this.promise,
    required this.researchIds,
    required this.scene,
    required this.nextChallenge,
    required this.scientificBoundary,
  });

  final String id;
  final String title;
  final String promise;
  final List<String> researchIds;
  final String scene;
  final String nextChallenge;
  final String scientificBoundary;
}

abstract final class ResearchFrontiers {
  static const destinations = <ResearchFrontier>[
    ResearchFrontier(
      id: 'harbor_of_two_worlds',
      title: '二つの星の港',
      promise: '地球と火星を、帰れる故郷に。',
      researchIds: [
        'electric_tugs',
        'orbital_logistics',
        'intercity_logistics',
      ],
      scene: '軌道に青い航跡が灯る。港の掲示板に並ぶのは実験番号ではなく、家族を迎える定期便の名前。かつて一度きりだった旅が、ふたつの故郷を結ぶ日常になる。',
      nextChallenge: '次の研究構想：長期貯蔵できる推進剤、補給拠点、往復輸送。先行投資と地球からの補給量をどう減らすかが鍵。',
      scientificBoundary: '電気推進には実証があります。大量の旅客が往来する定期航路と、その先の物語はSF上の到達像です。',
    ),
    ResearchFrontier(
      id: 'gardens_of_the_red_planet',
      title: '赤い星の庭',
      promise: '持ち込んだ命が、次の命を育てる。',
      researchIds: ['oxygen_pilot', 'orbital_gardens', 'local_resources'],
      scene: '最初の収穫祭で、子どもが種をひとつ土へ戻す。観測窓の外はまだ赤い。それでも食卓には、地球から運ばなかった季節の色が並んでいる。',
      nextChallenge: '次の研究構想：栄養塩の回収、複数作物の循環、保護された生態系。収量だけでなく、水・光・病害への備えを選ぶ。',
      scientificBoundary:
          '閉鎖空間の栽培や酸素製造から発想した未来像です。生態系の完全自立、呼吸可能な屋外環境は実証されていません。',
    ),
    ResearchFrontier(
      id: 'lights_beyond_the_night',
      title: '夜を越える街の灯',
      promise: '遠い星でも、暮らしを止めない。',
      researchIds: [
        'radiation_shelters',
        'surface_fission',
        'regolith_printing',
        'regional_habitats',
      ],
      scene: '長い夜に街の灯が点々と続く。赤土の壁に守られた工房から、次の都市へ向かう建設機が出発する。住民たちはもう「滞在」と呼ばず、「暮らす」と言う。',
      nextChallenge: '次の研究構想：故障しても維持できる分散電源、現地修理、環境制御。効率と予備設備のどちらへ投資するかを問う。',
      scientificBoundary: '原子炉と建材造形には地上実証、防護にはモデル研究があります。火星での長期自立運用は未来の構想です。',
    ),
  ];
}
