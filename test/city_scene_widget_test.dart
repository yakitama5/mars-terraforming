import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/rendering/city_scene.dart';

class _MemoryStore implements SaveRepository {
  Map<String, dynamic>? data;
  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);
  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void main() {
  testWidgets(
    'fallback ground paints completed and upgraded buildings without a terrain reset',
    (tester) async {
      Future<void> showLevel(int level) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: CityScene(
                  cityId: 'test_city',
                  cityName: '描画試験都市',
                  earth: true,
                  columns: 1,
                  rows: 1,
                  plots: [
                    ScenePlot(
                      index: 0,
                      terrain: 'plain',
                      terrainName: '平地',
                      districtId: level > 0 ? 'housing' : null,
                      districtName: level > 0 ? '住宅地区' : null,
                      level: level,
                    ),
                  ],
                  selectedPlot: 0,
                  adjacentPlots: const {},
                  onPlotSelected: (_) {},
                  renderScene: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<List<int>> groundPixels() async {
        final map = find.byType(CityScene);
        // Paint only the bottom (ground/building) layer: changed text or selection
        // labels must not conceal a stale fallback building snapshot.
        final ground = tester
            .widget<CustomPaint>(
              find
                  .descendant(of: map, matching: find.byType(CustomPaint))
                  .first,
            )
            .painter!;
        final size = tester.getSize(map);
        return (await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          ground.paint(Canvas(recorder), size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            size.width.toInt(),
            size.height.toInt(),
          );
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return bytes!.buffer.asUint8List().toList();
          } finally {
            image.dispose();
            picture.dispose();
          }
        }))!;
      }

      int changedPixels(List<int> before, List<int> after) {
        var count = 0;
        for (var i = 0; i < before.length; i += 4) {
          if (before[i] != after[i] ||
              before[i + 1] != after[i + 1] ||
              before[i + 2] != after[i + 2] ||
              before[i + 3] != after[i + 3]) {
            count++;
          }
        }
        return count;
      }

      await showLevel(0);
      final empty = await groundPixels();
      await showLevel(1);
      final completed = await groundPixels();
      expect(
        changedPixels(empty, completed),
        inInclusiveRange(50, 200),
        reason: 'Completing a district must paint a building on the existing ground.',
      );
      await showLevel(2);
      final upgraded = await groundPixels();
      expect(
        changedPixels(completed, upgraded),
        inInclusiveRange(25, 150),
        reason:
            'Increasing the level must enlarge that same fallback building.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(844, 390), const Size(1280, 800)]) {
    testWidgets(
      'terrain selection, pan, expanded map and paid construction at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = GameController(
          _MemoryStore(),
          devTools: true,
          now: () => DateTime.utc(2026, 10, 14),
        );
        await controller.initialize(startTimer: false);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MarsApp(controller: controller, renderScene: false),
        );
        await tester.tap(find.byKey(const Key('navigation-1')));
        await tester.pumpAndSettle();
        final map = find.byType(CityScene);
        CityScene current() => tester.widget<CityScene>(map);
        Future<void> tapGround(int index) async {
          final scene = current();
          final terrain = CityTerrain(
            earth: scene.earth,
            columns: scene.columns,
            rows: scene.rows,
            plots: scene.plots,
          );
          final screen = CityMapProjection(terrain: terrain)
              .center(index, tester.getSize(map));
          await tester.tapAt(tester.getTopLeft(map) + screen);
          await tester.pumpAndSettle();
          expect(current().selectedPlot, index);
        }

        final before = jsonEncode(controller.state.toJson());
        await tapGround(4);
        expect(find.text('区画 5  ·  高台'), findsOneWidget);
        await tester.drag(map, const Offset(45, 16));
        await tester.pumpAndSettle();
        expect(current().selectedPlot, 4);
        await tester.tap(find.byTooltip('都市地図の視点を戻す'));
        await tester.pumpAndSettle();
        final narrow = tester.getSize(map).width;
        await tester.tap(find.byKey(const Key('city-inspector-toggle')));
        await tester.pumpAndSettle();
        expect(tester.getSize(map).width, greaterThan(narrow));
        expect(find.byKey(const Key('confirm-district')), findsNothing);
        await tapGround(0);
        expect(
          find.byKey(const Key('confirm-district')).hitTestable(),
          findsOneWidget,
        );
        expect(jsonEncode(controller.state.toJson()), before);
        await tester.tap(find.byKey(const Key('confirm-district')));
        await tester.pumpAndSettle();
        final plan = controller.state.districtPlanAt('earth_delta', 0)!;
        expect(plan.plotIndex, 0);
        expect(current().plots[0].workState, SceneWorkState.building);
        expect(current().plots[0].level, 0);
        expect(find.byKey(const Key('district-work-status')), findsOneWidget);
        expect(find.text('建設前の見積もり'), findsNothing);
        final remaining = plan.remainingMs;
        await controller.advanceForDevelopment(
          duration: Duration(milliseconds: remaining),
        );
        await tester.pumpAndSettle();
        expect(current().plots[0].workState, SceneWorkState.none);
        expect(current().plots[0].level, 1);
        expect(current().plots[1].level, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
