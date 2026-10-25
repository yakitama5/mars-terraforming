import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/title_scene_data.dart';
import 'package:mars_terraforming/rendering/title_scene_snapshot.dart';

void main() {
  final epoch = DateTime.utc(2026, 10, 25);

  void addBuilding(
    GameState state,
    String id,
    String technology, {
    String city = 'mars_arcadia',
    int plot = 12,
    int slot = 0,
  }) {
    state.developments.add(id);
    state.developmentTechnologyIds[id] = technology;
    state.developmentCityIds[id] = city;
    state.developmentEnabled[id] = true;
    state.developmentResearchers[id] = 0;
    state.buildingLocations[id] = BuildingLocation(
      cityId: city,
      plotIndex: plot,
      slotIndex: slot,
    );
  }

  test('新規世界は無人の赤い火星を保ち、読み取りでセーブを変更しない', () {
    final state = GameState.initial(epoch);
    final before = jsonEncode(state.toJson());
    final snapshot = buildTitleSceneSnapshot(state);
    expect(snapshot.hasSameModel(TitleSceneSnapshot.pristine), isTrue);
    expect(jsonEncode(state.toJson()), before);
  });

  test('地球・月の施設と研究解放だけでは火星を開発済みにしない', () {
    final state = GameState.initial(epoch);
    state.research.addAll(GameContent.researchTechnologies.keys);
    addBuilding(
      state,
      'earth_greenhouse',
      'orbital_gardens',
      city: 'earth_delta',
    );
    addBuilding(
      state,
      'moon_greenhouse',
      'orbital_gardens',
      city: 'moon_south_pole',
    );
    state.cityStocks['earth_delta'] = {'water': 100, 'oxygen': 100};
    final snapshot = buildTitleSceneSnapshot(state);
    expect(snapshot.infrastructureCount, 0);
    expect(snapshot.settlementCount, 0);
    expect(snapshot.greenery, 0);
    expect(snapshot.atmosphere, 0);
    expect(snapshot.cloudCoverage, 0);
  });

  test('完成した火星都市・住民・温室・ガス設備を景観へ反映する', () {
    final state = GameState.initial(epoch)
      ..marsHabitats = 1
      ..marsResidents = 48
      ..habitatChoice = 'dome';
    state.districts['mars_arcadia:12'] = const DistrictState(
      cityId: 'mars_arcadia',
      plotIndex: 12,
      districtId: 'mars_habitat',
      level: 2,
    );
    state.districts['mars_elysium:8'] = const DistrictState(
      cityId: 'mars_elysium',
      plotIndex: 8,
      districtId: 'greenhouse',
    );
    addBuilding(state, 'gas', 'hydrogen_storage', plot: 10);
    addBuilding(
      state,
      'garden',
      'orbital_gardens',
      city: 'mars_elysium',
      plot: 9,
    );
    final before = jsonEncode(state.toJson());
    final snapshot = buildTitleSceneSnapshot(state);
    expect(snapshot.settlementCount, 2);
    expect(snapshot.infrastructureCount, 4, reason: '居住地区の増強を旧居住施設へ二重計上しない');
    expect(snapshot.greenhouseCount, 2);
    expect(snapshot.residentCount, 48);
    expect(snapshot.activity, greaterThan(0));
    expect(snapshot.greenery, greaterThan(0));
    expect(snapshot.atmosphere, greaterThan(0));
    expect(snapshot.cloudCoverage, greaterThan(0));
    expect(jsonEncode(state.toJson()), before);
  });

  test('建設予約と建設中は完成施設の灯りや緑へ加えない', () {
    final state = GameState.initial(epoch);
    state.plans.add(
      PlannedTask(
        id: 'pending-garden',
        taskId: GameContent.developmentTaskId('orbital_gardens'),
        developmentCityId: 'mars_arcadia',
        buildingInstanceId: 'new-garden',
        buildingPlotIndex: 12,
        buildingSlotIndex: 0,
      ),
    );
    for (final status in ['queued', 'running']) {
      state.plans.single.status = status;
      final snapshot = buildTitleSceneSnapshot(state);
      expect(snapshot.infrastructureCount, 0);
      expect(snapshot.settlementCount, 0);
      expect(snapshot.greenery, 0);
      expect(snapshot.activity, 0);
    }
  });

  test('旧形式の居住施設は位置情報なしでも残し、JSON再読み込みで同じ景観にする', () {
    final state = GameState.initial(epoch)
      ..marsHabitats = 2
      ..marsResidents = 24
      ..habitatChoice = 'underground';
    state.achievements.add('first_landing');
    final snapshot = buildTitleSceneSnapshot(state);
    expect(snapshot.infrastructureCount, 2);
    expect(snapshot.settlementCount, 1);
    expect(snapshot.residentCount, 24);
    expect(snapshot.hasExploration, isTrue);
    final restored = GameState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
    );
    expect(snapshot.hasSameModel(buildTitleSceneSnapshot(restored)), isTrue);
  });

  test('休止しても施設は消えず、稼働の賑わいだけが下がる', () {
    final state = GameState.initial(epoch);
    addBuilding(state, 'garden', 'orbital_gardens');
    final active = buildTitleSceneSnapshot(state);
    state.developmentEnabled['garden'] = false;
    final sleeping = buildTitleSceneSnapshot(state);
    expect(sleeping.infrastructureCount, active.infrastructureCount);
    expect(sleeping.greenhouseCount, active.greenhouseCount);
    expect(sleeping.activity, lessThan(active.activity));
    expect(sleeping.hasSameModel(active), isFalse);
  });

  test('大きな旧セーブでも景観チャンネルを有限の範囲へ制限する', () {
    final state = GameState.initial(epoch)
      ..marsHabitats = 1000000
      ..marsResidents = 100000000;
    for (var i = 0; i < 100; i++) {
      addBuilding(state, 'garden-$i', 'orbital_gardens');
      addBuilding(state, 'gas-$i', 'hydrogen_storage');
      addBuilding(state, 'water-$i', 'water_purification');
    }
    final snapshot = buildTitleSceneSnapshot(state);
    for (final value in [
      snapshot.activity,
      snapshot.greenery,
      snapshot.atmosphere,
      snapshot.cloudCoverage,
    ]) {
      expect(value.isFinite, isTrue);
      expect(value, inInclusiveRange(0, 1));
    }
    expect(snapshot.cloudCoverage, lessThan(.2), reason: '装飾的な薄雲を全球大気に見せない');
  });
}
