import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/domain/colony_ending.dart';
import 'package:mars_terraforming/domain/game_state.dart';
import 'package:mars_terraforming/presentation/colony_endings.dart';

void main() {
  test('only a durable route achievement unlocks its ending after reload', () {
    final game = GameState.initial(DateTime.utc(2026, 10, 16));
    game.habitatChoice = 'dome';
    game.achievements.add('first_landing');
    expect(ColonyEnding.all.any((ending) => ending.isUnlocked(game)), isFalse);
    game.achievements.add('dome_habitat');
    final restored = GameState.fromJson(game.toJson());
    expect(ColonyEnding.all.first.isUnlocked(restored), isTrue);
    expect(ColonyEnding.all.last.isUnlocked(restored), isFalse);
  });

  for (final ending in ColonyEnding.all) {
    testWidgets('${ending.route} ending replays without changing the world', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(844, 393);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final game = GameState.initial(DateTime.utc(2026, 10, 16));
      game.achievements.add(ending.id);
      game.identity = game.identity.renamed(
        cities: {'mars_arcadia': '青空基地'},
        rocket: 'ほしのわ',
      );
      final before = jsonEncode(game.toJson());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showColonyEndings(context, game: game),
                child: const Text('物語'),
              ),
            ),
          ),
        ),
      );
      for (var replay = 0; replay < 2; replay++) {
        await tester.tap(find.text('物語'));
        await tester.pumpAndSettle();
        final play = find.byKey(Key('play-ending-${ending.id}'));
        await tester.ensureVisible(play);
        await tester.pumpAndSettle();
        await tester.tap(play);
        await tester.pumpAndSettle();
        for (var scene = 0; scene < ending.scenes.length; scene++) {
          expect(find.text(ending.scenes[scene].title), findsOneWidget);
          expect(
            find.byKey(const Key('ending-next')).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('ending-next')));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const Key('close-colony-endings')), findsNothing);
        expect(jsonEncode(game.toJson()), before);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
