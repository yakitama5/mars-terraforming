import 'package:flutter/material.dart';

import '../application/game_controller.dart';
import '../domain/game_content.dart';
import '../domain/game_state.dart';
import 'city_development.dart';
import 'first_run_coach.dart';
import 'research_tree.dart';
import 'research_display.dart';
import 'strategy_widgets.dart';

/// The first few orders use the same district and research commands as play.
/// Only these teaching controls are exposed; saving and app recovery stay above.
class FirstRunTutorial extends StatelessWidget {
  const FirstRunTutorial({
    super.key,
    required this.controller,
    required this.onComplete,
    this.renderScene = true,
  });

  final GameController controller;
  final VoidCallback onComplete;
  final bool renderScene;

  @override
  Widget build(BuildContext context) {
    final step = controller.state.firstRunTutorial;
    if (step == FirstRunTutorialStep.placeHousing ||
        step == FirstRunTutorialStep.finishConstruction ||
        step == FirstRunTutorialStep.income) {
      return CityDevelopment(
        key: const Key('first-run-city'),
        controller: controller,
        cityId: 'earth_delta',
        onCityChanged: (_) {},
        onOpenResearch: (_) {},
        onSaveInvestment: (_) {},
        renderScene: renderScene,
        guidedFirstBuild: true,
      );
    }
    return _research(context, step);
  }

  Widget _research(BuildContext context, FirstRunTutorialStep step) {
    final game = controller.state;
    final task = GameContent.tasks['life_support']!;
    final started = step == FirstRunTutorialStep.researchStarted;
    final plan = game.plans
        .where((plan) => plan.taskId == task.id && !plan.isFinished)
        .firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: AbsorbPointer(
                    child: ResearchTree(
                      game: game,
                      selectedId: task.id,
                      controlsVisible: false,
                      onSelected: (_) {},
                      requirementReasons:
                          controller.engine!.researchRequirementReasons,
                    ),
                  ),
                ),
                FirstRunCoach(
                  step: step,
                  instruction: started ? '待つ間も街づくりを。続きはガイドへ！' : '右で最初の研究を予約。',
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, color: strategyLine),
          SizedBox(
            width: constraints.maxWidth < 650
                ? constraints.maxWidth * .44
                : 300,
            child: ColoredBox(
              color: strategySurface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      key: const Key('first-run-research-detail'),
                      padding: const EdgeInsets.all(14),
                      children: [
                        Text(
                          started ? '研究が始まりました' : task.name,
                          key: const Key('first-run-research-title'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${dollars(task.cost)} · ${started ? '残り ' : ''}${gameDuration(plan?.remainingMs ?? game.currentTaskDurationMs(task.id))}',
                          key: const Key('first-run-research-cost-time'),
                          semanticsLabel:
                              '${started ? '支払済み' : '研究費'} ${dollars(task.cost)}。${started ? '残り時間' : '研究期間'} ${gameDuration(plan?.remainingMs ?? game.currentTaskDurationMs(task.id))}',
                          maxLines: 1,
                          style: const TextStyle(fontSize: 12, height: 1.3),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          researchUnlockSummary(game, task),
                          style: const TextStyle(
                            fontSize: 13,
                            color: strategyBenefit,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          started
                              ? '次の建設は通常の工期です。研究を待つ間も、街づくりや受注を並行できます。'
                              : '水や空気を循環させる技術から、火星へ届ける居住キットを開発します。',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: FilledButton.icon(
                      key: Key(
                        started ? 'tutorial-finish' : 'queue-life_support',
                      ),
                      onPressed: controller.busy || controller.error != null
                          ? null
                          : () async {
                              if (started) {
                                if (await controller
                                    .continueFirstRunTutorial()) {
                                  onComplete();
                                }
                              } else {
                                await controller.command(
                                  (engine) => engine.enqueue(task.id),
                                );
                              }
                            },
                      icon: Icon(
                        started ? Icons.check : Icons.science_outlined,
                        size: 18,
                      ),
                      label: Text(started ? 'ガイドと開発を続ける' : '研究を予約する'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
