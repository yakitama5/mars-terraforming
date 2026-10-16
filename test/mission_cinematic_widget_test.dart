import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_terraforming/presentation/mission_cinematic.dart';
import 'package:mars_terraforming/presentation/mission_sound.dart';

void main() {
  late VoidCallback ready;
  late ValueChanged<Object> fail;
  late double progress;
  late int finished;

  Future<void> mount(
    WidgetTester tester, {
    bool reduceMotion = false,
    Size size = const Size(844, 390),
    double textScale = 1,
    MissionAudioTrack? audio,
  }) async {
    progress = 0;
    finished = 0;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            body: MissionCinematic(
              onFinished: () => finished++,
              audioTrack: audio,
              sceneBuilder: (_, value, onReady, onError) {
                progress = value;
                ready = onReady;
                fail = onError;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'film waits for actual scene then visits all five chapters once',
    (tester) async {
      await mount(tester);
      await tester.pump(const Duration(seconds: 50));
      expect(progress, 0);
      expect(finished, 0);
      ready();
      await tester.pump();
      for (var chapter = 0; chapter < 5; chapter++) {
        expect(
          find.text(
            '${chapter + 1}  /  ${MissionCinematic.chapters[chapter].$1}',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 8));
        await tester.pump(const Duration(milliseconds: 450));
      }
      expect(finished, 1);
      await tester.tap(find.byKey(const Key('opening-cinematic-skip')));
      expect(finished, 1);
    },
  );

  testWidgets('pause and application suspension preserve the film position', (
    tester,
  ) async {
    await mount(tester);
    ready();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const Key('cinematic-pause')));
    await tester.pump();
    final paused = progress;
    await tester.pump(const Duration(seconds: 20));
    expect(progress, paused);
    await tester.tap(find.byKey(const Key('cinematic-pause')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(progress, greaterThan(paused));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final background = progress;
    await tester.pump(const Duration(seconds: 60));
    expect(progress, background);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(progress, closeTo(background + .025, .002));
    expect(finished, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 60));
    expect(finished, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'motion reduction uses five static shots and explicit progression',
    (tester) async {
      await mount(tester, reduceMotion: true);
      ready();
      await tester.pump();
      await tester.pump(const Duration(seconds: 60));
      expect(progress, .08);
      expect(finished, 0);
      for (var i = 0; i < 5; i++) {
        expect(
          find.text('${i + 1}  /  ${MissionCinematic.chapters[i].$1}'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('cinematic-next-still')));
        await tester.pumpAndSettle();
      }
      expect(finished, 1);
    },
  );

  testWidgets(
    'unavailable rendering still offers an immediate way into the story',
    (tester) async {
      await mount(tester);
      fail(StateError('GPU unavailable'));
      await tester.pump();
      expect(find.textContaining('映像を読み込めませんでした'), findsOneWidget);
      ready();
      await tester.pump(const Duration(seconds: 60));
      expect(progress, 0);
      await tester.tap(find.byKey(const Key('opening-cinematic-skip')));
      expect(finished, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all still captions and controls fit small landscape with large text',
    (tester) async {
      await mount(
        tester,
        reduceMotion: true,
        size: const Size(568, 320),
        textScale: 1.5,
      );
      ready();
      await tester.pump();
      for (var chapter = 0; chapter < 5; chapter++) {
        expect(
          find.byKey(const Key('opening-cinematic-skip')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('cinematic-next-still')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('cinematic-next-still')));
        await tester.pumpAndSettle();
      }
      expect(finished, 1);
    },
  );

  testWidgets(
    'sound follows pause, lifecycle, mute and skip without restarting',
    (tester) async {
      missionSoundEnabled.value = true;
      final audio = _FakeAudio();
      await mount(tester, audio: audio);
      ready();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(audio.positions.length, 1);
      await tester.tap(find.byKey(const Key('cinematic-pause')));
      await tester.pump();
      expect(audio.pauses, 1);
      await tester.pump(const Duration(seconds: 10));
      await tester.tap(find.byKey(const Key('cinematic-pause')));
      await tester.pump();
      expect(audio.positions.last.inMilliseconds, closeTo(3000, 20));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 20));
      expect(audio.pauses, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(audio.positions.last.inMilliseconds, closeTo(3000, 20));
      await tester.tap(find.byKey(const Key('cinematic-sound')));
      await tester.pump();
      expect(missionSoundEnabled.value, isFalse);
      expect(audio.pauses, 3);
      await tester.tap(find.byKey(const Key('cinematic-sound')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('opening-cinematic-skip')));
      expect(audio.pauses, 4);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(audio.disposed, isTrue);
    },
  );

  testWidgets(
    'autoplay refusal can be retried by a gesture, film remains usable',
    (tester) async {
      missionSoundEnabled.value = true;
      final audio = _FakeAudio()..refuse = true;
      await mount(tester, audio: audio);
      ready();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('cinematic-enable-sound')), findsOneWidget);
      expect(progress, greaterThan(0));
      audio.refuse = false;
      await tester.tap(find.byKey(const Key('cinematic-enable-sound')));
      await tester.pump();
      expect(audio.positions.last, Duration.zero);
      expect(find.byKey(const Key('cinematic-enable-sound')), findsNothing);
      await tester.tap(find.byKey(const Key('opening-cinematic-skip')));
      expect(finished, 1);
    },
  );

  testWidgets('reduced motion never starts an invisible audio timeline', (
    tester,
  ) async {
    missionSoundEnabled.value = true;
    final audio = _FakeAudio();
    await mount(tester, reduceMotion: true, audio: audio);
    ready();
    await tester.pump(const Duration(seconds: 10));
    expect(audio.positions, isEmpty);
    await tester.tap(find.byKey(const Key('cinematic-next-still')));
    await tester.pump();
    expect(audio.positions, isEmpty);
  });
}

class _FakeAudio implements MissionAudioTrack {
  final List<Duration> positions = [];
  int pauses = 0;
  bool disposed = false;
  bool refuse = false;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> play(Duration position) async {
    positions.add(position);
    if (refuse) throw StateError('Autoplay denied');
  }

  @override
  Future<void> pause() async {
    pauses++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
