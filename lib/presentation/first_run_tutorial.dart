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
    final legacyRunning = plan?.status == 'running';
    final manualStart = plan?.requiresManualStart == true;
    final unlocked = game.research.contains(task.id);
    final pointCost = GameContent.researchPointCost(task.id);
    final facts = legacyRunning
        ? '着手済み · 残り ${gameDuration(plan!.remainingMs)}'
        : unlocked
        ? '$pointCost RPを使用 · 解放済み'
        : '必要 $pointCost RP · 保有 ${game.researchPoints.toStringAsFixed(1)} RP';
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
                  legacyResearchRunning: legacyRunning,
                  instruction: started
                      ? legacyRunning
                            ? '着手済みの研究は継続中。続きはガイドへ！'
                            : '次は居住キットを製造。続きはガイドへ！'
                      : '共通RPを使って、右で最初の技術を解放。',
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
                          started
                              ? legacyRunning
                                    ? '着手済みの研究を継続中'
                                    : '技術を解放しました'
                              : task.name,
                          key: const Key('first-run-research-title'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          facts,
                          key: const Key('first-run-research-cost-time'),
                          semanticsLabel: legacyRunning
                              ? '研究費は支払済み。残り時間 ${gameDuration(plan!.remainingMs)}。追加RPは必要ありません。'
                              : facts,
                          maxLines: 2,
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
                              ? legacyRunning
                                    ? '着手済みの研究は、追加RPを使わず残り時間から続きます。その間も、街づくりや受注を並行できます。'
                                    : '技術を確実に解放できました。資金と工場を使って居住キットを製造し、火星へ届けましょう。新しい施設の建設には通常の費用と工期を使います。'
                              : '稼働中の研究施設で共通RPを蓄え、都市条件と必要量をそろえて技術を解放します。解放後は、資金と工場を使って居住キットを製造できます。',
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
                      onPressed:
                          controller.busy ||
                              controller.error != null ||
                              (!started &&
                                  ((plan != null && !manualStart) ||
                                      game.researchPoints < pointCost))
                          ? null
                          : () async {
                              if (started) {
                                if (await controller
                                    .continueFirstRunTutorial()) {
                                  onComplete();
                                }
                              } else {
                                await controller.command(
                                  (engine) => manualStart
                                      ? engine.startPlan(plan!.id)
                                      : engine.unlockResearch(task.id),
                                );
                              }
                            },
                      icon: Icon(
                        started ? Icons.check : Icons.science_outlined,
                        size: 18,
                      ),
                      label: Text(started ? 'ガイドと開発を続ける' : '技術を解放する'),
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
