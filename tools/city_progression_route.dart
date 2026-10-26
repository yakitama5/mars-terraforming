import 'dart:math' as math;

import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_engine.dart';
import 'package:mars_terraforming/domain/game_state.dart';

/// A deterministic player policy. It earns every resource, starts investments
/// only when ready, and never buys knowledge by injecting a completed city.
class CityProgressionRoute {
  CityProgressionRoute(this.game, {this.onEvent});
  final GameEngine game;
  final void Function(String kind, String label)? onEvent;
  final _researchStack = <String>{};
  int _events = 0;

  /// The opening's reading time is outside this domain-only measurement.
  /// Complete the real protected walkthrough, paying for its first house;
  /// only the normal one-time construction help removes that house's timer.
  void introduction() {
    if (game.state.firstRunTutorial == FirstRunTutorialStep.completed) return;
    command(
      game.enqueueDistrict('earth_delta', 0, 'housing'),
      'Place the tutorial house',
    );
    command(game.completeTutorialConstruction(), 'Use Luna construction help');
    onEvent?.call('completion', 'First coastal housing');
    command(
      game.continueFirstRunTutorial(),
      'Acknowledge the first city income',
    );
    command(game.unlockResearch('life_support'), 'Unlock life_support');
    onEvent?.call('completion', 'Life support');
    command(
      game.continueFirstRunTutorial(),
      'Finish the protected walkthrough',
    );
    if (game.state.introductionPausesClock) {
      throw StateError(
        'Normal progression cannot begin while the introduction pauses the clock',
      );
    }
  }

  void command(String? reason, String action) {
    if (reason != null) throw StateError('$action: $reason');
    onEvent?.call('decision', action);
  }

  void earnings() {
    for (final entry in {
      'factory': 'factory_contract',
      'launch': 'launch_contract',
    }.entries) {
      if (game.state.facilities[entry.key] != true) {
        while (game.state.money <
            GameContent.facilities[entry.key]!.upkeepPerMinute) {
          step();
        }
        command(
          game.setFacilityEnabled(entry.key, true),
          'Resume ${entry.key}',
        );
      }
      if (!game.state.plans.any(
        (p) => !p.isFinished && p.taskId == entry.value,
      )) {
        command(
          game.enqueue(entry.value, repeats: null),
          'Earn with ${entry.value}',
        );
      }
    }
  }

  void step([int? limitMs]) {
    if (game.state.introductionPausesClock) {
      throw StateError(
        'The protected introduction must finish before time advances',
      );
    }
    var duration = limitMs ?? const Duration(minutes: 1).inMilliseconds;
    for (final p in game.state.plans.where((p) => p.status == 'running')) {
      if (game.state.facilities[p.definition.facilityId] == true) {
        duration = math.min(duration, p.remainingMs);
      }
    }
    if (duration <= 0 ||
        ++_events > 300000 ||
        game.state.simulatedMs > const Duration(days: 30).inMilliseconds) {
      throw StateError('Public progression exceeded its event/time watchdog');
    }
    game.advanceBy(Duration(milliseconds: duration));
  }

  void waitUntil(bool Function() predicate) {
    while (!predicate()) {
      step();
    }
  }

  void funds(int amount) {
    if (amount > game.state.moneyCapacity && game.state.money < amount) {
      throw StateError('Population capacity cannot hold $amount dollars');
    }
    earnings();
    waitUntil(() => game.state.money >= amount);
  }

  void freeFacility(String facility) {
    if (game.state.facilities[facility] != true) {
      funds(GameContent.facilities[facility]!.upkeepPerMinute);
      command(game.setFacilityEnabled(facility, true), 'Resume $facility');
    }
    for (final p
        in game.state.plans
            .where(
              (p) =>
                  !p.isFinished &&
                  p.definition.facilityId == facility &&
                  p.remainingRepeats == null,
            )
            .toList()) {
      command(game.cancelQueued(p.id), 'Finish current ${p.taskId}');
    }
    waitUntil(() => game.state.currentPlanFor(facility) == null);
  }

  PlannedTask run(
    String facility,
    int cost,
    String? Function() action,
    String label,
  ) {
    funds(cost);
    freeFacility(facility);
    if (game.state.money < cost) {
      funds(cost);
      freeFacility(facility);
    }
    command(action(), label);
    final plan = game.state.plans.last;
    waitUntil(() => plan.isFinished);
    if (plan.status != 'completed') throw StateError('$label did not complete');
    onEvent?.call('completion', label);
    earnings();
    return plan;
  }

  void job(String id, {String? label}) {
    final task = GameContent.tasks[id]!;
    run(
      task.facilityId,
      game.state.taskCost(task),
      () => game.enqueue(id),
      label ?? id,
    );
  }

  void research(String id) {
    if (game.state.research.contains(id)) return;
    if (!_researchStack.add(id)) {
      throw StateError(
        'Research/facility cycle: ${_researchStack.join(' -> ')} -> $id',
      );
    }
    final technology = GameContent.technology(id);
    for (final parent in technology.prerequisiteIds) {
      research(parent);
    }
    if (technology.alternativePrerequisiteIds.isNotEmpty &&
        !technology.alternativePrerequisiteIds.any(
          game.state.research.contains,
        )) {
      research(technology.alternativePrerequisiteIds.first);
    }
    if (!game.state.isResearchDiscovered(id)) {
      final parents = GameContent.researchDiscoveryParentIds(id);
      if (parents.isEmpty) {
        throw StateError('No discovered route to ${technology.catalogId}');
      }
      research(parents.first);
    }
    population(GameContent.researchPopulationRequirement(id));
    final conditions = GameContent.cityResearchRequirements(id);
    for (final entry in conditions.developmentCatalogCounts.entries) {
      while (game.state.developments
              .where(
                (owned) =>
                    game.state.developmentTechnologyId(owned) ==
                    ResearchCatalog.idForCatalog(entry.key),
              )
              .length <
          entry.value) {
        development(ResearchCatalog.idForCatalog(entry.key));
      }
    }
    for (final entry in conditions.districtCounts.entries) {
      while (game.state.districtCount(entry.key) < entry.value) {
        district(entry.key);
      }
    }
    for (final achievement in conditions.achievements) {
      if (game.state.achievements.contains(achievement)) continue;
      if (achievement == 'first_launch') {
        earnings();
        waitUntil(() => game.state.achievements.contains(achievement));
      } else if (achievement == 'first_landing') {
        accessMars();
        marsKit();
      } else {
        throw StateError('Unsupported route achievement $achievement');
      }
    }
    surveys(conditions.minimumSurveyedSites);
    power(conditions.minimumPower);
    researchRate(conditions.minimumResearchPointsPerHour);
    habitats(conditions.minimumMarsHabitats);
    final reasons = game.researchRequirementReasons(id);
    if (reasons.isNotEmpty) {
      throw StateError('${technology.catalogId}: ${reasons.join(' / ')}');
    }
    earnings();
    waitUntil(
      () => game.state.researchPoints >= GameContent.researchPointCost(id),
    );
    command(game.unlockResearch(id), id);
    onEvent?.call('completion', id);
    _researchStack.remove(id);
  }

  void population(int minimum) {
    while (game.state.totalPopulation < minimum) {
      district('housing');
    }
  }

  void district(String type, {String? cityId, String? label}) {
    final definition = GameContent.districts[type]!;
    for (final id in [
      ?definition.requiredResearch,
      ...definition.prerequisites,
    ]) {
      research(id);
    }
    if (definition.planet == 'moon') {
      accessMoon();
      if (type != 'moon_outpost' &&
          game.state.districtCount('moon_outpost') == 0) {
        district('moon_outpost');
      }
      moonKit();
    } else if (definition.planet == 'mars') {
      accessMars();
      marsKit();
      if (type == 'mars_habitat' && game.state.habitatChoice == null) {
        command(game.chooseHabitat('dome'), 'Choose dome habitation');
      }
    }
    final city = cityId == null
        ? GameContent.cities.values.firstWhere(
            (city) =>
                city.planet == definition.planet &&
                game.state.cityUnlocked(city.id),
          )
        : GameContent.cities[cityId]!;
    for (var plot = 0; plot < city.plotCount; plot++) {
      final quote = game.state.districtPreview(city.id, plot, type);
      if (!quote.isValid && !(quote.blockedReason?.contains('資金') ?? false)) {
        continue;
      }
      run(
        definition.planet == 'earth' ? 'factory' : definition.planet,
        quote.cost,
        () => game.enqueueDistrict(city.id, plot, type),
        label ?? '$type:${city.id}:$plot',
      );
      return;
    }
    throw StateError('No legal plot for $type in ${city.id}');
  }

  void development(String id) {
    final owned = game.state.developments
        .where((owned) => game.state.developmentTechnologyId(owned) == id)
        .firstOrNull;
    if (owned != null) return;
    research(id);
    final mapped = GameContent.mapBuildingDefinitions[id];
    final planet = mapped?.allowedPlanets.contains('earth') == true
        ? 'earth'
        : mapped?.allowedPlanets.first ?? GameContent.developmentPlanet(id);
    if (planet == 'moon') accessMoon();
    if (planet == 'mars') accessMars();
    if (planet == 'moon') moonKit();
    if (planet == 'mars') marsKit();
    final city = GameContent.cities.values.firstWhere(
      (city) => city.planet == planet && game.state.cityUnlocked(city.id),
    );
    var instance = id;
    if (mapped != null) {
      var started = false;
      for (var plot = 0; plot < city.plotCount && !started; plot++) {
        for (
          var slot = 0;
          slot < GameContent.buildingSlotCount && !started;
          slot++
        ) {
          final quote = game.state.buildingPreview(
            id,
            cityId: city.id,
            plotIndex: plot,
            slotIndex: slot,
          );
          if (!quote.isValid &&
              !(quote.blockedReason?.contains('資金') ?? false)) {
            continue;
          }
          final plan = run(
            GameContent.developmentFacilityId(id),
            quote.cost,
            () => game.enqueueMapBuilding(
              id,
              cityId: city.id,
              plotIndex: plot,
              slotIndex: slot,
            ),
            'Build $id',
          );
          instance = plan.buildingInstanceId!;
          started = true;
        }
      }
      if (!started) throw StateError('No legal map site for $id');
    } else {
      run(
        GameContent.developmentFacilityId(id),
        GameContent.developmentCost(id),
        () => game.enqueueDevelopment(id, cityId: city.id),
        'Build $id',
      );
    }
    if (GameContent.developmentEffect(id) == ResearchUnlockEffect.research ||
        id == 'urban_planning') {
      enable(instance);
    }
  }

  void enable(String id) {
    if (game.state.isDevelopmentOperational(id)) return;
    final technology = game.state.developmentTechnologyId(id);
    funds(GameContent.developmentUpkeepPerMinute(technology));
    final facility = game.state.developmentFacilityFor(id);
    if (game.state.facilities[facility] != true) {
      command(game.setFacilityEnabled(facility, true), 'Resume $facility');
    }
    command(game.setDevelopmentEnabled(id, true), 'Operate $technology');
  }

  String owned(String technology) => game.state.developments.firstWhere(
    (id) => game.state.developmentTechnologyId(id) == technology,
  );

  void work(String instance, String taskId, {int? plot}) {
    enable(instance);
    final task = GameContent.tasks[taskId]!;
    run(
      task.facilityId,
      game.state.taskCost(task),
      () => game.enqueueBuildingWork(instance, taskId, targetPlotIndex: plot),
      taskId,
    );
  }

  void surveys(int minimum) {
    if (game.state.surveyedSites.length >= minimum) return;
    development('local_resources');
    final lab = owned('local_resources');
    var plot = 0;
    while (game.state.surveyedSites.length < minimum) {
      if (!game.state.isSiteSurveyed(
        game.state.developmentCityIds[lab]!,
        plot,
      )) {
        work(lab, 'building_survey', plot: plot);
      }
      plot++;
    }
  }

  int get powerSupply => GameContent.cities.values
      .where((city) => game.state.cityUnlocked(city.id))
      .fold(0, (sum, city) => sum + game.state.cityPowerSupply(city.id));

  void power(int minimum) {
    if (powerSupply >= minimum) return;
    development('urban_planning');
    final grid = owned('urban_planning');
    final city = game.state.developmentCityIds[grid]!;
    if (!game.state.connectedGridCities.contains(city)) {
      if (game.state.cityStock(city, 'parts') == 0) {
        work(grid, 'building_import_parts');
      }
      work(grid, 'building_connect_grid');
    }
    while (powerSupply < minimum) {
      district('solar', cityId: city);
    }
  }

  void researchRate(int minimum) {
    if (game.state.researchPointsPerHour >= minimum) return;
    for (final catalog in ['R01', 'R02', 'R03', 'R04']) {
      development(ResearchCatalog.idForCatalog(catalog));
      if (game.state.researchPointsPerHour >= minimum) return;
    }
    throw StateError('Research capacity cannot reach $minimum RP/hour');
  }

  void accessMoon() {
    if (game.state.planetUnlocked('moon')) return;
    earnings();
    waitUntil(() => game.state.planetUnlocked('moon'));
  }

  void moonKit() {
    if (game.state.moonKits > 0) return;
    research('life_support');
    if (game.state.earthKits == 0) job('habitat_kit');
    job('moon_delivery');
  }

  void accessMars() {
    if (game.state.planetUnlocked('mars')) return;
    accessMoon();
    if (game.state.districtCount('moon_outpost') == 0) district('moon_outpost');
    if (game.state.districtCount('moon_spaceport') == 0) {
      district('moon_spaceport');
    }
    job('mars_probe');
  }

  void marsKit() {
    if (game.state.marsKits > 0) return;
    accessMars();
    research('life_support');
    if (game.state.earthKits == 0) job('habitat_kit');
    job('mars_delivery');
  }

  void habitats(int minimum) {
    if (game.state.marsHabitats >= minimum) return;
    accessMars();
    marsKit();
    while (game.state.marsHabitats < minimum) {
      final cities = GameContent.cities.values.where(
        (city) => city.planet == 'mars' && game.state.cityUnlocked(city.id),
      );
      final city = cities.firstWhere(
        (city) => !game.state.districts.values.any(
          (d) => d.cityId == city.id && d.districtId == 'mars_habitat',
        ),
        orElse: () => cities.first,
      );
      district('mars_habitat', cityId: city.id);
    }
  }
}
