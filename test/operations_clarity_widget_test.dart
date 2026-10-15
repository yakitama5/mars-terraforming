import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/plan_forecast_dialog.dart';

class _MemorySave implements SaveRepository {
  int writes = 0;
  @override
  Future<SaveLoadResult> load() async =>
      const SaveLoadResult(data: null, recovered: false, generation: 0);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async => writes++;
}

void main() {
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('forecast prioritizes progress and blockers at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _MemorySave();
      final controller = GameController(
        repository,
        now: () => DateTime.utc(2026, 10, 15),
      );
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await controller.command((engine) {
        engine.state.money = 5000;
        engine.enqueue('life_support');
        engine.enqueue('factory_contract', repeats: 3);
        return engine.enqueue('mars_delivery');
      });
      final before = jsonEncode(controller.state.toJson());
      final writes = repository.writes;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PlanForecastDialog(controller: controller),
                ),
                child: const Text('見通しを開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('見通しを開く'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('forecast-money')), findsOneWidget);
      expect(find.byKey(const Key('forecast-research')), findsOneWidget);
      expect(
        find.byKey(const Key('forecast-attention-launch')),
        findsOneWidget,
      );
      expect(find.text('地球人口'), findsNothing);
      expect(find.byKey(const Key('forecast-facility-lab')), findsNothing);
      final completion = find.byKey(const Key('forecast-completion-summary'));
      final details = find.byKey(const Key('forecast-resource-details'));
      expect(
        tester.getTopLeft(completion).dy,
        lessThan(tester.getTopLeft(details).dy),
      );
      final scrollable = find.descendant(
        of: find.byKey(const Key('plan-forecast-scroll')),
        matching: find.byType(Scrollable),
      );
      Future<void> expand(String key) async {
        final target = find.byKey(Key(key));
        await tester.scrollUntilVisible(target, 100, scrollable: scrollable);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await expand('forecast-resource-details');
      expect(find.text('地球人口'), findsOneWidget);
      await expand('forecast-equipment-details');
      expect(find.byKey(const Key('forecast-facility-lab')), findsOneWidget);
      expect(
        find.byKey(const Key('close-plan-forecast')).hitTestable(),
        findsOneWidget,
      );
      expect(jsonEncode(controller.state.toJson()), before);
      expect(repository.writes, writes);
      expect(tester.takeException(), isNull);
    });
  }
}
