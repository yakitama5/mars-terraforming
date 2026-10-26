import 'dart:convert';
import 'dart:io';

import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

/// A public-command route starts with the normal budget and RP. Skipping the
/// story/tutorial changes no money, assets, resources, people or knowledge.
void main() {
  final initial = GameState.initial(DateTime.utc(2026, 10, 21))
    ..openingSeen = true
    ..firstRunTutorial = FirstRunTutorialStep.completed;
  var game = GameEngine(initial);
  void command(String? error) {
    if (error != null) throw StateError(error);
  }

  void until(bool Function() finished) {
    for (var events = 0; !finished(); events++) {
      if (events > 1000) throw StateError('施設の公開操作経路が停止しました');
      final running = game.state.plans.where(
        (plan) =>
            plan.status == 'running' &&
            game.state.facilities[plan.definition.facilityId] == true,
      );
      if (running.isEmpty) {
        throw StateError(
          jsonEncode({
            'money': game.state.money,
            'plans': game.state.plans
                .where((p) => !p.isFinished)
                .map((p) => p.toJson())
                .toList(),
          }),
        );
      }
      final next = running
          .map((plan) => plan.remainingMs)
          .reduce((a, b) => a < b ? a : b);
      game.advanceBy(Duration(milliseconds: next));
    }
  }

  void contract(int count) {
    command(game.enqueue('factory_contract', repeats: count));
    final plan = game.state.plans.last;
    until(() => plan.isFinished);
  }

  String build(String catalog, int plot, int slot) {
    final technologyId = ResearchCatalog.idForCatalog(catalog);
    if (!game.state.research.contains(technologyId)) {
      command(game.unlockResearch(technologyId));
    }
    command(
      game.enqueueMapBuilding(
        technologyId,
        cityId: 'earth_delta',
        plotIndex: plot,
        slotIndex: slot,
      ),
    );
    final instance = game.state
        .cityBuildings('earth_delta')
        .singleWhere((building) => building.technologyId == technologyId);
    until(() => game.state.developments.contains(instance.id));
    command(game.setDevelopmentEnabled(instance.id, true));
    return instance.id;
  }

  void work(String instance, String taskId, {int? targetPlot}) {
    command(
      game.enqueueBuildingWork(instance, taskId, targetPlotIndex: targetPlot),
    );
    final plan = game.state.plans.last;
    until(() => plan.isFinished);
  }

  // A city foundation is now part of research. Build it with the normal
  // starting budget before choosing either specialist facility.
  command(game.enqueueDistrict('earth_delta', 1, 'housing'));
  final housing = game.state.plans.last;
  until(() => housing.isFinished);
  contract(30);
  final greenhouse = build('B01', 12, 0);
  final analysis = build('R01', 12, 1);
  work(greenhouse, 'building_import_water');
  work(greenhouse, 'building_grow_food');
  if (game.state.cityStock('earth_delta', 'food') <= 0 ||
      game.state.cityStock('earth_delta', 'water') != 3) {
    throw StateError('温室の入力消費と食品産出が成立していません');
  }
  work(analysis, 'building_survey', targetPlot: 8);
  if (game.enqueueBuildingWork(
        analysis,
        'building_survey',
        targetPlotIndex: 8,
      ) ==
      null) {
    throw StateError('同一区画の調査報酬を再取得できてしまいます');
  }
  final beforeRestart = game.state.toJson();
  final restored = GameState.fromJson(
    jsonDecode(jsonEncode(beforeRestart)) as Map<String, dynamic>,
  );
  if (jsonEncode(restored.toJson()) != jsonEncode(beforeRestart)) {
    throw StateError('施設・仕事・在庫が保存再読込で変わりました');
  }
  final split = GameEngine(GameState.fromJson(game.state.toJson()));
  final bulk = GameEngine(GameState.fromJson(game.state.toJson()));
  bulk.advanceBy(const Duration(minutes: 12));
  for (final seconds in [31, 89, 7, 113, 101, 179, 200]) {
    split.advanceBy(Duration(seconds: seconds));
  }
  if (jsonEncode(bulk.state.toJson()) != jsonEncode(split.state.toJson())) {
    throw StateError('地図施設の一括・分割進行が一致しません');
  }
  game = GameEngine(restored);
  final originalTime = DateTime.fromMillisecondsSinceEpoch(
    game.state.lastWallClockMs,
    isUtc: true,
  );
  final stockBeforeClock = game.state.cityStock('earth_delta', 'food');
  game.advanceTo(originalTime.subtract(const Duration(hours: 1)));
  if (game.state.cityStock('earth_delta', 'food') != stockBeforeClock) {
    throw StateError('時計後退で食品が変化しました');
  }
  stdout.writeln(
    jsonEncode({
      'route': '初期予算→住宅の都市基盤→受注→研究→同一区画の温室/分析所→食品生産/一度限り調査',
      'elapsedMinutes': game.state.simulatedMs / 60000,
      'money': game.state.money,
      'food': game.state.cityStock('earth_delta', 'food'),
      'researchPoints': game.state.researchPoints,
      'placedBuildings': game.state
          .cityBuildings('earth_delta')
          .where((building) => !building.legacySite)
          .length,
      'saveAndSplit': '一致',
    }),
  );
}
