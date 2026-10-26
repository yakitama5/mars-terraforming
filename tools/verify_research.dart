import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

/// Funded content fixtures, not a normal-play duration or balance claim.
void main() {
  try {
    verifyAllDevelopments();
    verifyPartitions();
    verifyMigration();
    stdout.writeln(
      'PASS: 都市条件下の98研究・導入・保存、100seed上限/一括分割/時計後退、旧支払済み/未着手研究。全研究試験は基盤と予算を投入。',
    );
  } catch (error, stack) {
    stderr.writeln('研究進行検証に失敗: $error\n$stack');
    exitCode = 1;
  }
}

final epoch = DateTime.utc(2026, 10, 26);
const scale = GameState.researchPointScale;
void check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

void ok(String? reason, String label) =>
    check(reason == null, '$label: $reason');
GameState copy(GameState state) => GameState.fromJson(
  jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
);
GameEngine fresh() => GameEngine(
  GameState.initial(epoch)
    ..openingSeen = true
    ..firstRunTutorial = FirstRunTutorialStep.completed,
);

void verifyAllDevelopments() {
  final engine = fresh(), state = fresh().state;
  check(engine.state.discoveredResearchIds.length == 4, '最初は4入口');
  engine.state.population = 0;
  final before = jsonEncode(engine.state.toJson());
  check(engine.unlockResearch('local_resources') != null, '都市基盤不足を拒否');
  check(jsonEncode(engine.state.toJson()) == before, '拒否は状態を変えない');
  state
    ..money = 1000000000
    ..population = 6000
    ..marsResidents = 48
    ..marsHabitats = 2
    ..researchPointUnits = 1000000000 * scale;
  state.legacyUnlockedPlanets.addAll(['moon', 'mars']);
  state.achievements.addAll([
    'first_launch',
    'first_landing',
    'mars_route_open',
  ]);
  state.surveyedSites.addAll(['earth_delta:8', 'earth_delta:13']);
  state.connectedGridCities.addAll(GameContent.cities.keys);
  for (final id in state.facilities.keys.toList()) {
    state.facilities[id] = true;
  }
  for (final entry in <String, int>{
    'housing': 2,
    'solar': 3,
    'industry': 2,
    'spaceport': 2,
    'moon_outpost': 1,
    'moon_spaceport': 1,
    'mars_habitat': 2,
    'mars_lab': 1,
    'greenhouse': 1,
    'extractor': 1,
  }.entries) {
    final definition = GameContent.districts[entry.key]!;
    final city = GameContent.cities.values.firstWhere(
      (c) => c.planet == definition.planet,
    );
    for (var count = 0; count < entry.value; count++) {
      final plot = List.generate(city.plotCount, (i) => i).firstWhere(
        (i) =>
            state.districtAt(city.id, i) == null &&
            (definition.allowedTerrain.isEmpty ||
                definition.allowedTerrain.contains(city.terrainAt(i))),
      );
      final district = DistrictState(
        cityId: city.id,
        plotIndex: plot,
        districtId: entry.key,
      );
      state.districts[district.key] = district;
    }
  }
  final game = GameEngine(state);
  final pending = ResearchCatalog.purchasableTechnologies
      .map((t) => t.id)
      .toSet();
  var passes = 0;
  while (pending.isNotEmpty) {
    var progress = false;
    for (final id in pending.toList()) {
      if (!state.isResearchDiscovered(id) ||
          game.researchRequirementReasons(id).isNotEmpty) {
        continue;
      }
      final assets = state.developments.length;
      ok(game.unlockResearch(id), '全研究経路 $id');
      check(state.developments.length == assets, '研究だけで設備を無償取得しない');
      final city = GameContent.cities.values
          .firstWhere((c) => c.planet == GameContent.developmentPlanet(id))
          .id;
      ok(game.enqueueDevelopment(id, cityId: city), '設備導入 $id');
      final plan = state.plans.last;
      check(plan.status == 'running', '導入は即時着工 $id');
      game.advanceBy(Duration(milliseconds: plan.remainingMs));
      check(state.developments.contains(id), '設備保有 $id');
      if (GameContent.developmentEffect(id) == ResearchUnlockEffect.research ||
          id == 'urban_planning') {
        ok(game.setDevelopmentEnabled(id, true), '研究/配電基盤稼働 $id');
      }
      check(game.enqueueDevelopment(id, cityId: city) != null, '二重導入を拒否 $id');
      pending.remove(id);
      progress = true;
      check(
        jsonEncode(copy(state).toJson()) == jsonEncode(state.toJson()),
        '導入後保存 $id',
      );
    }
    check(
      progress && ++passes < 100,
      '到達不能: ${pending.map((id) => '$id:${game.researchRequirementReasons(id)}').join(', ')}',
    );
  }
  check(
    state.research.length == 98 && state.developments.length == 98,
    '98研究と導入',
  );
  check(GameEngine(copy(state)).state.developments.length == 98, '全設備の再起動保持');
}

void verifyPartitions() {
  for (var seed = 0; seed < 100; seed++) {
    final random = Random(seed), setup = fresh();
    setup.state.money = seed.isEven ? 1 : setup.state.moneyCapacity - 10;
    setup.state.researchPointUnits = random.nextInt(24 * scale);
    final receipt = jsonEncode(setup.state.toJson());
    check(setup.unlockResearch('life_support') != null, 'RP不足は再選択');
    check(jsonEncode(setup.state.toJson()) == receipt, 'RP不足で予約なし');
    ok(setup.enqueue('factory_contract', repeats: 3), '製造反復');
    ok(setup.enqueue('launch_contract', repeats: 2), '輸送反復');
    final one = GameEngine(copy(setup.state));
    var split = GameEngine(copy(setup.state));
    final duration = 100000 + random.nextInt(43200000);
    one.advanceTo(epoch.add(Duration(milliseconds: duration)));
    var elapsed = 0;
    while (elapsed < duration) {
      elapsed = min(duration, elapsed + 1 + random.nextInt(1000000));
      split.advanceTo(epoch.add(Duration(milliseconds: elapsed)));
      if (random.nextInt(7) == 0) split = GameEngine(copy(split.state));
    }
    check(
      jsonEncode(one.state.toJson()) == jsonEncode(split.state.toJson()),
      '一括/分割・再起動 seed=$seed',
    );
    check(
      split.state.researchPointUnits <=
          split.state.researchPointCapacity * scale,
      'RP上限',
    );
    check(split.state.money <= split.state.moneyCapacity, '資金上限');
    check(!split.state.research.contains('life_support'), '未着手研究を自動解放しない');
    final points = split.state.researchPointUnits,
        simulated = split.state.simulatedMs;
    split.advanceTo(epoch.subtract(const Duration(days: 1)));
    check(
      split.state.researchPointUnits == points &&
          split.state.simulatedMs == simulated,
      '時計後退保持',
    );
  }
}

void verifyMigration() {
  Map<String, dynamic> legacy(String status) => fresh().state.toJson()
    ..['contentVersion'] = 'district-10'
    ..['nextPlanId'] = 2
    ..['plans'] = [
      {
        'id': 'plan-1',
        'taskId': 'life_support',
        'remainingRepeats': 1,
        'completedRuns': 0,
        'status': status,
        'stopReason': '',
        'remainingMs': status == 'running' ? 90000 : 0,
        'iterationDurationMs': status == 'running' ? 120000 : 0,
        'iterationSpecialists': status == 'running' ? 6 : 0,
      },
    ];
  final paid = GameEngine(GameState.fromJson(legacy('running')));
  final balance = paid.state.money;
  paid.advanceBy(const Duration(seconds: 90));
  check(paid.state.research.contains('life_support'), '旧支払済み工期保持');
  check(paid.state.money <= balance, '完了で無償資金なし');
  final receipt = jsonEncode(paid.state.toJson()),
      resumed = GameEngine(copy(paid.state));
  resumed.advanceTo(epoch);
  check(jsonEncode(resumed.state.toJson()) == receipt, '同時刻再起動で二重完了なし');
  final manual = GameEngine(GameState.fromJson(legacy('queued')));
  check(manual.state.plans.single.requiresManualStart, '旧未着手研究は要着手');
  manual.advanceBy(const Duration(hours: 1));
  check(!manual.state.research.contains('life_support'), '旧予約を勝手に解放しない');
  ok(manual.startPlan('plan-1'), '旧研究を明示解放');
  check(manual.state.research.contains('life_support'), '明示操作で即解放');
}
