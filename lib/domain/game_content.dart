import 'agency_state.dart';
import 'research_catalog.dart';
export 'research_catalog.dart';
export 'agency_state.dart';

/// Tuning data for the first playable prototype. Money is in dollars,
/// durations are real seconds, and operating rates are dollars per real minute.
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
    this.researchPromise = '',
    this.districtId,
    this.isDistrictUpgrade = false,
    this.inputAmount = 1,
    this.outputAmount = 1,
    this.researchRequirements = const ResearchRequirements(),
    this.alternativePrerequisites = const [],
    this.developmentId,
    this.requiredDevelopmentId,
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

  /// Short benefit on the graph; full effects and evidence remain in details.
  final String researchPromise;
  final String? districtId;
  final bool isDistrictUpgrade;
  final int inputAmount;
  final int outputAmount;
  final ResearchRequirements researchRequirements;
  final List<String> alternativePrerequisites;
  final String? developmentId;
  final String? requiredDevelopmentId;
  int get durationMs => durationSeconds * 1000;
}

abstract final class GameContent {
  static const version = 'district-7';
  // Common RP use integer fixed-point integration in GameState. Values below
  // are provisional game tuning, not scientific performance estimates.
  static const initialResearchPoints = 24;
  static const researchPointsPerResearcherPerMinute = 1;
  static const researchPointCostsByStage = [120, 2400, 24000];
  static const developmentCostsByStage = [1200, 12000, 85000];
  static const developmentDurationsByStage = [300, 1800, 14400];
  static const developmentUpkeepByStage = [3, 12, 35];
  static const developmentBonusesByStage = [3, 7, 12];
  static const maxOperationalDevelopments = 12;
  static const researchTechnologies = ResearchCatalog.technologies;
  static const starterResearchCatalogIds = ['B01', 'M22', 'R01', 'E01'];
  static const preparatoryResearchCatalogIds = {
    'M13',
    'M16',
    'M19',
    'E03',
    'E20',
    'E24',
  };
  static ResearchTechnology technology(String id) => researchTechnologies[id]!;
  static int researchPointCost(String id) {
    final technology = researchTechnologies[id];
    if (technology == null || !technology.isPurchasable) return 0;
    if (starterResearchCatalogIds.contains(technology.catalogId)) return 24;
    return researchPointCostsByStage[technology.stage];
  }

  static String developmentTaskId(String id) => 'develop_$id';
  static String developmentOperationTaskId(String id) => 'operate_$id';
  static bool developmentIsPreparatory(String id) =>
      preparatoryResearchCatalogIds.contains(technology(id).catalogId);
  static ResearchUnlockEffect developmentEffect(String id) =>
      developmentIsPreparatory(id)
      ? ResearchUnlockEffect.research
      : technology(id).unlockEffect;
  static String developmentPlanet(String id) =>
      !developmentIsPreparatory(id) && technology(id).unlockFacilityId == 'mars'
      ? 'mars'
      : 'earth';
  static String developmentScopeLabel(String id) => developmentIsPreparatory(id)
      ? '月面展開に向けた地上実証'
      : developmentPlanet(id) == 'mars'
      ? '火星拠点への導入'
      : '地球都市への導入';
  static String developmentFacilityId(String id) =>
      developmentIsPreparatory(id) ? 'lab' : technology(id).unlockFacilityId;
  static int developmentCost(String id) =>
      developmentCostsByStage[technology(id).stage];
  static int developmentUpkeepPerMinute(String id) =>
      developmentUpkeepByStage[technology(id).stage];
  static int developmentCrewRequirement(String id) =>
      developmentEffect(id) == ResearchUnlockEffect.research
      ? 0
      : technology(id).unlockKind == ResearchUnlockKind.vehicle
      ? 2
      : 1;
  static int developmentResearchCapacity(String id) =>
      developmentEffect(id) == ResearchUnlockEffect.research ||
          technology(id).unlockKind == ResearchUnlockKind.facility
      ? 4 + technology(id).stage * 2
      : 0;
  static int developmentResearchRate(String id) => 2 + technology(id).stage;
  static int developmentEfficiencyBonus(String id) =>
      developmentBonusesByStage[technology(id).stage];
  static int developmentIncomePerMinute(String id) =>
      [6, 22, 65][technology(id).stage];

  static String developmentBenefitLabel(String id) {
    final bonus = developmentEfficiencyBonus(id);
    final capacity = developmentResearchCapacity(id);
    final effect = switch (developmentEffect(id)) {
      ResearchUnlockEffect.research => '研究運営能力 +$bonus%',
      ResearchUnlockEffect.production => '製造能力 +$bonus%',
      ResearchUnlockEffect.transport => '輸送運営能力 +$bonus%',
      ResearchUnlockEffect.construction => '現地建設能力 +$bonus%',
      ResearchUnlockEffect.income =>
        '事業収入 +${developmentIncomePerMinute(id)}ドル/分',
      ResearchUnlockEffect.partnership =>
        '共同事業収入 +${developmentIncomePerMinute(id)}ドル/分',
    };
    final research = capacity > 0
        ? '。実験へ最大$capacity名、基準${developmentResearchRate(id)}RP/人・分（生産能力と配分）'
        : '';
    return '稼働中：$effect$research。部署の能力上限内で適用';
  }

  static String? legacyResearchBranchFor(String id) {
    if (id == 'life_support') return _starterTasks[id]!.researchBranch;
    for (final task in _researchTasks) {
      if (task.id == id) return task.researchBranch;
    }
    return null;
  }

  static TaskDefinition _technologyTask(ResearchTechnology technology) {
    final legacy = <String, TaskDefinition>{
      'life_support': _starterTasks['life_support']!,
      for (final task in _researchTasks) task.id: task,
    }[technology.id];
    return TaskDefinition(
      id: technology.id,
      name: technology.name,
      facilityId: 'lab',
      // Kept only to finish already-paid old iterations and show their progress.
      durationSeconds: legacy?.durationSeconds ?? 1,
      cost: 0,
      unique: true,
      description: technology.description,
      science: technology.science,
      researchBranch: technology.field.label,
      researchStage: legacy != null && legacy.researchStage > technology.stage
          ? legacy.researchStage
          : technology.stage,
      prerequisites: technology.prerequisiteIds,
      alternativePrerequisites: technology.alternativePrerequisiteIds,
      unlockSummary: technology.unlockName,
      researchPromise: technology.description,
    );
  }

  static TaskDefinition _developmentTask(
    ResearchTechnology technology,
  ) => TaskDefinition(
    id: developmentTaskId(technology.id),
    name:
        '${technology.unlockName}を${developmentIsPreparatory(technology.id) ? '試作' : '導入'}',
    facilityId: developmentFacilityId(technology.id),
    durationSeconds: developmentDurationsByStage[technology.stage],
    cost: developmentCost(technology.id),
    requiredResearch: technology.id,
    developmentId: technology.id,
    description:
        '${technology.unlockDescription}\n${developmentScopeLabel(technology.id)}。完成後は休止状態で保有し、稼働と人員を配分します。',
    science: technology.science,
  );
  static TaskDefinition _developmentOperation(ResearchTechnology technology) {
    final cargo = ['M09', 'M26'].contains(technology.catalogId);
    final amount = technology.catalogId == 'M26' ? 12 : 1;
    return TaskDefinition(
      id: developmentOperationTaskId(technology.id),
      name: cargo
          ? '${technology.unlockName}で火星へ輸送'
          : '${technology.unlockName}の事業運転',
      facilityId:
          cargo ||
              developmentEffect(technology.id) == ResearchUnlockEffect.transport
          ? 'launch'
          : 'factory',
      durationSeconds: cargo
          ? (amount == 12 ? 1800 : 300)
          : [600, 3600, 14400][technology.stage],
      cost: cargo
          ? (amount == 12 ? 1800 : 260)
          : [180, 1600, 8000][technology.stage],
      reward: cargo ? 0 : [1500, 12500, 65000][technology.stage],
      requiredResearch: technology.id,
      requiredDevelopmentId: technology.id,
      inputResource: cargo ? 'earthKits' : null,
      inputAmount: amount,
      outputResource: cargo ? 'marsKits' : null,
      outputAmount: amount,
      description: cargo
          ? '対応機体と宇宙港を使い居住キットを輸送。機体の稼働維持費と航路枠が必要です。'
          : '導入済み設備を使う外部受注。担当部署の作業枠を使い、自前の製造・輸送と競合します。',
    );
  }

  static const initialSpecialists = 12;
  static const baselineDepartmentStaff = 6;
  static const maxSpecialists = 36;
  static const specialistTrainingCount = 2;
  static const staffEfficiencyPerPerson = 2;
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
      description: '共用工場を使い、完了時に220ドルを受領。居住キット製造と設備を取り合う。',
    ),
    'launch_contract': TaskDefinition(
      id: 'launch_contract',
      name: '外部受注・衛星打上げ',
      facilityId: 'launch',
      durationSeconds: 120,
      cost: 80,
      reward: 360,
      description: '共用宇宙港を使い、完了時に360ドルを受領。自前の火星輸送はその間待機。',
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
      description: '人口を60人、税収を毎分18ドル増やす。工場を使うため、受注・製造との配分が必要。',
    ),
  };

  /// Content values are provisional. The short starter loop is preserved for
  /// existing saves; these branches add investment choices over several days.
  static final tasks = <String, TaskDefinition>{
    ..._starterTasks,
    'train_specialists': TaskDefinition(
      id: 'train_specialists',
      name: '専門職を2名育成',
      facilityId: 'lab',
      durationSeconds: 180,
      cost: 600,
      description: '研究所を使い専門職を2名育成。工業へ配属後、機関運営で再配分できます。専門職は最大36名。人口そのものは増えません。',
    ),
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
    for (final technology in ResearchCatalog.purchasableTechnologies)
      technology.id: _technologyTask(technology),
    for (final technology in ResearchCatalog.purchasableTechnologies)
      developmentTaskId(technology.id): _developmentTask(technology),
    for (final technology in ResearchCatalog.purchasableTechnologies)
      if (!developmentIsPreparatory(technology.id) &&
          (technology.unlockKind == ResearchUnlockKind.vehicle ||
              [
                ResearchUnlockEffect.income,
                ResearchUnlockEffect.partnership,
                ResearchUnlockEffect.production,
              ].contains(technology.unlockEffect)))
        developmentOperationTaskId(technology.id): _developmentOperation(
          technology,
        ),
  };

  static const _researchTasks = <TaskDefinition>[
    TaskDefinition(
      id: 'process_design',
      name: '工程設計',
      facilityId: 'lab',
      durationSeconds: 180,
      cost: 200,
      unique: true,
      requiredResearch: 'urban_planning',
      researchBranch: '都市・産業',
      unlockSummary: '製造効率+3%（次の着工から）',
      description: '設備配置の研究と並行して、共用工場の工程を改善する。',
      science: 'ゲーム上の仮定：工程設計の成果を製造時間の短縮へ集約。費用と効率値は調整用です。',
    ),
    TaskDefinition(
      id: 'cargo_packaging',
      name: '輸送梱包',
      facilityId: 'lab',
      durationSeconds: 240,
      cost: 300,
      unique: true,
      requiredResearch: 'urban_planning',
      researchBranch: '輸送',
      unlockSummary: '輸送効率+3%（次の着工から）',
      description: '貨物の取り扱いを改良し、外部輸送と自前の輸送へ活かす。',
      science: 'ゲーム上の仮定：梱包と運用改善を共用宇宙港の工期へ反映。実際の惑星間航行時間を短縮する実証ではありません。',
    ),
    TaskDefinition(
      id: 'habitat_operations',
      name: '居住運用',
      facilityId: 'lab',
      durationSeconds: 300,
      cost: 450,
      unique: true,
      requiredResearch: 'urban_planning',
      prerequisites: ['life_support'],
      researchBranch: '居住・現地生産',
      unlockSummary: '火星建設効率+3%（次の着工から）',
      description: '居住施設の組み立てと運用を研究し、火星拠点の整備へつなぐ。',
      science: 'ゲーム上の仮定：閉鎖居住設備の運用知見を建設効率へ集約。屋外居住を実証した技術ではありません。',
    ),
    TaskDefinition(
      id: 'urban_planning',
      name: '都市基盤の計画',
      facilityId: 'lab',
      durationSeconds: 480,
      cost: 700,
      unique: true,
      researchBranch: '都市・産業',
      researchStage: 1,
      unlockSummary: '住宅Lv.2・研究地区・工業地区・高原科学都市',
      description: '住宅と産業の近接効果を活用し、研究または製造に都市を特化する。',
      science: 'ゲーム上の仮定：地区の機能集積を研究・製造の工期短縮として簡略化しています。',
    ),
    TaskDefinition(
      id: 'automated_fabrication',
      name: '自動化生産の実証',
      facilityId: 'lab',
      durationSeconds: 5400,
      cost: 20000,
      unique: true,
      researchRequirements: ResearchRequirements(
        districtCounts: {'industry': 1},
      ),
      requiredResearch: 'urban_planning',
      researchBranch: '都市・産業',
      researchStage: 2,
      unlockSummary: '自動化設備受注・キット6基製造・地球の他地区Lv.2・製造効率上限45%',
      description: '同じ工場で収益事業と自前の設備製造を選び分ける。',
      science: 'ゲーム上の仮定：自動化の成果を一括製造と地区増強に集約。費用・期間は仮値です。',
    ),
    TaskDefinition(
      id: 'industrial_network',
      name: '広域産業ネットワーク',
      facilityId: 'lab',
      durationSeconds: 86400,
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
      durationSeconds: 1800,
      cost: 6000,
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
      durationSeconds: 14400,
      cost: 120000,
      unique: true,
      researchRequirements: ResearchRequirements(
        districtCounts: {'spaceport': 1},
      ),
      requiredResearch: 'reusable_launch',
      researchBranch: '輸送',
      researchStage: 2,
      unlockSummary: '軌道補給受注・火星へ6基輸送・エリシウム・輸送効率上限45%',
      description: '輸送をまとめて実行し、複数の火星都市へ展開する余力を作る。',
      science: '構想：補給拠点を利用する輸送網。ゲーム上の仮定：軌道設備を独立建設せず研究完了で利用可能とします。',
    ),
    TaskDefinition(
      id: 'intercity_logistics',
      name: '惑星間の都市連携',
      facilityId: 'lab',
      durationSeconds: 86400,
      cost: 1200000,
      unique: true,
      requiredResearch: 'orbital_logistics',
      researchBranch: '輸送',
      researchStage: 3,
      unlockSummary: '全輸送の効率を追加+15%・ヘラス・輸送効率上限60%',
      description: '異なる地形の火星都市へ設備を送り、土地の使い方を分担する。',
      science: 'ゲーム上の仮定：惑星間・都市間の物流を共通在庫と輸送効率へ集約しています。',
    ),
    TaskDefinition(
      id: 'closed_ecology',
      name: '閉鎖循環の実証',
      facilityId: 'lab',
      durationSeconds: 10800,
      cost: 40000,
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
      durationSeconds: 43200,
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
    TaskDefinition(
      id: 'oxygen_pilot',
      name: '火星の空気から酸素へ',
      facilityId: 'lab',
      durationSeconds: 2700,
      cost: 14000,
      unique: true,
      requiredResearch: 'life_support',
      researchRequirements: ResearchRequirements(marsHabitats: 1),
      researchBranch: '居住・現地生産',
      researchStage: 1,
      researchPromise: '火星建設効率 +4%',
      unlockSummary: '火星建設効率+4%（次の着工から・既存の上限内）',
      description: '居住区に小さな酸素製造実験室を置く。地球から運ぶ技術を、現地で作る技術へ育てる。',
      science:
          '実証：NASAのMOXIEは火星の二酸化炭素から酸素を取り出し、2021〜2023年に計122gを生成しました。\n'
          '応用構想：連続運転、大型化、酸素の貯蔵が次の課題です。火星の大気全体を呼吸可能にした実験ではありません。\n'
          'ゲーム上の仮定：設備組立の知見を火星建設効率+4%に集約します。酸素在庫や大気組成は変えません。\n'
          '出典：NASA/JPL-Caltech（2023）\n'
          'https://www.nasa.gov/solar-system/nasas-oxygen-generating-experiment-moxie-completes-mars-mission/',
    ),
    TaskDefinition(
      id: 'radiation_shelters',
      name: '宇宙線から守る住まい',
      facilityId: 'lab',
      durationSeconds: 3600,
      cost: 18000,
      unique: true,
      requiredResearch: 'life_support',
      researchRequirements: ResearchRequirements(marsHabitats: 1),
      researchBranch: '居住・現地生産',
      researchStage: 1,
      researchPromise: '火星建設効率 +5%',
      unlockSummary: '火星建設効率+5%（次の着工から・既存の上限内）',
      description: '土と複合材を重ねた防護構造を設計する。窓の向こうの赤い世界を眺めながら、安心して眠れる街を目指す。',
      science:
          '数値モデル：GakisとAtriは観測値と照合したGeant4モデルで、火星表面の放射線と材料による遮蔽を検討しました。\n'
          '応用構想：レゴリス（土）だけで完全に防げるという結論ではなく、複合材、厚さ、二次粒子などの検討が必要です。\n'
          'ゲーム上の仮定：防護構造の標準化を火星建設効率+5%へ集約。被曝量、事故率、屋外居住条件は変えません。\n'
          '出典：Gakis & Atri（2022、2024改訂）\n'
          'https://arxiv.org/abs/2205.13786',
    ),
    TaskDefinition(
      id: 'electric_tugs',
      name: '青い光の電気推進',
      facilityId: 'lab',
      durationSeconds: 7200,
      cost: 40000,
      unique: true,
      requiredResearch: 'reusable_launch',
      researchRequirements: ResearchRequirements(
        districtCounts: {'spaceport': 1},
      ),
      researchBranch: '輸送',
      researchStage: 1,
      researchPromise: '輸送効率 +6%',
      unlockSummary: '共用宇宙港の輸送効率+6%（次の着手から・既存の上限内）',
      description: '小さな推力を積み重ねて宇宙を渡る。化学ロケットと電気推進を組み合わせる貨物運用を研究する。',
      science:
          '実証：電気推進は探査機や人工衛星で使われています。太陽電池などの電力で推進剤を加速し、少ない推進剤で運用できますが、推力は小さくなります。\n'
          '応用構想：大型の惑星間貨物輸送には電源、長期間の運転、航路設計が必要です。地表からの打上げを置き換えません。\n'
          'ゲーム上の仮定：運用全体を共用宇宙港の効率+6%へ簡略化。実際の飛行時間短縮を示す数値ではありません。\n'
          '出典：NASA Solar Electric Propulsion（技術概要・2026年10月確認）\n'
          'https://www.nasa.gov/space-technology-mission-directorate/tdm/solar-electric-propulsion/',
    ),
    TaskDefinition(
      id: 'surface_fission',
      name: '長い夜を越える電源',
      facilityId: 'lab',
      durationSeconds: 21600,
      cost: 150000,
      unique: true,
      requiredResearch: 'closed_ecology',
      researchRequirements: ResearchRequirements(
        districtCounts: {'mars_lab': 1},
      ),
      researchBranch: '都市・産業',
      researchStage: 1,
      researchPromise: '研究 +6%・火星建設 +4%',
      unlockSummary: '研究効率+6%・火星建設効率+4%（次の着手から・既存の上限内）',
      description: '火星の現地研究地区で小型原子炉の利用計画を作る。日照に頼りきらず、実験と暮らしを支える。',
      science:
          '地上実証：NASAと米国エネルギー省は2018年にKRUSTY試験を実施し、小型核分裂電源の運転を地上で検証しました。\n'
          '応用構想：火星への輸送、設置、放熱、防護、保守は別の課題です。本研究は火星での利用案であり、月面拠点を開設するものではありません。\n'
          'ゲーム上の仮定：安定電源の効果を研究+6%と火星建設+4%へ集約。電力在庫や独立した原子炉施設は追加しません。\n'
          '出典：NASA（2018）KRUSTY地上試験\n'
          'https://www.nasa.gov/news-release/demonstration-proves-nuclear-fission-system-can-provide-space-exploration-power/',
    ),
    TaskDefinition(
      id: 'orbital_gardens',
      name: '赤い星に育つ食卓',
      facilityId: 'lab',
      durationSeconds: 28800,
      cost: 180000,
      unique: true,
      requiredResearch: 'closed_ecology',
      researchRequirements: ResearchRequirements(
        districtCounts: {'greenhouse': 1},
      ),
      researchBranch: '居住・現地生産',
      researchStage: 1,
      researchPromise: '研究 +5%・火星建設 +5%',
      unlockSummary: '研究効率+5%・火星建設効率+5%（次の着手から・既存の上限内）',
      description: '温室で種から次の種へ命をつなぐ。初めて収穫した葉を食卓に並べ、補給に頼る暮らしを少しずつ変えていく。',
      science:
          '実証：ISSのVeggieでは管理された環境で作物を栽培しています。\n'
          '応用構想：火星での農業には光、水、栄養、病害対策が必要です。少量の栽培成功は、食料の完全自給や火星屋外での生育を意味しません。\n'
          'ゲーム上の仮定：栽培データを研究+5%と現地施工の効率+5%へ集約。食料、人口、生態系は自動的に増えません。\n'
          '出典：NASA（2014）VeggieのISS稼働報告\n'
          'https://www.nasa.gov/missions/station/veggie-plant-growth-system-activated-on-international-space-station/',
    ),
    TaskDefinition(
      id: 'regolith_printing',
      name: '赤土から街を刷る',
      facilityId: 'lab',
      durationSeconds: 43200,
      cost: 480000,
      unique: true,
      requiredResearch: 'local_resources',
      prerequisites: ['automated_fabrication'],
      researchRequirements: ResearchRequirements(
        districtCounts: {'extractor': 1},
      ),
      researchBranch: '都市・産業',
      researchStage: 2,
      researchPromise: '製造 +5%・火星建設 +8%',
      unlockSummary: '製造効率+5%・火星建設効率+8%（次の着工から・既存の上限内）',
      description: '地球で育てた自動化と、火星で得た資源を結ぶ。赤い土を積み重ね、次の街の壁を現地で作る。',
      science:
          '地上実証：NASAの3D-Printed Habitat Challengeは2019年までに材料・構造・縮小居住構造物の自動造形を競いました。\n'
          '応用構想：実際の火星の土、低温、低圧、粉塵の下で作る居住施設は未実証です。気密性と設備は別途必要です。\n'
          'ゲーム上の仮定：材料加工を製造+5%と火星建設+8%へ集約。居住キットは従来どおり必要です。\n'
          '出典：NASA（2019）3D-Printed Habitat Challenge\n'
          'https://www.nasa.gov/prizes-challenges-and-crowdsourcing/centennial-challenges/3d-printed-habitat-challenge/',
    ),
  ];

  /// Efficiency grows with demonstrated research, rather than filling its
  /// final cap as soon as the first scientific city opens.
  static const efficiencyCapsByStage = [30, 30, 45, 60];

  /// Provisional marginal investment prices. Upgrading saves land and shared
  /// equipment time; expansion gains fresh terrain but develops infrastructure.
  static const districtCostPercentByLevel = [100, 175, 250];
  static const districtDurationPercentByLevel = [100, 80, 120];
  static const newPlotDevelopmentPercent = 12;
  static const cityStageThresholds = [0, 1, 8, 20];
  static const cityStageNames = ['候補地', '拠点', '成長都市', '中核都市'];
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
    'process_design': {'factory': 3},
    'cargo_packaging': {'launch': 3},
    'habitat_operations': {'mars': 3},
    'industrial_network': {'factory': 10},
    'reusable_launch': {'launch': 10},
    'intercity_logistics': {'launch': 15},
    'regional_habitats': {'mars': 10},
    'oxygen_pilot': {'mars': 4},
    'radiation_shelters': {'mars': 5},
    'electric_tugs': {'launch': 6},
    'surface_fission': {'lab': 6, 'mars': 4},
    'orbital_gardens': {'lab': 5, 'mars': 5},
    'regolith_printing': {'factory': 5, 'mars': 8},
  };
  static const optionalFrontierResearchIds = [
    'oxygen_pilot',
    'radiation_shelters',
    'electric_tugs',
    'surface_fission',
    'orbital_gardens',
    'regolith_printing',
  ];

  static const agencyMetricDescriptions = {
    'fame': '知名度：研究1件+4、完成地区1区画+2、居住・輸送実績1件+8、提携選択1件+3。上限100。提携の解禁と活動の目安に使います。独立した収益効果はありません。',
    'technology':
        '技術力：研究1件+6、完成地区の総レベル+1ずつ。上限100。提携解禁に使います。実際の効率は各研究・地区・人員・提携の効果で決まります。',
    'friendship': '友好度：初期10＋選択した提携・支援の加点。上限100。宇宙支援の解禁に使います。追加の割引・自動支援はありません。',
    'spaceContribution': '宇宙支援貢献：輸送・居住分野の研究1件+3、輸送・居住実績1件+8、火星地区総レベル×2、提携選択の加点。上限100。宇宙支援の解禁に使います。追加報酬は自動発生しません。',
  };
  static const partnerships = <String, PartnershipDefinition>{
    'research_exchange': PartnershipDefinition(
      id: 'research_exchange',
      title: '都市技術の共同研究',
      partner: 'アーク技術共同体（架空）',
      description: '研究の恒久改善か、今回の開発資金かを選びます。各提案は一度だけ選択でき、後から変更できません。',
      requiredResearch: 'urban_planning',
      minimumDistricts: 1,
      minimumFame: 6,
      minimumTechnology: 6,
      choices: [
        PartnershipChoice(
          id: 'technology',
          title: '技術提携',
          description: '研究効率+4%、製造効率+2%。設備上限内で次の着工から。',
          friendship: 6,
          spaceContribution: 2,
          efficiencyBonuses: {'lab': 4, 'factory': 2},
        ),
        PartnershipChoice(
          id: 'funding',
          title: '開発資金を受ける',
          description: '開発支援1,200ドルを一度だけ受領。',
          funding: 1200,
          friendship: 3,
          spaceContribution: 1,
        ),
      ],
    ),
    'industrial_alliance': PartnershipDefinition(
      id: 'industrial_alliance',
      title: '工業設備の共同開発',
      partner: 'ヘリオス工業連合（架空）',
      description: '完成した工業地区を実証に、製造技術か設備投資の支援を選びます。',
      requiredDistrict: 'industry',
      minimumTechnology: 12,
      choices: [
        PartnershipChoice(
          id: 'technology',
          title: '製造技術で提携',
          description: '製造効率+6%。設備上限内で次の着工から。',
          friendship: 6,
          spaceContribution: 2,
          efficiencyBonuses: {'factory': 6},
        ),
        PartnershipChoice(
          id: 'funding',
          title: '設備資金を受ける',
          description: '設備支援1,800ドルを一度だけ受領。',
          funding: 1800,
          friendship: 3,
          spaceContribution: 1,
        ),
      ],
    ),
    'orbital_support': PartnershipDefinition(
      id: 'orbital_support',
      title: '火星輸送への国際支援',
      partner: 'オーロラ宇宙協力国（架空）',
      description: '初めての火星輸送を受け、共同技術開発か次の輸送への支援を選びます。',
      requiredAchievement: 'first_landing',
      minimumFriendship: 13,
      minimumSpaceContribution: 11,
      choices: [
        PartnershipChoice(
          id: 'technology',
          title: '宇宙技術で提携',
          description: '研究効率+4%、輸送効率+4%。設備上限内で次の着工から。',
          friendship: 8,
          spaceContribution: 6,
          efficiencyBonuses: {'lab': 4, 'launch': 4},
        ),
        PartnershipChoice(
          id: 'funding',
          title: '宇宙開発資金を受ける',
          description: '宇宙支援2,400ドルを一度だけ受領。',
          funding: 2400,
          friendship: 4,
          spaceContribution: 3,
        ),
      ],
    ),
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
      setupCost: 1200,
      setupDurationSeconds: 900,
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
      setupCost: 1600,
      setupDurationSeconds: 2700,
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
      setupCost: 2400,
      setupDurationSeconds: 5400,
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
      level2Research: 'urban_planning',
      cost: 350,
      durationSeconds: 300,
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
      durationSeconds: 600,
      upkeepPerMinute: 4,
      requiredResearch: 'urban_planning',
      description: '研究効率+4%。高台で+2%、隣接住宅で+1%、発電地区で+2%。',
    ),
    'industry': DistrictDefinition(
      id: 'industry',
      name: '工業地区',
      planet: 'earth',
      cost: 1200,
      durationSeconds: 480,
      upkeepPerMinute: 5,
      requiredResearch: 'urban_planning',
      description: '製造効率+4%。鉱床で+2%、宇宙港で+1%、発電地区で+2%。住宅の隣接収入は低下。',
    ),
    'solar': DistrictDefinition(
      id: 'solar',
      name: '発電地区',
      planet: 'earth',
      cost: 650,
      durationSeconds: 300,
      upkeepPerMinute: 1,
      description: '隣接する研究・工業・宇宙港地区の効率を+2%。高台では追加+1%。',
    ),
    'spaceport': DistrictDefinition(
      id: 'spaceport',
      name: '宇宙港地区',
      planet: 'earth',
      cost: 2400,
      durationSeconds: 1200,
      upkeepPerMinute: 6,
      requiredResearch: 'reusable_launch',
      description: '輸送効率+4%。海岸で+2%、工業で+1%、発電地区で+2%。',
    ),
    'mars_habitat': DistrictDefinition(
      id: 'mars_habitat',
      name: '火星居住地区',
      planet: 'mars',
      cost: 700,
      durationSeconds: 600,
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
    this.setupCost = 0,
    this.setupDurationSeconds = 0,
    this.width = 5,
    this.height = 5,
  });
  final String id, name, planet, description;
  final double latitude, longitude;
  final String? requiredResearch;
  final int width, height, setupCost, setupDurationSeconds;
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
    this.level2Research,
    this.baseTaxPerMinute = 0,
    this.upkeepPerMinute = 0,
    this.maxLevel = 3,
    this.residents = 0,
    this.allowedTerrain = const [],
  });
  final String id, name, planet, description;
  final String? requiredResearch, level2Research;
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
  String researchForUpgrade(int targetLevel) => targetLevel == 2
      ? level2Research ??
            (planet == 'earth' ? 'automated_fabrication' : 'local_resources')
      : (planet == 'earth' ? 'industrial_network' : 'regional_habitats');
  String taskId({bool upgrade = false}) =>
      '${upgrade ? 'upgrade' : 'district'}_$id';
  int costForLevel(int level) =>
      (cost *
              GameContent.districtCostPercentByLevel[level.clamp(1, maxLevel) -
                  1] +
          99) ~/
      100;
  int durationMsForLevel(int level) =>
      (durationSeconds *
              1000 *
              GameContent.districtDurationPercentByLevel[level.clamp(
                    1,
                    maxLevel,
                  ) -
                  1] +
          99) ~/
      100;
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
