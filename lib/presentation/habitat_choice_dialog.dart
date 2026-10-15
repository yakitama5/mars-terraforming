import 'package:flutter/material.dart';

import '../application/game_controller.dart';

/// One confirmation shared by the city and transport entry points.
Future<void> confirmHabitatChoice(
  BuildContext context,
  GameController controller,
  String choice,
) async {
  final dome = choice == 'dome';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('${dome ? 'ドーム居住' : '地下居住'}で進めますか？'),
      scrollable: true,
      content: Text(
        '${dome ? '平地' : 'クレーター'}に建てる居住地区の効果が高まります。\n\n'
        '居住方式は後から変更できません。都市の地形を見てから選ぶこともできます。',
      ),
      actions: [
        TextButton(
          key: const Key('cancel-habitat-choice'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('選び直す'),
        ),
        FilledButton(
          key: const Key('confirm-habitat-choice'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('この方式で進める'),
        ),
      ],
    ),
  );
  if (!context.mounted || confirmed != true) return;
  await controller.command((engine) => engine.chooseHabitat(choice));
}
