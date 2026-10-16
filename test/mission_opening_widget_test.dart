import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/application/game_controller.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/domain/save_repository.dart';
import 'package:mars_terraforming/presentation/game_screen.dart';
import 'package:mars_terraforming/presentation/mission_opening.dart';

class _OpeningSave implements SaveRepository {
  Map<String, dynamic>? data;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<SaveLoadResult> load() async =>
      SaveLoadResult(data: data, recovered: false, generation: 1);

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    if (gate case final waiting?) await waiting.future;
    if (fail) throw StateError('disk full');
    data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
  }
}

void main() {
  final epoch = DateTime.utc(2026, 10, 16);

  Future<void> mount(
    WidgetTester tester,
    GameController controller, {
    Size size = const Size(844, 390),
    double textScale = 1,
    Widget? home,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: home ?? GameScreen(controller: controller, renderScene: false),
      ),
    );
    await tester.pumpAndSettle();
    final cinematicSkip = find.byKey(const Key('opening-cinematic-skip'));
    if (cinematicSkip.evaluate().isNotEmpty) {
      await tester.tap(cinematicSkip);
      await tester.pumpAndSettle();
    }
  }

  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('new opening and optional naming remain usable at $size', (
      tester,
    ) async {
      final store = _OpeningSave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await mount(tester, controller, size: size, textScale: 1.3);
      expect(find.text('青い星から、次の故郷へ'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('opening-next')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(
        find.byKey(const Key('mission-city-earth_delta')),
        '青空市',
      );
      await tester.ensureVisible(find.byKey(const Key('mission-rocket')));
      await tester.enterText(find.byKey(const Key('mission-rocket')), 'はるか');
      await tester.tap(find.byKey(const Key('mission-names-save')));
      await tester.pumpAndSettle();
      expect(controller.state.openingSeen, isTrue);
      expect(controller.state.cityName('earth_delta'), '青空市');
      expect(controller.state.rocketName, 'はるか');
      expect(find.byKey(const Key('mission-opening')), findsNothing);
      expect(find.byKey(const Key('first-run-city')), findsOneWidget);
      expect(find.byKey(const Key('navigation-1')), findsNothing);
      expect(
        controller.state.firstRunTutorial,
        FirstRunTutorialStep.placeHousing,
      );
      expect(GameState.fromJson(store.data!).cityName('earth_delta'), '青空市');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'story skip still offers naming and the second skip starts with defaults',
    (tester) async {
      final controller = GameController(_OpeningSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await mount(tester, controller);
      await tester.tap(find.byKey(const Key('opening-skip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mission-city-earth_delta')), findsOneWidget);
      await tester.tap(find.byKey(const Key('mission-names-cancel')));
      await tester.pumpAndSettle();
      expect(controller.state.openingSeen, isTrue);
      expect(controller.state.rocketName, 'あかつき');
      expect(controller.state.plans, isEmpty);
      expect(find.byKey(const Key('first-run-city')), findsOneWidget);
      expect(find.byKey(const Key('navigation-1')), findsNothing);
    },
  );

  testWidgets(
    'replaying story closes without changing names, progress or awards',
    (tester) async {
      final controller = GameController(_OpeningSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await controller.updateMissionIdentity(
        cities: {'earth_delta': '青空市'},
        rocket: 'はるか',
        finishOpening: true,
      );
      final before = jsonEncode(controller.state.toJson());
      var closed = 0;
      await mount(
        tester,
        controller,
        home: MissionOpening(
          controller: controller,
          replay: true,
          renderScene: false,
          onClose: () => closed++,
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('opening-next')));
        await tester.pumpAndSettle();
      }
      expect(closed, 1);
      expect(jsonEncode(controller.state.toJson()), before);
      expect(find.byKey(const Key('mission-names-save')), findsNothing);
    },
  );

  testWidgets(
    'an existing save without opening metadata is never interrupted',
    (tester) async {
      final store = _OpeningSave()
        ..data = (GameState.initial(epoch).toJson()
          ..remove('openingSeen')
          ..remove('missionIdentity')
          ..remove('firstRunTutorial')
          ..remove('firstRunTutorialPlanId'));
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await mount(tester, controller);
      expect(find.byKey(const Key('mission-opening')), findsNothing);
      expect(find.byKey(const Key('first-run-city')), findsNothing);
      expect(find.byKey(const Key('navigation-1')), findsOneWidget);
      expect(controller.state.firstRunTutorial, FirstRunTutorialStep.completed);
    },
  );

  testWidgets('failed setup save keeps editable names and a retry action', (
    tester,
  ) async {
    final store = _OpeningSave();
    final controller = GameController(store, now: () => epoch);
    await controller.initialize(startTimer: false);
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await tester.tap(find.byKey(const Key('opening-skip')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('mission-city-earth_delta')),
      '青空市',
    );
    store.fail = true;
    await tester.tap(find.byKey(const Key('mission-names-save')));
    await tester.pumpAndSettle();
    expect(controller.state.openingSeen, isFalse);
    expect(find.byKey(const Key('first-run-city')), findsNothing);
    expect(find.text('保存できませんでした。名前を残したまま再試行できます。'), findsOneWidget);
    expect(
      find.byKey(const Key('mission-names-save')).hitTestable(),
      findsOneWidget,
    );
    store.fail = false;
    await tester.tap(find.byKey(const Key('mission-names-save')));
    await tester.pumpAndSettle();
    expect(controller.state.openingSeen, isTrue);
    expect(controller.state.cityName('earth_delta'), '青空市');
    expect(find.byKey(const Key('first-run-city')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a second save tap cannot close naming while the first save is pending',
    (tester) async {
      final store = _OpeningSave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      var closed = 0;
      await mount(
        tester,
        controller,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 680,
              child: MissionNameForm(
                controller: controller,
                onDone: () => closed++,
                onCancel: () => closed++,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('mission-city-earth_delta')),
        '青空市',
      );
      store.gate = Completer<void>();
      store.fail = true;
      final save = find.byKey(const Key('mission-names-save'));
      await tester.tap(save);
      // Even before the disabled state rebuilds, the handler's local guard blocks another tap.
      await tester.tap(save);
      await tester.pump();
      expect(closed, 0);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('mission-names-cancel')))
            .onPressed,
        isNull,
      );
      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(closed, 0);
      expect(find.text('保存できませんでした。名前を残したまま再試行できます。'), findsOneWidget);
      store.gate = null;
      store.fail = false;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(controller.state.cityName('earth_delta'), '青空市');
      await tester.pump(const Duration(seconds: 8));
    },
  );
  testWidgets(
    'opening remains visible until its completion snapshot is durable',
    (tester) async {
      final store = _OpeningSave();
      final controller = GameController(store, now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await mount(tester, controller);
      await tester.tap(find.byKey(const Key('opening-skip')));
      await tester.pumpAndSettle();
      store.gate = Completer<void>();
      await tester.tap(find.byKey(const Key('mission-names-save')));
      controller.notifyListeners(); // A competing save or status update can redraw the shell.
      await tester.pump();
      expect(controller.finishingOpening, isTrue);
      expect(find.byKey(const Key('mission-names-save')), findsOneWidget);
      expect(find.byKey(const Key('first-run-city')), findsNothing);
      expect(find.byKey(const Key('navigation-1')), findsNothing);
      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(controller.finishingOpening, isFalse);
      expect(find.byKey(const Key('first-run-city')), findsOneWidget);
      expect(find.byKey(const Key('navigation-1')), findsNothing);
      expect(
        GameState.fromJson(store.data!).firstRunTutorial,
        FirstRunTutorialStep.placeHousing,
      );
    },
  );
  testWidgets(
    'each story chapter starts at its heading after small-screen scrolling',
    (tester) async {
      final controller = GameController(_OpeningSave(), now: () => epoch);
      await controller.initialize(startTimer: false);
      addTearDown(controller.dispose);
      await mount(
        tester,
        controller,
        size: const Size(568, 320),
        textScale: 1.5,
      );
      final scroll = find.byKey(const Key('mission-dialogue-scroll'));
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find.descendant(of: scroll, matching: find.byType(Scrollable)),
          )
          .position;
      await tester.drag(scroll, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(position().pixels, greaterThan(0));
      await tester.tap(find.byKey(const Key('opening-next')));
      await tester.pumpAndSettle();
      expect(position().pixels, 0);
      expect(find.text('あなたは、計画の指揮官').hitTestable(), findsOneWidget);
      await tester.drag(scroll, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('opening-back')));
      await tester.pumpAndSettle();
      expect(position().pixels, 0);
      expect(find.text('青い星から、次の故郷へ').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final initialSetup in [true, false]) {
    testWidgets(
      'mission naming stays usable with landscape keyboard (initial setup: $initialSetup)',
      (tester) async {
        final controller = GameController(_OpeningSave(), now: () => epoch);
        await controller.initialize(startTimer: false);
        addTearDown(controller.dispose);
        final originalName = controller.state.cityName('earth_delta');
        await mount(
          tester,
          controller,
          size: const Size(568, 320),
          textScale: 1.5,
          home: initialSetup
              ? null
              : Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: TextButton(
                        key: const Key('open-mission-dialog'),
                        onPressed: () => showMissionNames(context, controller),
                        child: const Text('名前を変更'),
                      ),
                    ),
                  ),
                ),
        );
        await tester.tap(
          find.byKey(
            Key(initialSetup ? 'opening-skip' : 'open-mission-dialog'),
          ),
        );
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 170);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        for (final (id, value) in [
          ('mission-city-earth_delta', '青空市'),
          ('mission-rocket', 'はるか'),
          ('mission-city-mars_arcadia', '夜明け'),
        ]) {
          final field = find.byKey(Key(id));
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          await tester.enterText(field, value);
          await tester.pumpAndSettle();
          expect(
            find
                .descendant(of: field, matching: find.byType(EditableText))
                .hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
        final save = find.byKey(const Key('mission-names-save'));
        final cancel = find.byKey(const Key('mission-names-cancel'));
        expect(save.hitTestable(), findsOneWidget);
        expect(cancel.hitTestable(), findsOneWidget);
        await tester.tap(initialSetup ? save : cancel);
        // The next route is tested at its normal height after keyboard dismissal.
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(
          controller.state.cityName('earth_delta'),
          initialSetup ? '青空市' : originalName,
        );
        if (initialSetup) {
          expect(controller.state.openingSeen, isTrue);
          expect(controller.state.rocketName, 'はるか');
        } else {
          expect(find.byType(Dialog), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
