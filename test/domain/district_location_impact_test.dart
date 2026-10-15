import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';

void main() {
  GameState game() =>
      GameState.initial(DateTime.utc(2026, 10, 16))
        ..research.addAll(['urban_planning', 'automated_fabrication']);

  void place(GameState state, int plot, String id, {int level = 1}) {
    final district = DistrictState(
      cityId: 'earth_delta',
      plotIndex: plot,
      districtId: id,
      level: level,
    );
    state.districts[district.key] = district;
  }

  test(
    'coastal land and both directions of industrial adjacency show real deltas',
    () {
      final state = game();
      final coast = state.districtPreview('earth_delta', 0, 'housing');
      expect(coast.terrainEffects.tax, 4);
      expect(coast.adjacencyEffects.isEmpty, isTrue);
      place(state, 2, 'housing');
      final industry = state.districtPreview('earth_delta', 3, 'industry');
      expect(industry.adjacencyEffects.tax, -3);
      expect(industry.taxDeltaPerMinute, -3);
      expect(industry.factoryBonusDelta, 4);
      final beforeTax = state.taxPerMinute;
      place(state, 3, 'industry');
      expect(state.taxPerMinute - beforeTax, industry.taxDeltaPerMinute);
      final housing = state.districtPreview('earth_delta', 4, 'housing');
      expect(housing.adjacencyEffects.tax, -3);
    },
  );

  test(
    'highland solar attributes ordinary support and extra land effect once',
    () {
      final state = game();
      place(state, 3, 'campus');
      final before = jsonEncode(state.toJson());
      final solar = state.districtPreview('earth_delta', 4, 'solar');
      expect(solar.adjacencyEffects.research, 2);
      expect(solar.terrainEffects.research, 1);
      expect(solar.rawResearchBonusDelta, 3);
      expect(solar.researchBonusDelta, 3);
      expect(jsonEncode(state.toJson()), before);

      place(state, 4, 'solar');
      final upgrade = state.districtPreview(
        'earth_delta',
        4,
        'solar',
        upgrade: true,
      );
      expect(upgrade.adjacencyEffects.research, 2);
      expect(upgrade.terrainEffects.research, 1);
      expect(upgrade.rawResearchBonusDelta, 3);
    },
  );

  test(
    'paused equipment contributes neither land nor neighboring benefits',
    () {
      final state = game();
      place(state, 3, 'campus');
      state.facilities['factory'] = false;
      final solar = state.districtPreview('earth_delta', 4, 'solar');
      expect(solar.terrainEffects.isEmpty, isTrue);
      expect(solar.adjacencyEffects.isEmpty, isTrue);
      expect(solar.rawResearchBonusDelta, 0);
      expect(solar.bonuses.any((bonus) => bonus.startsWith('設備休止中')), isTrue);
    },
  );

  test(
    'explanation preserves raw potential when the research cap blocks the gain',
    () {
      final state = game();
      for (var i = 5; i < GameContent.cities['earth_delta']!.plotCount; i++) {
        place(state, i, 'campus', level: 3);
      }
      place(state, 3, 'campus');
      final solar = state.districtPreview('earth_delta', 4, 'solar');
      expect(solar.researchBonusDelta, 0);
      expect(solar.rawResearchBonusDelta, greaterThan(0));
      expect(
        solar.terrainEffects.research + solar.adjacencyEffects.research,
        solar.rawResearchBonusDelta,
      );
    },
  );

  test('tax floor is respected in the adjacency loss explanation', () {
    final state = game();
    place(state, 12, 'housing');
    final adjacent = GameContent.cities['earth_delta']!.adjacentPlots(12);
    for (final plot in adjacent.take(4)) {
      place(state, plot, 'industry', level: 3);
    }
    final preview = state.districtPreview(
      'earth_delta',
      adjacent.last,
      'industry',
    );
    expect(preview.adjacencyEffects.tax, 0);
    expect(preview.taxDeltaPerMinute, 0);
  });

  test('coastal housing tax clipped by industry remains an adjacency loss', () {
    final state = game();
    place(state, 5, 'housing');
    final adjacent = GameContent.cities['earth_delta']!.adjacentPlots(5);
    place(state, adjacent.first, 'industry', level: 3);
    place(state, adjacent[1], 'industry');
    final preview = state.districtPreview(
      'earth_delta',
      adjacent.last,
      'industry',
    );
    expect(preview.terrainEffects.tax, 0);
    expect(preview.adjacencyEffects.tax, -3);
    expect(preview.taxDeltaPerMinute, -3);
    place(state, adjacent.last, 'industry');
    final upgrade = state.districtPreview(
      'earth_delta',
      adjacent.last,
      'industry',
      upgrade: true,
    );
    expect(upgrade.adjacencyEffects.tax, -1);
    expect(upgrade.terrainEffects.tax, 0);
    expect(upgrade.taxDeltaPerMinute, -1);
  });
}
