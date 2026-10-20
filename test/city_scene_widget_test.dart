import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/research_tree.dart';
import 'package:mars_terraforming/rendering/city_scene.dart';

class _MemoryStore implements SaveRepository {
  Map<String, dynamic>? data;
  bool conflict = false;
  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);
  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    if (conflict) throw const SaveConflictException('別のタブで更新されました');
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

  testWidgets(
    'placement is an uncommitted draft across cancel, occupied plots and cities',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(
        _MemoryStore(),
        now: () => DateTime.utc(2026, 10, 14),
      );
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      controller.state.research.addAll([
        'urban_planning',
        'automated_fabrication',
      ]);
      const house = DistrictState(
        cityId: 'earth_delta',
        plotIndex: 0,
        districtId: 'housing',
      );
      controller.state.districts[house.key] = house;
      await controller.command(
        (engine) => engine.enqueueDistrict('earth_delta', 1, 'housing'),
      );
      await tester.pumpWidget(
        MarsApp(
          showIntroduction: false,
          controller: controller,
          renderScene: false,
        ),
      );
      await tester.tap(find.byKey(const Key('navigation-1')));
      await tester.pumpAndSettle();
      CityScene scene() => tester.widget<CityScene>(find.byType(CityScene));
      Future<void> choose(String id) async {
        final button = find.byKey(Key('district-option-$id'));
        await tester.scrollUntilVisible(
          button,
          80,
          scrollable: find.descendant(
            of: find.byKey(const Key('city-facility-palette')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      Future<void> select(int plot) async {
        // These draft cases deliberately compare plots on the outer row.
        await tester.tap(find.byTooltip('都市全体を表示'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('plot-${scene().cityId}-$plot')));
        await tester.pumpAndSettle();
      }

      final before = jsonEncode(controller.state.toJson());
      await choose('solar');
      expect(scene().constructionMode, isTrue);
      expect(scene().buildablePlots, isNot(contains(0)));
      expect(scene().buildablePlots, isNot(contains(1)));
      expect(scene().buildablePlots, hasLength(23));
      await select(2);
      final firstQuote = controller.state.districtPreview(
        'earth_delta',
        2,
        'solar',
      );
      expect(find.text('${firstQuote.cost}ドル'), findsWidgets);
      await select(3);
      expect(scene().selectedPlot, 3);
      expect(jsonEncode(controller.state.toJson()), before);
      expect(scene().plots[2].districtId, isNull);
      await tester.tap(find.byKey(const Key('city-cancel-placement')));
      await tester.pumpAndSettle();
      expect(scene().constructionMode, isFalse);
      expect(scene().selectedPlot, -1);
      expect(scene().buildablePlots, isEmpty);
      await choose('solar');
      await select(0);
      expect(scene().constructionMode, isFalse);
      expect(find.text('住宅地区 Lv.1'), findsOneWidget);
      expect(find.text('地区を強化'), findsOneWidget);
      await select(1);
      expect(find.byKey(const Key('district-work-status')), findsOneWidget);
      expect(find.byKey(const Key('district-open-operations')), findsOneWidget);
      expect(find.byKey(const Key('confirm-district')), findsNothing);
      expect(jsonEncode(controller.state.toJson()), before);
      await tester.tap(find.byKey(const Key('city-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(GameContent.cities['earth_highland']!.name).last,
      );
      await tester.pumpAndSettle();
      expect(scene().cityId, 'earth_highland');
      expect(scene().selectedPlot, -1);
      expect(scene().constructionMode, isTrue);
      expect(find.text(GameContent.districts['solar']!.name), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-district')))
            .onPressed,
        isNull,
      );
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'locked city opens a known research entrance without exposing future names',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(
        _MemoryStore(),
        now: () => DateTime.utc(2026, 10, 14),
      );
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MarsApp(
          showIntroduction: false,
          controller: controller,
          renderScene: false,
        ),
      );
      await tester.tap(find.byKey(const Key('navigation-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('district-option-housing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('city-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(GameContent.cities['earth_highland']!.name).last,
      );
      await tester.pumpAndSettle();
      final before = jsonEncode(controller.state.toJson());
      final scene = tester.widget<CityScene>(find.byType(CityScene));
      expect(scene.buildablePlots, isEmpty);
      final link = find.byKey(const Key('district-required-research'));
      await tester.scrollUntilVisible(
        link,
        80,
        scrollable: find.descendant(
          of: find.byKey(const Key('district-inspector')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-district')))
            .onPressed,
        isNull,
      );
      final unknownId = GameContent.cities['earth_highland']!.requiredResearch!;
      expect(controller.state.isResearchDiscovered(unknownId), isFalse);
      expect(
        find.textContaining(GameContent.tasks[unknownId]!.name),
        findsNothing,
      );
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      expect(link.hitTestable(), findsOneWidget);
      await tester.tap(link);
      await tester.pumpAndSettle();
      final selected = tester
          .widget<ResearchTree>(find.byType(ResearchTree))
          .selectedId;
      expect(controller.state.isResearchDiscovered(selected), isTrue);
      expect(find.byKey(Key('queue-$selected')).hitTestable(), findsOneWidget);
      expect(find.byKey(Key('research-node-$unknownId')), findsNothing);
      expect(
        find.textContaining(GameContent.tasks[unknownId]!.name),
        findsNothing,
      );
      expect(jsonEncode(controller.state.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'undiscovered upgrade keeps its safe reason above the fixed action on small landscape',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameController(
        _MemoryStore(),
        now: () => DateTime.utc(2026, 10, 14),
      );
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      controller.state.research.add('urban_planning');
      const campus = DistrictState(
        cityId: 'earth_delta',
        plotIndex: 7,
        districtId: 'campus',
      );
      controller.state.districts[campus.key] = campus;
      await tester.pumpWidget(
        MarsApp(
          showIntroduction: false,
          controller: controller,
          renderScene: false,
        ),
      );
      await tester.tap(find.byKey(const Key('navigation-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plot-earth_delta-7')));
      await tester.pumpAndSettle();
      final reason = find.byKey(const Key('district-blocked-reason'));
      final action = find.byKey(const Key('confirm-district'));
      expect(reason.hitTestable(), findsOneWidget);
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.widget<Text>(reason).data, '前提研究：研究を進めて手掛かりを探してください');
      expect(
        controller.state.isResearchDiscovered('automated_fabrication'),
        isFalse,
      );
      expect(
        find.textContaining(GameContent.tasks['automated_fabrication']!.name),
        findsNothing,
      );
      expect(
        tester.getBottomLeft(reason).dy,
        lessThan(tester.getTopLeft(action).dy),
      );
      expect(tester.widget<FilledButton>(action).onPressed, isNull);
      expect(controller.state.plans, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final stage in ['construction', 'details', 'comparison']) {
    testWidgets(
      'save conflict safely stops $stage without replacing committed data',
      (tester) async {
        tester.view.physicalSize = const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = _MemoryStore();
        final controller = GameController(
          store,
          now: () => DateTime.utc(2026, 10, 14),
        );
        await controller.initialize(startTimer: false);
        addTearDown(controller.dispose);
        final savedBefore = jsonEncode(store.data);
        await tester.pumpWidget(
          MarsApp(
            showIntroduction: false,
            controller: controller,
            renderScene: false,
          ),
        );
        await tester.tap(find.byKey(const Key('navigation-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('district-option-housing')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('都市全体を表示'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('plot-earth_delta-0')));
        await tester.pumpAndSettle();
        // The detailed information remains accessible without scrolling the
        // narrow inspector, even when its adjacency lines extend below the fold.
        final details = find.byKey(const Key('city-open-details'));
        expect(details.hitTestable(), findsOneWidget);
        if (stage == 'construction') {
          store.conflict = true;
          await tester.tap(find.byKey(const Key('confirm-district')));
          await tester.pumpAndSettle();
        } else {
          await tester.tap(details);
          await tester.pumpAndSettle();
          Future<void> tapDetail(String key) async {
            final target = find.byKey(Key(key));
            await tester.scrollUntilVisible(
              target.hitTestable(),
              80,
              scrollable: find.descendant(
                of: find.byKey(const Key('district-detail')),
                matching: find.byType(Scrollable),
              ),
            );
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            expect(target.hitTestable(), findsOneWidget);
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          if (stage == 'comparison') {
            await tapDetail('save-investment');
            await tester.tap(find.byKey(const Key('plot-earth_delta-1')));
            await tester.pumpAndSettle();
            await tester.tap(details);
            await tester.pumpAndSettle();
            await tapDetail('compare-investments');
          }
          store.conflict = true;
          await controller.save();
          await tester.pumpAndSettle();
          expect(
            find.byKey(
              Key(
                stage == 'details'
                    ? 'district-detail-stopped'
                    : 'investment-comparison-stopped',
              ),
            ),
            findsOneWidget,
          );
          final close = find.byKey(
            Key(
              stage == 'details'
                  ? 'close-district-details'
                  : 'close-investment-comparison',
            ),
          );
          expect(close.hitTestable(), findsOneWidget);
          await tester.tap(close);
          await tester.pumpAndSettle();
        }
        expect(controller.engine, isNull);
        expect(controller.error, contains('保存内容の競合'));
        expect(jsonEncode(store.data), savedBefore);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
        try {
          await controller.initialize(startTimer: false);
          await tester.pumpWidget(
            MarsApp(
              showIntroduction: false,
              controller: controller,
              renderScene: false,
            ),
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
            final screen = CityMapProjection(
              terrain: terrain,
              elevation: CityMapProjection.overviewElevation,
              zoom: CityMapProjection.overviewZoom,
            ).center(index, tester.getSize(map));
            await tester.tapAt(tester.getTopLeft(map) + screen);
            await tester.pumpAndSettle();
            expect(current().selectedPlot, index);
          }

          final before = jsonEncode(controller.state.toJson());
          expect(current().constructionMode, isFalse);
          expect(current().selectedPlot, -1);
          await tester.tap(find.byKey(const Key('district-option-housing')));
          await tester.pumpAndSettle();
          expect(current().constructionMode, isTrue);
          expect(current().buildablePlots, hasLength(25));
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('confirm-district')))
                .onPressed,
            isNull,
          );
          await tester.tap(find.byTooltip('都市全体を表示'));
          await tester.pumpAndSettle();
          await tapGround(4);
          expect(find.text('区画 5  ·  高台'), findsOneWidget);
          await tester.drag(map, const Offset(45, 16));
          await tester.pumpAndSettle();
          expect(current().selectedPlot, 4);
          await tester.tap(find.byTooltip('都市全体を表示'));
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
        } finally {
          controller.dispose();
        }
      },
    );
  }
}
