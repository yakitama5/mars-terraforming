import 'package:flutter/material.dart';

import '../domain/game_state.dart';
import 'mission_adviser.dart';
import 'mission_speech.dart';
import 'strategy_colors.dart';

/// The dialogue reserves its own space; the portrait cannot intercept map input.
class FirstRunCoach extends StatelessWidget {
  const FirstRunCoach({
    super.key,
    required this.step,
    required this.instruction,
    this.portraitVisible = true,
  });

  final FirstRunTutorialStep step;
  final String instruction;
  final bool portraitVisible;

  static String speech(FirstRunTutorialStep step) => switch (step) {
    FirstRunTutorialStep.placeHousing => 'まずは住宅地区です。施設、空地、建設予約の順に選びましょう。',
    FirstRunTutorialStep.finishConstruction =>
      '今回は私が建設をお手伝いします。「ルナに完成を頼む」を押してください。',
    FirstRunTutorialStep.income =>
      '完成です！ 住宅の税収が毎分入ります。維持費を引いた収支を、上の数字で確認しましょう。',
    FirstRunTutorialStep.startResearch =>
      '次は「生命維持の実証」を研究します。街の収入が、宇宙で暮らす技術につながります。',
    FirstRunTutorialStep.researchStarted =>
      '研究が始まりました！ 次の住宅からは完成を待ちます。その間も街づくりを進められます。続きはガイドでご案内します。',
    FirstRunTutorialStep.completed => '',
  };

  static String summary(FirstRunTutorialStep step) => switch (step) {
    FirstRunTutorialStep.placeHousing => '海沿いの住宅は税収が増えます。',
    FirstRunTutorialStep.finishConstruction => '最初の1棟だけ、私が即完成！',
    FirstRunTutorialStep.income => '税収−維持費が毎分の収支です。',
    FirstRunTutorialStep.startResearch => '街の収入を、宇宙で暮らす技術に。',
    FirstRunTutorialStep.researchStarted => '次の建設は、通常の工期で完成します。',
    FirstRunTutorialStep.completed => '',
  };

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.sizeOf(context).width < 650;
    final enlarged = MediaQuery.textScalerOf(context).scale(13) > 17;
    final portraitSize = small ? 130.0 : 160.0;
    return MissionSpeech(
      audioId: 'first_run_${step.name}',
      child: SizedBox(
        key: const Key('first-run-coach'),
        height: portraitVisible
            ? (enlarged ? 132 : 104)
            : (enlarged ? 116 : 92),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (portraitVisible)
              Positioned(
                left: 0,
                bottom: 0,
                width: portraitSize,
                height: portraitSize,
                child: FirstRunPortrait(step: step, size: portraitSize),
              ),
            Positioned.fill(
              left: portraitVisible ? portraitSize - 24 : 0,
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 4, 8, 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: strategyPanel.withValues(alpha: .86),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: strategyBlue.withValues(alpha: .7)),
                ),
                child: Semantics(
                  key: ValueKey('first-run-announcement-${step.name}'),
                  liveRegion: true,
                  label: 'ルナ。${speech(step)} $instruction',
                  excludeSemantics: true,
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Column(
                      key: ValueKey('$step:$instruction'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ルナ · ${step.index + 1}/5',
                          style: const TextStyle(
                            fontSize: 11,
                            color: strategyBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Expanded(
                          child: SingleChildScrollView(
                            key: const Key('first-run-instruction-scroll'),
                            child: Text(
                              '${summary(step)}\n$instruction',
                              key: const Key('first-run-instruction'),
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reuses the same portrait motion and lifecycle without intercepting map taps.
class FirstRunPortrait extends StatelessWidget {
  const FirstRunPortrait({super.key, required this.step, required this.size});
  final FirstRunTutorialStep step;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: MinaPortrait(
        size: size,
        expression:
            step == FirstRunTutorialStep.income ||
                step == FirstRunTutorialStep.researchStarted
            ? MinaExpression.joy
            : MinaExpression.normal,
      ),
    ),
  );
}
