import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

/// Reproducible balance check using public player commands and event time only.
/// Run with `dart tools/verify_progression.dart`; failure returns nonzero even
/// when Dart assertions are disabled. This is one route, not an optimum.
void main() {
  try {
    stdout.writeln(jsonEncode(runProgressionVerification().toJson()));
  } catch (error) {
    stderr.writeln(jsonEncode({'status': 'failed', 'error': '$error'}));
    exitCode = 1;
  }
}

class ProgressionVerification {
  const ProgressionVerification(this.state, this.milestones);
  final GameState state;
  final List<Map<String, Object>> milestones;

  Map<String, Object> toJson() => {
    'status': 'passed',
    'contentVersion': GameContent.version,
    'startingMoney': GameContent.initialMoney,
    'elapsedHours': state.simulatedMs / Duration.millisecondsPerHour,
    'elapsedDays': state.simulatedMs / Duration.millisecondsPerDay,
    'finalMoney': state.money,
    'researchCount': state.research.length,
    'developedMarsCities': state.developedMarsCityIds.toList(),
    'marsHabitats': state.marsHabitats,
    'marsResidents': state.marsResidents,
    'marsKits': state.marsKits,
    'milestones': milestones,
  };
}

ProgressionVerification runProgressionVerification() {
  final game = GameEngine(GameState.initial(DateTime.utc(2026, 10, 13)));
  final milestones = <Map<String, Object>>[];
  void require(bool condition, String reason) {
    if (!condition) throw StateError(reason);
  }

  void command(String? reason) {
    if (reason != null) throw StateError(reason);
  }

  void advanceUntil(bool Function() condition) {
    var events = 0;
    while (!condition()) {
      final running = game.state.plans.where(
        (plan) =>
            plan.status == 'running' &&
            game.state.facilities[plan.definition.facilityId] == true,
      );
      require(
        running.isNotEmpty,
        'Route is blocked: ${game.state.plans.where((p) => !p.isFinished).map((p) => '${p.taskId}: ${p.stopReason}').join(' / ')}',
      );
      game.advanceBy(
        Duration(milliseconds: running.map((p) => p.remainingMs).reduce(min)),
      );
      require(++events < 200000, 'Too many completion events');
      require(
        game.state.simulatedMs < const Duration(days: 30).inMilliseconds,
        'This prototype route exceeded 30 days',
      );
    }
  }

  void record(String step) {
    milestones.add({
      'step': step,
      'elapsedHours': game.state.simulatedMs / Duration.millisecondsPerHour,
      'money': game.state.money,
      'researchEfficiency': game.state.researchBonusPercent,
      'factoryEfficiency': game.state.factoryBonusPercent,
      'launchEfficiency': game.state.launchBonusPercent,
      'marsEfficiency': game.state.marsBonusPercent,
    });
  }

  void research(String id) {
    command(game.enqueue(id));
    advanceUntil(() => game.state.research.contains(id));
    record(id);
  }

  void prioritize(PlannedTask plan) {
    final candidates = game.state
        .upcomingPlansFor(plan.definition.facilityId)
        .where((p) => p.id != plan.id)
        .toList();
    if (candidates.isNotEmpty) {
      command(
        game.reorderPlan(
          plan.id,
          relativeToPlanId: candidates.first.id,
          before: true,
        ),
      );
    }
  }

  void job(String id) {
    command(game.enqueue(id));
    final plan = game.state.plans.last;
    prioritize(plan);
    advanceUntil(() => plan.isFinished);
    record(id);
  }

  void district(String cityId, int plotIndex, String districtId) {
    command(game.enqueueDistrict(cityId, plotIndex, districtId));
    final plan = game.state.plans.last;
    prioritize(plan);
    advanceUntil(() => plan.isFinished);
    record('$cityId:$plotIndex:$districtId');
  }

  void replaceContract(String oldId, String nextId) {
    final old = game.state.plans.firstWhere(
      (plan) => plan.taskId == oldId && !plan.isFinished,
    );
    command(game.cancelQueued(old.id));
    command(game.enqueue(nextId, repeats: null));
  }

  command(game.enqueue('factory_contract', repeats: null));
  command(game.enqueue('launch_contract', repeats: null));
  research('life_support');
  research('urban_planning');
  district('earth_highland', 0, 'campus');
  district('earth_highland', 1, 'solar');
  district('earth_highland', 3, 'industry');
  job('habitat_kit');
  job('mars_delivery');
  command(game.chooseHabitat('dome'));
  district('mars_arcadia', 2, 'mars_habitat');
  research('automated_fabrication');
  replaceContract('factory_contract', 'precision_contract');
  research('reusable_launch');
  district('earth_delta', 0, 'spaceport');
  research('orbital_logistics');
  replaceContract('launch_contract', 'orbital_contract');
  job('batch_habitat_kit');
  job('cargo_delivery');
  district('mars_elysium', 3, 'mars_habitat');
  research('closed_ecology');
  district('mars_arcadia', 0, 'greenhouse');
  research('local_resources');
  district('mars_arcadia', 1, 'extractor');
  research('intercity_logistics');
  research('industrial_network');
  research('regional_habitats');

  require(
    GameContent.tasks.values
        .where((task) => task.unique)
        .every((task) => game.state.research.contains(task.id)),
    'Not all available research was reachable',
  );
  require(
    game.state.developedMarsCityIds.length == 2,
    'Expected two Mars cities',
  );
  require(game.state.marsHabitats == 2, 'Expected two completed habitats');
  require(game.state.marsKits == 3, 'Cargo was duplicated or lost');
  require(
    game.state.simulatedMs > const Duration(days: 7).inMilliseconds,
    'This route no longer sustains a week of prototype progression',
  );
  final snapshot = jsonEncode(game.state.toJson());
  final restored = GameEngine(
    GameState.fromJson(jsonDecode(snapshot) as Map<String, dynamic>),
  );
  require(
    jsonEncode(restored.state.toJson()) == snapshot,
    'Reload changed state',
  );
  return ProgressionVerification(game.state, milestones);
}
