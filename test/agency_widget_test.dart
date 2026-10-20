import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_content.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/main.dart';
import 'package:mars_terraforming/presentation/strategy_widgets.dart';

class _AgencySave implements SaveRepository {
  Map<String, dynamic>? data;
  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);
  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

Future<void> _tapDetail(WidgetTester tester, String key, String panel) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      140,
      scrollable: find.descendant(
        of: find.byKey(Key(panel)),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('dollar labels group integers and preserve old saved log amounts', () {
    expect(dollars(1234567), '1,234,567ドル');
    expect(signedDollars(-1200), '-1,200ドル');
    expect(legacyCurrencyLabel('外部受注が完了（+24000 Cr）'), '外部受注が完了（+24,000ドル）');
    expect(legacyCurrencyLabel('支払（-1200 Cr）'), '支払（-1,200ドル）');
  });

  for (final size in [const Size(844, 390), const Size(1280, 800)]) {
    testWidgets('staff draft, paid locks and recruitment work at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _AgencySave();
      final controller = GameController(
        store,
        devTools: true,
        now: () => DateTime.utc(2026, 10, 14),
      );
      try {
        await controller.initialize(startTimer: false);
        await tester.pumpWidget(
          MarsApp(
            showIntroduction: false,
            controller: controller,
            sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
          ),
        );
        expect(find.text('900ドル'), findsOneWidget);
        await tester.tap(find.byKey(const Key('navigation-4')));
        await tester.pumpAndSettle();
        final unchanged = jsonEncode(controller.state.toJson());
        await _tapDetail(tester, 'staff-research-more', 'agency-staff');
        expect(controller.state.researchers, 6);
        expect(jsonEncode(controller.state.toJson()), unchanged);
        expect(find.text('研究 7人 / 工業 5人に変更'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const Key('confirm-staff-allocation')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('confirm-staff-allocation')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('confirm-staff-allocation')));
        await tester.pumpAndSettle();
        expect(controller.state.researchers, 7);
        expect(controller.state.industrialWorkers, 5);
        expect(store.data!['researchers'], 7);

        // A research paid before the RP update still holds its people.
        // Preparing that old paid iteration is fixture setup, not a new bill.
        await controller.command((engine) {
          final legacy =
              PlannedTask(
                  id: 'plan-${engine.state.nextPlanId++}',
                  taskId: 'life_support',
                )
                ..status = 'running'
                ..remainingMs = 120000
                ..iterationDurationMs = 120000
                ..iterationSpecialists = engine.state.researchers;
          engine.state.plans.add(legacy);
          engine.enqueue('factory_contract', repeats: null);
          return null;
        });
        await tester.pumpAndSettle();
        // The confirm action may have scrolled the lazily built controls out
        // of the small viewport. Return to the allocation row before reading
        // the paid-work locks on its buttons.
        await tester.scrollUntilVisible(
          find.byKey(const Key('staff-research-less')),
          -140,
          scrollable: find.descendant(
            of: find.byKey(const Key('agency-staff')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('staff-research-less')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('staff-research-more')))
              .onPressed,
          isNull,
        );
        final beforeOperations = jsonEncode(controller.state.toJson());
        await _tapDetail(tester, 'agency-open-operations', 'agency-staff');
        expect(find.byKey(const Key('operations-list-0')), findsOneWidget);
        expect(jsonEncode(controller.state.toJson()), beforeOperations);
        expect(
          controller.state.currentPlanFor('factory')!.remainingRepeats,
          isNull,
        );
        await tester.tap(find.byKey(const Key('navigation-4')));
        await tester.pumpAndSettle();
        final duration = controller.state
            .currentPlanFor('lab')!
            .iterationDurationMs;
        await controller.advanceForDevelopment(
          duration: const Duration(minutes: 10),
        );
        await tester.pumpAndSettle();
        expect(controller.state.research, contains('life_support'));
        expect(duration, greaterThan(0));
        await _tapDetail(tester, 'queue-train_specialists', 'agency-staff');
        expect(
          controller.state.plans.where((p) => p.taskId == 'train_specialists'),
          hasLength(1),
        );
        await controller.advanceForDevelopment();
        await tester.pumpAndSettle();
        expect(
          controller.state.specialistCount,
          GameContent.initialSpecialists + GameContent.specialistTrainingCount,
        );
        expect(controller.state.researchers, 7);
        expect(tester.takeException(), isNull);
      } finally {
        controller.dispose();
      }
    });

    testWidgets(
      'a partnership can be compared and selected only once at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = GameController(
          _AgencySave(),
          now: () => DateTime.utc(2026, 10, 14),
        );
        await controller.initialize(startTimer: false);
        addTearDown(controller.dispose);
        controller.state.research.add('urban_planning');
        const house = DistrictState(
          cityId: 'earth_delta',
          plotIndex: 0,
          districtId: 'housing',
        );
        controller.state.districts[house.key] = house;
        await tester.pumpWidget(
          MarsApp(
            showIntroduction: false,
            controller: controller,
            sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
          ),
        );
        // The guide must land directly on the available support choices.
        await _tapDetail(tester, 'guide-partnership', 'planet-detail');
        expect(find.byKey(const Key('agency-partnerships')), findsOneWidget);
        final funds = controller.state.money;
        final funding = GameContent.partnerships['research_exchange']!.choices
            .firstWhere((c) => c.id == 'funding')
            .funding;
        await _tapDetail(
          tester,
          'partnership-research_exchange-funding',
          'agency-partnerships',
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(controller.state.partnershipChoices, isEmpty);
        expect(controller.state.money, funds);
        await tester.tap(
          find.byKey(const Key('cancel-partnership-research_exchange')),
        );
        await tester.pumpAndSettle();
        expect(controller.state.partnershipChoices, isEmpty);
        await _tapDetail(
          tester,
          'partnership-research_exchange-funding',
          'agency-partnerships',
        );
        await tester.tap(
          find.byKey(
            const Key('confirm-partnership-research_exchange-funding'),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.state.partnershipChoices, {
          'research_exchange': 'funding',
        });
        expect(controller.state.money, funds + funding);
        final button = find.byKey(
          const Key('partnership-research_exchange-funding'),
        );
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(controller.state.money, funds + funding);
        expect(controller.state.partnershipEfficiencyBonus('lab'), 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('guide targets its research and offers a parallel city action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameController(
      _AgencySave(),
      now: () => DateTime.utc(2026, 10, 14),
    );
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    controller.state.researchPointUnits = 0;
    await tester.pumpWidget(
      MarsApp(
        showIntroduction: false,
        controller: controller,
        sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
      ),
    );
    await tester.tap(find.byKey(const Key('navigation-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('research-filter-bio')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('research-node-orbital_gardens')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('next-goal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('queue-life_support')), findsOneWidget);
    await tester.tap(find.byKey(const Key('queue-life_support')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('navigation-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('予約済み · 研究ポイント待ち'), findsOneWidget);
    await controller.command(
      (engine) => engine.setFacilityEnabled('lab', false),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('停止中 · 設備休止中'), findsOneWidget);
    expect(find.textContaining('予約済み · 研究ポイント待ち'), findsNothing);
    final paused = jsonEncode(controller.state.toJson());
    await tester.tap(find.byKey(const Key('next-goal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('operations-list-0')), findsOneWidget);
    expect(jsonEncode(controller.state.toJson()), paused);
    await tester.tap(find.byKey(const Key('navigation-0')));
    await tester.pumpAndSettle();
    final before = jsonEncode(controller.state.toJson());
    await tester.tap(find.byKey(const Key('guide-city')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('district-option-housing')).hitTestable(),
      findsOneWidget,
    );
    expect(jsonEncode(controller.state.toJson()), before);
    expect(tester.takeException(), isNull);
  });
  testWidgets('optional short research guide opens each intended research', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameController(
      _AgencySave(),
      now: () => DateTime.utc(2026, 10, 14),
    );
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    controller.state.research.addAll(['urban_planning', 'life_support']);
    await tester.pumpWidget(
      MarsApp(
        showIntroduction: false,
        controller: controller,
        sceneBuilder: (_, _, _, _) => const SizedBox.expand(),
      ),
    );
    final before = jsonEncode(controller.state.toJson());
    for (final id in [
      'orbital_gardens',
      ResearchCatalog.idForCatalog('M01'),
      ResearchCatalog.idForCatalog('M17'),
    ]) {
      await _tapDetail(tester, 'guide-short-research', 'planet-detail');
      await tester.tap(find.byKey(Key('guide-research-$id')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('queue-$id')), findsOneWidget);
      expect(jsonEncode(controller.state.toJson()), before);
      await tester.tap(find.byKey(const Key('navigation-0')));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
