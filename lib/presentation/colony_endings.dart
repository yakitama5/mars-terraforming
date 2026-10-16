import 'package:flutter/material.dart';

import '../domain/colony_ending.dart';
import '../domain/game_state.dart';
import 'mission_adviser.dart';
import 'mission_dialogue.dart';
import 'strategy_widgets.dart';

Future<void> showColonyEndings(
  BuildContext context, {
  required GameState game,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ColonyEndingsDialog(game: game),
);

class _ColonyEndingsDialog extends StatefulWidget {
  const _ColonyEndingsDialog({required this.game});
  final GameState game;

  @override
  State<_ColonyEndingsDialog> createState() => _ColonyEndingsDialogState();
}

class _ColonyEndingsDialogState extends State<_ColonyEndingsDialog> {
  ColonyEnding? selected;
  int scene = 0;

  MinaExpression get expression => switch ((selected?.id, scene)) {
    ('dome_habitat', 1) || ('underground_habitat', 1) => MinaExpression.delight,
    ('dome_habitat', 0) ||
    ('dome_habitat', 2) ||
    ('underground_habitat', 0) ||
    ('underground_habitat', 2) => MinaExpression.joy,
    _ => MinaExpression.normal,
  };

  @override
  Widget build(BuildContext context) {
    final ending = selected;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 560),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                ending?.id == 'underground_habitat'
                    ? 'assets/images/underground_home.png'
                    : 'assets/images/colony_home.png',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: strategyBackground),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: strategyBackground.withValues(
                  alpha: ending == null ? .80 : .25,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (ending == null) const MinaAvatar(size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ending == null ? '物語の記録' : '居住編 ED · ${ending.route}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('close-colony-endings'),
                        tooltip: '開発へ戻る',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ending == null
                        ? SingleChildScrollView(child: _catalogue())
                        : _story(ending),
                  ),
                  const SizedBox(height: 12),
                  if (ending != null)
                    Row(
                      children: [
                        Text(
                          '${scene + 1} / ${ending.scenes.length}',
                          style: const TextStyle(color: strategyMuted),
                        ),
                        const Spacer(),
                        TextButton(
                          key: const Key('ending-back'),
                          onPressed: () => setState(() {
                            if (scene > 0) {
                              scene--;
                            } else {
                              selected = null;
                            }
                          }),
                          child: Text(scene == 0 ? '記録へ' : '前へ'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const Key('ending-next'),
                          onPressed: () {
                            if (scene + 1 < ending.scenes.length) {
                              setState(() => scene++);
                            } else {
                              Navigator.pop(context);
                            }
                          },
                          child: Text(
                            scene + 1 < ending.scenes.length ? '次へ' : '開発を続ける',
                          ),
                        ),
                      ],
                    )
                  else
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('開発へ戻る'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogue() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('火星で見つける、それぞれの暮らし。', style: TextStyle(fontSize: 16)),
      const SizedBox(height: 4),
      const Text(
        '居住編の結末を迎えた後も、同じ世界で開発を続けられます。',
        style: TextStyle(color: strategyMuted, fontSize: 12),
      ),
      const SizedBox(height: 16),
      for (final ending in ColonyEnding.all)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StrategyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ending.title,
                  style: const TextStyle(fontSize: 18, color: strategyText),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ending.route} · ${ending.isUnlocked(widget.game) ? '達成済み' : ending.condition}',
                  style: const TextStyle(color: strategyMuted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: Key('play-ending-${ending.id}'),
                  onPressed: ending.isUnlocked(widget.game)
                      ? () => setState(() {
                          selected = ending;
                          scene = 0;
                        })
                      : null,
                  icon: Icon(
                    ending.isUnlocked(widget.game)
                        ? Icons.play_circle_outline
                        : Icons.lock_outline,
                    size: 18,
                  ),
                  label: Text(ending.isUnlocked(widget.game) ? '結末を見る' : '未達成'),
                ),
              ],
            ),
          ),
        ),
      const Text(
        'この世界では選んだ居住方式の結末へ進みます。\n全球の屋外居住と、その先の結末は今後の開発予定です。',
        style: TextStyle(color: strategyMuted, fontSize: 12),
      ),
    ],
  );

  Widget _story(ColonyEnding ending) => MissionDialogue(
    dialogueKey: '${ending.id}-$scene',
    title: ending.scenes[scene].title,
    text: [
      ending.scenes[scene].body,
      if (scene == ending.scenes.length - 1)
        '${widget.game.cityName('mars_arcadia')}へ、${widget.game.rocketName}がつないだ未来。',
    ].join('\n\n'),
    expression: expression,
    portraitSize: 250,
  );
}
