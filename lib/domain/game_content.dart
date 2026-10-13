/// Tuning data for the first playable prototype. Money is in credits (Cr),
/// durations are real seconds, and operating rates are credits per real minute.
/// Starter jobs remain short for compatibility; city investment and research
/// branch over several real days. This does not model the finished 4–6 week game.
class FacilityDefinition {
  const FacilityDefinition(this.id, this.name, this.upkeepPerMinute);
  final String id;
  final String name;
  final int upkeepPerMinute;
}

class TaskDefinition {
  const TaskDefinition({
    required this.id,
    required this.name,
    required this.facilityId,
    required this.durationSeconds,
    required this.cost,
    required this.description,
    this.reward = 0,
    this.requiredResearch,
    this.inputResource,
    this.outputResource,
    this.unique = false,
    this.requiresHabitatChoice = false,
    this.science = '',
    this.prerequisites = const [],
    this.researchBranch = '',
    this.researchStage = 0,
    this.unlockSummary = '',
    this.districtId,
    this.isDistrictUpgrade = false,
    this.inputAmount = 1,
    this.outputAmount = 1,
    this.researchRequirements = const ResearchRequirements(),
  });
  final String id;
  final String name;
  final String facilityId;
  final int durationSeconds;
  final int cost;
  final int reward;
  final String description;
  final String? requiredResearch;
  final String? inputResource;
  final String? outputResource;
  final bool unique;
  final bool requiresHabitatChoice;
  final String science;
  final List<String> prerequisites;
  List<String> get prerequisiteIds => [?requiredResearch, ...prerequisites];
  final String researchBranch;
  final int researchStage;
  final String unlockSummary;
  final String? districtId;
  final bool isDistrictUpgrade;
  final int inputAmount;
  final int outputAmount;
  final ResearchRequirements researchRequirements;
  int get durationMs => durationSeconds * 1000;
}

abstract final class GameContent {
  static const version = 'district-2';
  static const initialMoney = 900;
  static const initialPopulation = 120;
  static const baseTaxPerMinute = 30;
  static const districtTaxPerMinute = 18;
  static const residentsPerHabitat = 12;
  static const residentsPerDistrict = 60;
  static const achievementReward = 180;
  static const maxActivePlans = 24;
  static const maxFinishedPlans = 48;
  static const facilities = <String, FacilityDefinition>{
    'lab': FacilityDefinition('lab', '研究所', 8),
    'factory': FacilityDefinition('factory', '共用工場', 18),
    'launch': FacilityDefinition('launch', '共用宇宙港', 14),
    'mars': FacilityDefinition('mars', '火星建設班', 2),
  };
  static const _starterTasks = <String, TaskDefinition>{
    'factory_contract': TaskDefinition(
      id: 'factory_contract',
      name: '外部受注・精密機器',
      facilityId: 'factory',
      durationSeconds: 90,
      cost: 40,
      reward: 220,
      description: '共用工場を使い、完了時に220 Crを受領。居住キット製造と設備を取り合う。',
    ),
    'launch_contract': TaskDefinition(
      id: 'launch_contract',
      name: '外部受注・衛星打上げ',
      facilityId: 'launch',
      durationSeconds: 120,
      cost: 80,
      reward: 360,
      description: '共用宇宙港を使い、完了時に360 Crを受領。自前の火星輸送はその間待機。',
    ),
    'life_support': TaskDefinition(
      id: 'life_support',
      name: '生命維持の実証',
      facilityId: 'lab',
      durationSeconds: 120,
      cost: 180,
      unique: true,
      researchBranch: '居住・現地生産',
      researchStage: 0,
      unlockSummary: '居住キット製造・火星居住地区',
      description: '閉鎖居住に必要な水・空気の再生系を研究。居住キットを製造できるようになる。',
      science:
          '実証：ISSでは水回収・再生システムが運用されています。NASAは2023年に98%の水回収という到達点を報告しました。\n\n'
          '構想：その考え方を火星の閉鎖居住設備へ応用します。ISSでの実証は火星での長期自立や屋外居住の実証ではありません。\n\n'
          'ゲーム上の仮定：設備1組で少人数の居住を支えます。期間・費用・輸送・放射線対策を簡略化しています。\n\n'
          'NASA (2023) NASA Achieves Water Recovery Milestone on International Space Station\n'
          'https://www.nasa.gov/missions/station/iss-research/nasa-achieves-water-recovery-milestone-on-international-space-station/',
    ),
    'habitat_kit': TaskDefinition(
      id: 'habitat_kit',
      name: '居住キット製造',
      facilityId: 'factory',
      durationSeconds: 180,
      cost: 260,
      requiredResearch: 'life_support',
      outputResource: 'earthKits',
      description: '生命維持設備と居住モジュールを1基製造。地球の在庫に追加する。',
    ),
    'mars_delivery': TaskDefinition(
      id: 'mars_delivery',
      name: '火星へ輸送',
      facilityId: 'launch',
      durationSeconds: 180,
      cost: 220,
      inputResource: 'earthKits',
      outputResource: 'marsKits',
      description: '地球の居住キット1基を火星へ運ぶ。貨物と費用は出発時に確保する。',
    ),
    'build_habitat': TaskDefinition(
      id: 'build_habitat',
      name: '火星居住区を建設',
      facilityId: 'mars',
      durationSeconds: 120,
      cost: 200,
      inputResource: 'marsKits',
      requiresHabitatChoice: true,
      description: 'ドーム／地下居住の方針を選んで建設。1基につき12人が閉鎖居住区で暮らせる。',
      science: '火星の閉鎖居住は構想段階。保護された居住区の成立を仮定し、屋外の居住可能化とは区別します。',
    ),
    'earth_expansion': TaskDefinition(
      id: 'earth_expansion',
      name: '地球の住宅地区を拡張',
      facilityId: 'factory',
      durationSeconds: 120,
      cost: 300,
      description: '人口を60人、税収を毎分18 Cr増やす。工場を使うため、受注・製造との配分が必要。',
    ),
  };

  /// Content values are provisional. The short starter loop is preserved for
  /// existing saves; these branches add investment choices over several days.
  static final tasks = <String, TaskDefinition>{
    ..._starterTasks,
    for (final task in _researchTasks) task.id: task,
    'precision_contract': TaskDefinition(
      id: 'precision_contract',
      name: '外部受注・自動化設備',
      facilityId: 'factory',
      durationSeconds: 7200,
      cost: 2400,
      reward: 24000,
      requiredResearch: 'automated_fabrication',
      description: '2時間のまとまった受注。高い収益と引き換えに、自前の製造・地区建設を待たせる。',
    ),
    'orbital_contract': TaskDefinition(
      id: 'orbital_contract',
      name: '外部受注・軌道補給',
      facilityId: 'launch',
      durationSeconds: 10800,
      cost: 4200,
      reward: 42000,
      requiredResearch: 'orbital_logistics',
      description: '共用宇宙港を使う長期契約。完了収入を都市・研究へ再投資できる。',
    ),
    'batch_habitat_kit': TaskDefinition(
      id: 'batch_habitat_kit',
      name: '居住キット一括製造',
      facilityId: 'factory',
      durationSeconds: 600,
      cost: 1200,
      outputResource: 'earthKits',
      outputAmount: 6,
      requiredResearch: 'automated_fabrication',
      prerequisites: ['life_support'],
      description: '6基をまとめて製造。単基製造より費用・総工期を節約する。',
    ),
    'cargo_delivery': TaskDefinition(
      id: 'cargo_delivery',
      name: '火星へ一括輸送',
      facilityId: 'launch',
      durationSeconds: 600,
      cost: 950,
      inputResource: 'earthKits',
      inputAmount: 6,
      outputResource: 'marsKits',
      outputAmount: 6,
      requiredResearch: 'orbital_logistics',
      description: '地球の居住キット6基を一括輸送。輸送費を節約して火星の地区建設を支える。',
    ),
    for (final district in districts.values)
      for (final upgrade in [false, true])
        district.taskId(upgrade: upgrade): TaskDefinition(
          id: district.taskId(upgrade: upgrade),
          name: '${district.name}${upgrade ? 'を増強' : 'を建設'}',
          facilityId: district.planet == 'earth' ? 'factory' : 'mars',
          durationSeconds: district.durationSeconds,
          cost: district.cost,
          requiredResearch: district.requiredResearch,
          districtId: district.id,
          isDistrictUpgrade: upgrade,
          inputResource: district.planet == 'mars' ? 'marsKits' : null,
          requiresHabitatChoice: district.id == 'mars_habitat',
          description: district.description,
        ),
  };

  static const _researchTasks = <TaskDefinition>[
    TaskDefinition(
      id: 'urban_planning',
      name: '都市基盤の計画',
      facilityId: 'lab',
      durationSeconds: 14400,
      cost: 4000,
      unique: true,
      researchBranch: '都市・産業',
      researchStage: 1,
      unlockSummary: '研究地区・工業地区・高原科学都市',
      description: '住宅と産業の近接効果を活用し、研究または製造に都市を特化する。',
      science: 'ゲーム上の仮定：地区の機能集積を研究・製造の工期短縮として簡略化しています。',
    ),
    TaskDefinition(
      id: 'automated_fabrication',
      name: '自動化生産の実証',
      facilityId: 'lab',
      durationSeconds: 64800,
      cost: 120000,
      unique: true,
      researchRequirements: ResearchRequirements(
        districtCounts: {'industry': 1},
      ),
      requiredResearch: 'urban_planning',
      researchBranch: '都市・産業',
      researchStage: 2,
      unlockSummary: '自動化設備受注・キット6基製造・Lv.2地区・製造効率上限45%',
      description: '同じ工場で収益事業と自前の設備製造を選び分ける。',
      science: 'ゲーム上の仮定：自動化の成果を一括製造と地区増強に集約。費用・期間は仮値です。',
    ),
    TaskDefinition(
      id: 'industrial_network',
      name: '広域産業ネットワーク',
      facilityId: 'lab',
      durationSeconds: 129600,
      cost: 900000,
      unique: true,
      requiredResearch: 'automated_fabrication',
      researchBranch: '都市・産業',
      researchStage: 3,
      unlockSummary: '地球地区Lv.3・全工場の効率+10%・製造効率上限60%',
      description: '限られた用地を増強するか、別都市へ展開するかを選ぶ。',
      science: 'ゲーム上の仮定：都市間の産業連携を共用工場の効率に反映します。',
    ),
    TaskDefinition(
      id: 'reusable_launch',
      name: '再使用輸送の実証',
      facilityId: 'lab',
      durationSeconds: 21600,
      cost: 30000,
      unique: true,
      requiredResearch: 'urban_planning',
      researchBranch: '輸送',
      researchStage: 1,
      unlockSummary: '宇宙港地区・全輸送の効率+10%',
      description: '輸送能力へ投資し、外部打上げと火星向け輸送の共用待ちを短くする。',
      science: 'ゲーム上の仮定：再使用運用の効果を工期短縮として表現。実際の打上げ窓・航行時間は再現しません。',
    ),
    TaskDefinition(
      id: 'orbital_logistics',
      name: '軌道補給網',
      facilityId: 'lab',
      durationSeconds: 86400,
      cost: 300000,
      unique: true,
      researchRequirements: ResearchRequirements(
        districtCounts: {'spaceport': 1},
      ),
      requiredResearch: 'reusable_launch',
      researchBranch: '輸送',
      researchStage: 2,
      unlockSummary: '軌道補給受注・火星へ6基輸送・エリシウム都市・輸送効率上限45%',
      description: '輸送をまとめて実行し、複数の火星都市へ展開する余力を作る。',
      science: '構想：補給拠点を利用する輸送網。ゲーム上の仮定：軌道設備を独立建設せず研究完了で利用可能とします。',
    ),
    TaskDefinition(
      id: 'intercity_logistics',
      name: '惑星間の都市連携',
      facilityId: 'lab',
      durationSeconds: 129600,
      cost: 1200000,
      unique: true,
      requiredResearch: 'orbital_logistics',
      researchBranch: '輸送',
      researchStage: 3,
      unlockSummary: '全輸送の効率を追加+15%・ヘラス都市・輸送効率上限60%',
      description: '異なる地形の火星都市へ設備を送り、土地の使い方を分担する。',
      science: 'ゲーム上の仮定：惑星間・都市間の物流を共通在庫と輸送効率へ集約しています。',
    ),
    TaskDefinition(
      id: 'closed_ecology',
      name: '閉鎖循環の実証',
      facilityId: 'lab',
      durationSeconds: 43200,
      cost: 60000,
      unique: true,
      researchRequirements: ResearchRequirements(marsHabitats: 1),
      requiredResearch: 'life_support',
      researchBranch: '居住・現地生産',
      researchStage: 1,
      unlockSummary: '温室地区・現地研究地区',
      description: '居住地区の隣へ温室を配置し、税収と現地建設の効率を育てる。',
      science: '構想：閉鎖された設備内の資源循環。ゲーム上の仮定：温室は屋内生活を支えます。火星屋外の生育や完全自立を意味しません。',
    ),
    TaskDefinition(
      id: 'local_resources',
      name: '現地資源利用の実証',
      facilityId: 'lab',
      durationSeconds: 86400,
      cost: 600000,
      unique: true,
      researchRequirements: ResearchRequirements(
        districtCounts: {'greenhouse': 1},
      ),
      requiredResearch: 'closed_ecology',
      researchBranch: '居住・現地生産',
      researchStage: 2,
      unlockSummary: '資源採取地区・火星地区Lv.2・現地建設効率上限45%',
      description: '氷・鉱物のある区画を開発し、収入と現地建設速度を伸ばす。',
      science: '構想：火星の資源を現地設備で利用する開発。ゲーム上の仮定：採取量や継続補給を税収・建設効率へ簡略化しています。',
    ),
    TaskDefinition(
      id: 'regional_habitats',
      name: '地域の閉鎖居住網',
      facilityId: 'lab',
      durationSeconds: 172800,
      cost: 1800000,
      unique: true,
      researchRequirements: ResearchRequirements(
        districtCounts: {'extractor': 1},
        developedMarsCities: 2,
      ),
      requiredResearch: 'local_resources',
      prerequisites: ['orbital_logistics'],
      researchBranch: '居住・現地生産',
      researchStage: 3,
      unlockSummary: '火星地区Lv.3・現地建設の効率+10%・現地建設効率上限60%',
      description: '複数都市の限られた土地を増強し、閉鎖居住の長期運営を目指す。',
      science: 'ゲーム上の仮定：閉鎖居住設備を地域へ展開する段階。屋外居住・全球テラフォーミングの達成ではありません。',
    ),
  ];

  /// Efficiency grows with demonstrated research, rather than filling its
  /// final cap as soon as the first scientific city opens.
  static const efficiencyCapsByStage = [30, 30, 45, 60];
  static const facilityResearchBranches = {
    'factory': '都市・産業',
    'launch': '輸送',
    'mars': '居住・現地生産',
  };
  static const districtEfficiencyBase = {
    'campus': 4,
    'industry': 4,
    'spaceport': 4,
    'mars_lab': 4,
    'solar': 2,
    'extractor': 4,
    'greenhouse': 2,
  };
  static const efficiencyTerrainBonus = 2;
  static const efficiencyAdjacentBonus = 1;
  static const solarRidgeEfficiency = 3;
  static const researchEfficiencyBonuses = {
    'industrial_network': {'factory': 10},
    'reusable_launch': {'launch': 10},
    'intercity_logistics': {'launch': 15},
    'regional_habitats': {'mars': 10},
  };

  static const terrainNames = {
    'plain': '平地',
    'coast': '海岸',
    'mineral': '鉱床',
    'ridge': '高台',
    'ice': '氷層',
    'crater': 'クレーター',
  };
  static const cities = <String, CityDefinition>{
    'earth_delta': CityDefinition(
      id: 'earth_delta',
      name: 'デルタ湾岸',
      planet: 'earth',
      latitude: 28,
      longitude: -80,
      description: '海岸の住宅収入と宇宙港。既存の本部・街区は区画外にあります。',
      terrain: [
        'coast',
        'coast',
        'plain',
        'plain',
        'ridge',
        'coast',
        'plain',
        'plain',
        'mineral',
        'ridge',
        'coast',
        'plain',
        'plain',
        'mineral',
        'plain',
        'coast',
        'plain',
        'plain',
        'plain',
        'ridge',
        'coast',
        'coast',
        'plain',
        'mineral',
        'ridge',
      ],
    ),
    'earth_highland': CityDefinition(
      id: 'earth_highland',
      name: '高原科学都市',
      planet: 'earth',
      latitude: 35,
      longitude: 10,
      requiredResearch: 'urban_planning',
      description: '高台の研究と鉱床の製造。隣接する地区で専門都市に育てる。',
      terrain: [
        'ridge',
        'ridge',
        'plain',
        'mineral',
        'mineral',
        'ridge',
        'plain',
        'plain',
        'mineral',
        'ridge',
        'plain',
        'plain',
        'ridge',
        'plain',
        'mineral',
        'ridge',
        'plain',
        'plain',
        'ridge',
        'plain',
        'mineral',
        'mineral',
        'plain',
        'ridge',
        'ridge',
      ],
    ),
    'mars_arcadia': CityDefinition(
      id: 'mars_arcadia',
      name: 'アルカディア',
      planet: 'mars',
      latitude: 40,
      longitude: -110,
      description: '氷層が豊富な初期着陸地域。温室と資源採取を組み合わせる。',
      terrain: [
        'ice',
        'ice',
        'plain',
        'plain',
        'ridge',
        'ice',
        'plain',
        'plain',
        'mineral',
        'ridge',
        'plain',
        'plain',
        'ice',
        'plain',
        'crater',
        'ridge',
        'plain',
        'plain',
        'ice',
        'ice',
        'crater',
        'mineral',
        'plain',
        'ice',
        'ice',
      ],
    ),
    'mars_elysium': CityDefinition(
      id: 'mars_elysium',
      name: 'エリシウム',
      planet: 'mars',
      latitude: 5,
      longitude: 150,
      requiredResearch: 'orbital_logistics',
      description: '高台と鉱床の地域。現地研究と採取による建設網を整える。',
      terrain: [
        'ridge',
        'ridge',
        'mineral',
        'plain',
        'crater',
        'ridge',
        'plain',
        'plain',
        'mineral',
        'crater',
        'plain',
        'mineral',
        'ridge',
        'plain',
        'plain',
        'mineral',
        'plain',
        'plain',
        'ridge',
        'ice',
        'crater',
        'crater',
        'mineral',
        'plain',
        'ice',
      ],
    ),
    'mars_hellas': CityDefinition(
      id: 'mars_hellas',
      name: 'ヘラス',
      planet: 'mars',
      latitude: -42,
      longitude: 70,
      requiredResearch: 'intercity_logistics',
      description: 'クレーターの多い後期拠点。地下居住の立地効果を活かせる。',
      terrain: [
        'crater',
        'crater',
        'ridge',
        'plain',
        'ice',
        'crater',
        'plain',
        'crater',
        'plain',
        'ice',
        'ridge',
        'crater',
        'plain',
        'crater',
        'mineral',
        'plain',
        'plain',
        'crater',
        'plain',
        'mineral',
        'ice',
        'crater',
        'crater',
        'ridge',
        'plain',
      ],
    ),
  };
  static const districts = <String, DistrictDefinition>{
    'housing': DistrictDefinition(
      id: 'housing',
      name: '住宅地区',
      planet: 'earth',
      cost: 350,
      durationSeconds: 600,
      baseTaxPerMinute: 12,
      upkeepPerMinute: 2,
      residents: 60,
      description: '海岸で税収+4。研究地区の隣で+3。工業の隣では−3。',
    ),
    'campus': DistrictDefinition(
      id: 'campus',
      name: '研究地区',
      planet: 'earth',
      cost: 1200,
      durationSeconds: 3600,
      upkeepPerMinute: 4,
      requiredResearch: 'urban_planning',
      description: '研究効率+4%。高台で+2%、隣接住宅で+1%、発電地区で+2%。',
    ),
    'industry': DistrictDefinition(
      id: 'industry',
      name: '工業地区',
      planet: 'earth',
      cost: 1500,
      durationSeconds: 5400,
      upkeepPerMinute: 5,
      requiredResearch: 'urban_planning',
      description: '製造効率+4%。鉱床で+2%、宇宙港で+1%、発電地区で+2%。住宅の隣接収入は低下。',
    ),
    'solar': DistrictDefinition(
      id: 'solar',
      name: '発電地区',
      planet: 'earth',
      cost: 650,
      durationSeconds: 1200,
      upkeepPerMinute: 1,
      description: '隣接する研究・工業・宇宙港地区の効率を+2%。高台では追加+1%。',
    ),
    'spaceport': DistrictDefinition(
      id: 'spaceport',
      name: '宇宙港地区',
      planet: 'earth',
      cost: 2400,
      durationSeconds: 7200,
      upkeepPerMinute: 6,
      requiredResearch: 'reusable_launch',
      description: '輸送効率+4%。海岸で+2%、工業で+1%、発電地区で+2%。',
    ),
    'mars_habitat': DistrictDefinition(
      id: 'mars_habitat',
      name: '火星居住地区',
      planet: 'mars',
      cost: 700,
      durationSeconds: 1800,
      baseTaxPerMinute: 6,
      upkeepPerMinute: 2,
      residents: 24,
      requiredResearch: 'life_support',
      description: '隣接する温室・資源採取で税収+3。ドームは平地、地下はクレーターで+4。',
    ),
    'greenhouse': DistrictDefinition(
      id: 'greenhouse',
      name: '温室地区',
      planet: 'mars',
      cost: 1800,
      durationSeconds: 7200,
      baseTaxPerMinute: 4,
      upkeepPerMinute: 3,
      requiredResearch: 'closed_ecology',
      description: '氷層で税収+6。隣接居住の税収+3、現地建設効率+2%。閉鎖設備内での生育。',
    ),
    'extractor': DistrictDefinition(
      id: 'extractor',
      name: '資源採取地区',
      planet: 'mars',
      cost: 3000,
      durationSeconds: 10800,
      baseTaxPerMinute: 8,
      upkeepPerMinute: 3,
      requiredResearch: 'local_resources',
      allowedTerrain: ['ice', 'mineral'],
      description: '氷層・鉱床に建設。現地建設効率+4%、隣接居住地区の税収+3。',
    ),
    'mars_lab': DistrictDefinition(
      id: 'mars_lab',
      name: '現地研究地区',
      planet: 'mars',
      cost: 2200,
      durationSeconds: 7200,
      upkeepPerMinute: 4,
      requiredResearch: 'closed_ecology',
      description: '研究効率+4%。高台で+2%、隣接する居住・採取地区で+1%。',
    ),
  };

  static const resourceNames = {
    'earthKits': '地球の居住キット',
    'marsKits': '火星の居住キット',
  };
  static const achievementNames = {
    'first_landing': '火星への初輸送',
    'dome_habitat': 'ドームでの暮らし',
    'underground_habitat': '地下での暮らし',
  };
}

/// Offset hexagons: odd rows shift right. Geometry is shared by UI and rules.
class CityDefinition {
  const CityDefinition({
    required this.id,
    required this.name,
    required this.planet,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.terrain,
    this.requiredResearch,
    this.width = 5,
    this.height = 5,
  });
  final String id, name, planet, description;
  final double latitude, longitude;
  final String? requiredResearch;
  final int width, height;
  final List<String> terrain;
  int get plotCount => width * height;
  String terrainAt(int index) => terrain[index];
  List<int> adjacentPlots(int index) {
    final row = index ~/ width;
    final col = index % width;
    final shift = row.isOdd ? 1 : -1;
    final coordinates = [
      (row, col - 1),
      (row, col + 1),
      (row - 1, col),
      (row + 1, col),
      (row - 1, col + shift),
      (row + 1, col + shift),
    ];
    return [
      for (final (r, c) in coordinates)
        if (r >= 0 && r < height && c >= 0 && c < width) r * width + c,
    ];
  }
}

class DistrictDefinition {
  const DistrictDefinition({
    required this.id,
    required this.name,
    required this.planet,
    required this.cost,
    required this.durationSeconds,
    required this.description,
    this.requiredResearch,
    this.baseTaxPerMinute = 0,
    this.upkeepPerMinute = 0,
    this.maxLevel = 3,
    this.residents = 0,
    this.allowedTerrain = const [],
  });
  final String id, name, planet, description;
  final String? requiredResearch;
  final int cost,
      durationSeconds,
      baseTaxPerMinute,
      upkeepPerMinute,
      maxLevel,
      residents;
  final List<String> allowedTerrain;
  String get operatingFacilityId => switch (id) {
    'campus' || 'mars_lab' => 'lab',
    'spaceport' => 'launch',
    _ => planet == 'earth' ? 'factory' : 'mars',
  };
  String taskId({bool upgrade = false}) =>
      '${upgrade ? 'upgrade' : 'district'}_$id';
  int costForLevel(int level) =>
      cost *
      (level == 1
          ? 1
          : level == 2
          ? 4
          : 12);
  int durationMsForLevel(int level) =>
      durationSeconds *
      1000 *
      (level == 1
          ? 1
          : level == 2
          ? 4
          : 12);
}

/// Completed physical demonstrations; these never revoke legacy research.
class ResearchRequirements {
  const ResearchRequirements({
    this.marsHabitats = 0,
    this.districtCounts = const {},
    this.developedMarsCities = 0,
  });
  final int marsHabitats;
  final Map<String, int> districtCounts;
  final int developedMarsCities;
}

class ResearchRequirementStatus {
  const ResearchRequirementStatus({
    required this.label,
    required this.current,
    required this.required,
    required this.unmetReason,
  });
  final String label, unmetReason;
  final int current, required;
  bool get isMet => current >= required;
}
