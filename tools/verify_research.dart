import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

/// Direct Dart invariants, independent of Flutter's localhost test server.
/// This verifies deterministic simulation and migration, not long-term balance.
void main() {
  try {
    _verifyFrontierAndUnlocks();
    _verifyAllDevelopments();
    _verifyPartitions();
    _verifyPersonnelAndBudget();
    _verifyLegacyMigration();
    stdout.writeln(
      'PASS: 98研究・都市への導入・保存再読込、100seedの一括/分割、'
      '人員・資金休止、旧研究・初回案内移行',
    );
  } catch (error, stack) {
    stderr.writeln('研究進行検証に失敗: $error\n$stack');
    exitCode = 1;
  }
}

final _epoch = DateTime.utc(2026, 10, 20);
const _scale = GameState.researchPointScale;

void _check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

void _ok(String? reason, String label) =>
    _check(reason == null, '$label: $reason');

String _id(String catalogId) => ResearchCatalog.idForCatalog(catalogId);

GameState _copy(GameState state) => GameState.fromJson(
  jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
);

GameEngine _fresh({int money = 1000000000}) => GameEngine(
  GameState.initial(_epoch)
    ..firstRunTutorial = FirstRunTutorialStep.completed
    ..openingSeen = true
    ..money = money,
);

String _city(String technologyId) => GameContent.cities.values
    .firstWhere(
      (city) => city.planet == GameContent.developmentPlanet(technologyId),
    )
    .id;

void _build(GameEngine engine, String id) {
  _ok(engine.enqueueDevelopment(id, cityId: _city(id)), '設備導入 $id');
  final plan = engine.state.plans.last;
  _check(plan.status == 'running', '導入が始まらない $id: ${plan.stopReason}');
  final before = engine.state.moneyUnits;
  engine.advanceBy(Duration(milliseconds: plan.remainingMs));
  _check(plan.isFinished && plan.completedRuns == 1, '導入が一度だけ完了 $id');
  _check(engine.state.developments.contains(id), '設備が保有状態になる $id');
  _check(engine.state.developmentCityIds[id] == _city(id), '都市帰属 $id');
  _check(engine.state.developmentEnabled[id] == false, '完成時は休止 $id');
  _check(engine.state.moneyUnits <= before, '導入中の無償収入なし $id');
}

void _verifyFrontierAndUnlocks() {
  final engine = _fresh();
  final initial = GameContent.starterResearchCatalogIds.map(_id).toSet();
  _check(
    engine.state.discoveredResearchIds.length == 4 &&
        engine.state.discoveredResearchIds.containsAll(initial),
    '初期表示は4分野の入口だけ',
  );
  engine.state.researchPointUnits = 1000000 * _scale;
  final hiddenPoints = engine.state.researchPointUnits;
  _check(engine.unlockResearch(_id('M26')) != null, '未発見の大型輸送は解放不可');
  _check(engine.state.researchPointUnits == hiddenPoints, '拒否はRPを消費しない');
  _ok(engine.unlockResearch(_id('E01')), '初期電源研究');
  _check(engine.state.isResearchDiscovered(_id('E13')), '都市基盤を先端炉より先に発見');
  _ok(engine.unlockResearch(_id('R01')), '初期資源研究');
  _check(engine.state.isResearchDiscovered(_id('R09')), '大気資源の入口を発見');
  _check(engine.state.isResearchDiscovered(_id('R15')), '資源研究から製造基盤を発見');
  _check(!engine.state.isResearchDiscovered(_id('R07')), '水源研究前には浄水を発見しない');
  _ok(engine.unlockResearch(_id('R09')), '大気資源研究');
  _check(!engine.state.isResearchDiscovered(_id('R07')), '無関係の解放件数では浄水を発見しない');
  final before = engine.state.researchPointUnits;
  final money = engine.state.moneyUnits;
  _check(engine.unlockResearch(_id('R09')) != null, '二重解放不可');
  _check(before == engine.state.researchPointUnits, '二重RP支払いなし');
  _check(money == engine.state.moneyUnits, '通常研究の追加資金課金なし');
}

void _verifyAllDevelopments() {
  var engine = _fresh();
  engine.state.researchPointUnits = 1000000000 * _scale;
  final pending = ResearchCatalog.purchasableTechnologies
      .map((t) => t.id)
      .toSet();
  var passes = 0;
  while (pending.isNotEmpty && passes++ < 100) {
    final previous = pending.length;
    for (final id in pending.toList()) {
      if (!engine.state.isResearchDiscovered(id) ||
          engine.researchRequirementReasons(id).isNotEmpty) {
        continue;
      }
      _ok(engine.unlockResearch(id), '全研究経路 $id');
      pending.remove(id);
    }
    _check(pending.length < previous, '到達不能な研究 ${pending.join(', ')}');
  }
  _check(engine.state.research.length == 98, '購入可能研究98件');
  _check(engine.state.developments.isEmpty, '研究だけで設備を無償取得しない');
  engine.state.achievements.add('first_landing');
  for (final technology in ResearchCatalog.purchasableTechnologies) {
    _build(engine, technology.id);
    final snapshot = jsonEncode(engine.state.toJson());
    engine = GameEngine(_copy(engine.state));
    _check(
      jsonEncode(engine.state.toJson()) == snapshot,
      '導入後再読込 ${technology.id}',
    );
    _check(
      engine.enqueueDevelopment(technology.id, cityId: _city(technology.id)) !=
          null,
      '同一設備を二重建設しない ${technology.id}',
    );
  }
  _check(engine.state.developments.length == 98, '全98解放先を実際に導入可能');
  _check(engine.state.developmentWorkers == 0, '休止中設備が人員を取らない');
}

void _verifyPartitions() {
  for (var seed = 0; seed < 100; seed++) {
    final random = Random(seed);
    final setup = _fresh();
    final bio = _id('B01');
    setup.state.research.add(bio);
    _build(setup, bio);
    _ok(setup.setDevelopmentEnabled(bio, true), '試験設備稼働 seed=$seed');
    _ok(setup.assignDevelopmentResearchers(bio, 1), '試験設備配属 seed=$seed');
    setup.state.researchPointUnits = random.nextInt(24 * _scale);
    setup.state.money = seed.isEven ? 1 : 10000;
    _ok(setup.enqueue('life_support'), 'RP待ち予約 seed=$seed');
    _ok(setup.enqueue('factory_contract', repeats: 3), '製造受注 seed=$seed');
    _ok(setup.enqueue('launch_contract', repeats: 2), '打上げ受注 seed=$seed');
    final one = GameEngine(_copy(setup.state));
    final split = GameEngine(_copy(setup.state));
    final duration = 100000 + random.nextInt(43200000);
    one.advanceTo(_epoch.add(Duration(milliseconds: duration)));
    var elapsed = 0;
    while (elapsed < duration) {
      elapsed = min(duration, elapsed + 1 + random.nextInt(1000000));
      split.advanceTo(_epoch.add(Duration(milliseconds: elapsed)));
      if (random.nextInt(7) == 0) {
        final restored = _copy(split.state);
        _check(
          jsonEncode(restored.toJson()) == jsonEncode(split.state.toJson()),
          '途中保存 seed=$seed',
        );
      }
    }
    _check(
      jsonEncode(one.state.toJson()) == jsonEncode(split.state.toJson()),
      '一括/分割不一致 seed=$seed',
    );
    final points = split.state.researchPointUnits;
    final simulated = split.state.simulatedMs;
    split.advanceTo(_epoch.subtract(const Duration(days: 1)));
    _check(split.state.researchPointUnits == points, '時計後退RP保持 seed=$seed');
    _check(split.state.simulatedMs == simulated, '時計後退進行なし seed=$seed');
    _check(split.state.moneyUnits >= 0, '負債を作らない seed=$seed');
    _check(
      split.state.industrialWorkers >= split.state.reservedIndustrialWorkers,
      '工業員確保 seed=$seed',
    );
    _check(
      split.state.researchers >= split.state.minAssignableResearchers,
      '研究者確保 seed=$seed',
    );
  }
}

void _verifyPersonnelAndBudget() {
  final laboratory = _fresh();
  final analysis = _id('R01');
  laboratory.state.research.add(analysis);
  _build(laboratory, analysis);
  final baseRate = laboratory.state.researchPointsPerMinute;
  _ok(laboratory.setDevelopmentEnabled(analysis, true), '分析所の稼働');
  _check(
    laboratory.state.researchPointsPerMinute == baseRate,
    '空の専門研究設備からRPを生まない',
  );
  _ok(laboratory.assignDevelopmentResearchers(analysis, 1), '分析所への研究者配属');
  _check(laboratory.state.researchPointsPerMinute > baseRate, '専門配属で研究産出が変わる');
  _check(
    laboratory.state.researchPointsPerMinuteForResearchers(
          laboratory.state.researchers,
        ) ==
        laboratory.state.researchPointsPerMinute,
    '配属予測と実際の産出が一致',
  );
  final engine = _fresh();
  final bio = _id('B01');
  engine.state.research.add(bio);
  _build(engine, bio);
  _ok(engine.setDevelopmentEnabled(bio, true), '設備稼働');
  _ok(engine.assignDevelopmentResearchers(bio, 1), '設備の研究者配属');
  _check(engine.state.specializedResearchers == 1, '専用配属');
  _check(engine.state.labResearchers == engine.state.researchers - 1, '二重配属なし');
  _check(engine.assignResearchers(0) != null, '配属中の研究者を奪えない');
  final facility = GameContent.developmentFacilityId(bio);
  _ok(engine.setFacilityEnabled(facility, false), '共用部署休止');
  _ok(engine.assignResearchers(0), '休止後は人員解放');
  _check(engine.setDevelopmentEnabled(bio, true) != null, '休止部署内の隠れた稼働不可');
  _ok(engine.setFacilityEnabled(facility, true), '共用部署再開');
  _check(engine.state.specializedResearchers == 0, '配属を勝手に復元しない');
  _copy(engine.state);
  _ok(engine.assignResearchers(6), '基礎研究へ再配属');
  final vehicle = _id('M25');
  engine.state.research.add(vehicle);
  _build(engine, vehicle);
  _ok(engine.enqueue('factory_contract'), '支払済み製造');
  final paid = engine.state.plans.last;
  _check(
    engine.setDevelopmentEnabled(vehicle, true) != null,
    '支払済み作業の工業員を奪えない',
  );
  engine.advanceBy(Duration(milliseconds: paid.remainingMs));
  _ok(engine.setDevelopmentEnabled(vehicle, true), '製造完了後に機体稼働');
  engine.state.money = 0;
  engine.advanceBy(const Duration(minutes: 2));
  _check(
    engine.state.moneyUnits >= 0 && engine.state.netPerMinute >= 0,
    '低資金の自動休止と再建',
  );
  _copy(engine.state);

  final joint = _id('M20');
  engine.state.research.add(joint);
  engine.state.money = 1000000;
  for (final id in GameContent.facilities.keys) {
    _ok(engine.setFacilityEnabled(id, true), '共用部署復旧');
  }
  _build(engine, joint);
  _check(engine.setDevelopmentEnabled(joint, true) != null, '技術だけで共同事業を稼働しない');

  // The new precise-landing vehicle must open the same settlement gate as the
  // basic cargo route when it is used for the first actual delivered kit.
  final freight = _fresh();
  final landing = _id('M09');
  freight.state.research.add(landing);
  _build(freight, landing);
  _ok(freight.setDevelopmentEnabled(landing, true), '精密着陸船稼働');
  freight.state.earthKits = 1;
  _ok(
    freight.enqueue(GameContent.developmentOperationTaskId(landing)),
    '精密着陸便',
  );
  final flight = freight.state.plans.last;
  freight.advanceBy(Duration(milliseconds: flight.remainingMs));
  _check(freight.state.marsKits == 1, '精密着陸便の貨物受渡');
  _check(freight.state.achievements.contains('first_landing'), '新輸送便の初着陸実績');
}

Map<String, dynamic> _legacy({bool paid = false, bool tutorial = false}) {
  final current = GameState.initial(_epoch)
    ..openingSeen = true
    ..firstRunTutorial = tutorial
        ? FirstRunTutorialStep.startResearch
        : FirstRunTutorialStep.completed
    ..money = 100000
    ..specialistCount = 18;
  final json = current.toJson()
    ..['contentVersion'] = 'district-6'
    ..['nextPlanId'] = paid ? 2 : 1;
  for (final key in [
    'researchPointUnits',
    'developments',
    'developmentEnabled',
    'developmentResearchers',
    'developmentCityIds',
  ]) {
    json.remove(key);
  }
  if (paid) {
    json['plans'] = [
      {
        'id': 'plan-1',
        'taskId': 'life_support',
        'remainingRepeats': 1,
        'completedRuns': 0,
        'status': 'running',
        'stopReason': '',
        'remainingMs': 90000,
        'iterationDurationMs': 120000,
        'iterationSpecialists': 6,
        'cityId': null,
        'plotIndex': null,
        'targetLevel': null,
      },
    ];
  }
  return json;
}

void _verifyLegacyMigration() {
  final paid = GameEngine(GameState.fromJson(_legacy(paid: true)));
  _check(paid.state.specialistCount == 18, '旧専門職を保持');
  _check(paid.state.researchPointUnits == 0, '通常移行へ遡及RPなし');
  _check(paid.state.labResearchers == 0, '旧支払済み研究者の二重利用なし');
  paid.advanceBy(const Duration(seconds: 90));
  _check(paid.state.research.contains('life_support'), '旧支払済み工期で完了');
  _check(paid.state.researchPointUnits == 0, '旧研究完了前のRPを遡及しない');
  final receipt = jsonEncode(paid.state.toJson());
  final resumed = GameEngine(_copy(paid.state));
  resumed.advanceTo(_epoch);
  _check(jsonEncode(resumed.state.toJson()) == receipt, '同時刻再起動で二重完了なし');

  final tutorial = GameEngine(GameState.fromJson(_legacy(tutorial: true)));
  _check(tutorial.state.introductionPausesClock, '移行後の案内保護を保持');
  _check(
    tutorial.state.researchPointUnits ==
        GameContent.researchPointCost('life_support') * _scale,
    '止まった案内に初期研究予算を一度引継ぎ',
  );
  _ok(tutorial.unlockResearch('life_support'), '保護中の最初の研究');
  final zero = _copy(tutorial.state);
  _check(zero.researchPointUnits == 0, '使用済み初期予算を再付与しない');
  final noRescue = GameState.fromJson(_legacy(paid: true, tutorial: true));
  _check(noRescue.researchPointUnits == 0, '旧支払済み研究には二重支援なし');
}
