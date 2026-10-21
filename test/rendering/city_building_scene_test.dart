import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/rendering/city_scene.dart';

List<ScenePlot> _plots(List<SceneBuilding> buildings) => [
  for (var index = 0; index < 25; index++)
    ScenePlot(
      index: index,
      terrain: 'plain',
      terrainName: '平地',
      buildings: index == 12 ? buildings : const [],
    ),
];

Widget _map({
  List<SceneBuilding> buildings = const [],
  List<SceneBuilding> legacy = const [],
  String? selectedId,
  bool placement = false,
  bool wholePlot = false,
  Set<int> slots = const {0, 1},
  ValueChanged<int>? onSlot,
  ValueChanged<String>? onBuilding,
}) => MaterialApp(
  home: Center(
    child: SizedBox(
      width: 600,
      height: 360,
      child: CityScene(
        cityId: 'test_city',
        cityName: '建築試験都市',
        earth: true,
        columns: 5,
        rows: 5,
        plots: _plots(buildings),
        selectedPlot: 12,
        adjacentPlots: const {},
        onPlotSelected: (_) {},
        renderScene: false,
        legacyBuildings: legacy,
        selectedBuildingId: selectedId,
        onBuildingSelected: onBuilding,
        buildingPlacementMode: placement,
        buildingOccupiesWholePlot: wholePlot,
        availableBuildingSlots: slots,
        onBuildingSlotSelected: onSlot,
      ),
    ),
  ),
);

Future<List<int>> _pixels(WidgetTester tester) async {
  final map = find.byType(CityScene);
  final painter = tester
      .widget<CustomPaint>(
        find.descendant(of: map, matching: find.byType(CustomPaint)).first,
      )
      .painter!;
  final size = tester.getSize(map);
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }))!;
}

void main() {
  test('通常2棟の用地座標は異なり、専有施設は区画中央に置く', () {
    final terrain = CityTerrain(
      earth: true,
      columns: 5,
      rows: 5,
      plots: _plots(const []),
    );
    final a = terrain.buildingCenter(12, 0);
    final b = terrain.buildingCenter(12, 1);
    final whole = terrain.buildingCenter(12, 0, occupiesWholePlot: true);
    expect(b.x - a.x, closeTo(.80, 1e-6));
    expect(whole.x, closeTo(terrain.center(12).x, 1e-6));
    expect(a.z, b.z);
    expect(terrain.containsLand(a.x, a.z), isTrue);
    expect(terrain.containsLand(b.x, b.z), isTrue);
  });

  testWidgets('建設候補のAとBを地図上の44px以上の領域で選べる', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(_map(placement: true, onSlot: selected.add));
    await tester.pumpAndSettle();
    for (final slot in [0, 1]) {
      final target = find.byKey(Key('building-slot-test_city-12-$slot'));
      expect(target.hitTestable(), findsOneWidget);
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(target);
    }
    expect(selected, [0, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('専有施設は中央の1用地だけを選ぶ', (tester) async {
    await tester.pumpWidget(
      _map(placement: true, wholePlot: true, slots: const {0}, onSlot: (_) {}),
    );
    await tester.pumpAndSettle();
    final a = find.byKey(const Key('building-slot-test_city-12-0'));
    expect(a.hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('building-slot-test_city-12-1')), findsNothing);
    final mapCenter = tester.getCenter(find.byType(CityScene));
    expect(tester.getCenter(a).dx, closeTo(mapCenter.dx, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('既設2棟を押し分け、同じ系統でも実体IDを返す', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(
      _map(
        buildings: const [
          SceneBuilding(
            id: 'building-7',
            catalogId: 'B01',
            name: '第一温室',
            slotIndex: 0,
            operational: true,
          ),
          SceneBuilding(
            id: 'building-9',
            catalogId: 'B01',
            name: '第二温室',
            slotIndex: 1,
          ),
        ],
        selectedId: 'building-7',
        onBuilding: selected.add,
      ),
    );
    await tester.pumpAndSettle();
    for (final id in ['building-7', 'building-9']) {
      final target = find.byKey(Key('scene-building-$id'));
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target);
    }
    expect(selected, ['building-7', 'building-9']);
    await tester.tap(find.byTooltip('都市全体を表示'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scene-building-building-7')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('完成輪郭、建設、稼働と休止を同じ簡易地図へ反映する', (tester) async {
    Future<List<int>> show({
      String catalog = 'B01',
      bool active = true,
      SceneWorkState work = SceneWorkState.none,
    }) async {
      await tester.pumpWidget(
        _map(
          buildings: [
            SceneBuilding(
              id: 'building-1',
              catalogId: catalog,
              name: '試験施設',
              slotIndex: 0,
              operational: active,
              workState: work,
              workProgress: .6,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return _pixels(tester);
    }

    final greenhouse = await show();
    final battery = await show(catalog: 'E09');
    final sleeping = await show(catalog: 'E09', active: false);
    final construction = await show(
      catalog: 'E09',
      work: SceneWorkState.building,
    );
    expect(greenhouse, isNot(equals(battery)));
    expect(battery, isNot(equals(sleeping)));
    expect(sleeping, isNot(equals(construction)));
    expect(tester.takeException(), isNull);
  });

  for (final catalogId in ['M25', 'M13']) {
    testWidgets('$catalogIdは機体出発でモデルを更新し格納庫を残す', (tester) async {
      SceneBuilding snapshot(bool present) => SceneBuilding(
        id: 'vehicle-site',
        catalogId: catalogId,
        name: '整備棟',
        slotIndex: 0,
        operational: true,
        occupiesWholePlot: true,
        vehiclePresent: present,
      );
      expect(snapshot(true).hasSameModel(snapshot(false)), isFalse);
      Future<List<int>> show(bool present) async {
        await tester.pumpWidget(
          _map(buildings: [snapshot(present)], selectedId: 'vehicle-site'),
        );
        await tester.pumpAndSettle();
        return _pixels(tester);
      }

      final parked = await show(true);
      final inFlight = await show(false);
      expect(parked, isNot(equals(inFlight)));
      await tester.pumpWidget(_map(selectedId: 'vehicle-site'));
      await tester.pumpAndSettle();
      final empty = await _pixels(tester);
      expect(inFlight, isNot(equals(empty)), reason: '出発中も敷地と格納庫は残る');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('移設予約は旧完成模型を残し予約先の実体を一度だけ選べる', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(
      _map(
        buildings: const [
          SceneBuilding(
            id: 'base_lab',
            catalogId: 'base_lab',
            name: '基礎研究所',
            slotIndex: 0,
            workState: SceneWorkState.queued,
          ),
        ],
        legacy: const [
          SceneBuilding(
            id: 'base_lab',
            catalogId: 'base_lab',
            name: '基礎研究所',
            slotIndex: 0,
            operational: true,
          ),
        ],
        selectedId: 'base_lab',
        onBuilding: selected.add,
      ),
    );
    await tester.pumpAndSettle();
    final target = find.byKey(const Key('scene-building-base_lab'));
    expect(target.hitTestable(), findsOneWidget);
    expect(
      tester.getCenter(target).dx,
      closeTo(tester.getCenter(find.byType(CityScene)).dx, 2),
      reason: '旧本部でなく移設先を接写する',
    );
    await tester.tap(target);
    expect(selected, ['base_lab']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本部の旧敷地へ寄り実体IDで選択できる', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(
      _map(
        legacy: const [
          SceneBuilding(
            id: 'base_lab',
            catalogId: 'base_lab',
            name: '基礎研究所',
            slotIndex: 0,
            operational: true,
          ),
        ],
        selectedId: 'base_lab',
        onBuilding: selected.add,
      ),
    );
    await tester.pumpAndSettle();
    final target = find.byKey(const Key('scene-building-base_lab'));
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    expect(selected, ['base_lab']);
    expect(tester.takeException(), isNull);
  });
}
