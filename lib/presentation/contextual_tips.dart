import 'package:flutter/material.dart';

import '../domain/contextual_tips.dart';
import '../domain/game_state.dart';
import 'mission_adviser.dart';
import 'mission_dialogue.dart';
import 'strategy_widgets.dart';

/// Shows one suggestion at a time. The host owns dismissal persistence and
/// navigation; tips never create notifications or interrupt ongoing work.
class ContextualTipsPanel extends StatefulWidget {
  const ContextualTipsPanel({
    super.key,
    required this.game,
    required this.onOpen,
    required this.onDismiss,
    this.dismissedIds = const {},
    this.compact = false,
  });

  final GameState game;
  final ValueChanged<ContextualTip> onOpen;
  final ValueChanged<String> onDismiss;
  final Set<String> dismissedIds;
  final bool compact;

  @override
  State<ContextualTipsPanel> createState() => _ContextualTipsPanelState();
}

class _ContextualTipsPanelState extends State<ContextualTipsPanel> {
  // Tip IDs carry a stable category before the optional plan/facility ID.
  // Serious cautions concern the queue rule, never the player's choices.
  MinaExpression _expressionFor(ContextualTip tip) =>
      switch (tip.id.split(':').first) {
        'paused' ||
        'staff' ||
        'budget' ||
        'resource' ||
        'unassigned' ||
        'low-operating-funds' => MinaExpression.sorrow,
        'unlimited' || 'training-limit' => MinaExpression.anger,
        'habitat-choice' => MinaExpression.joy,
        'partnership' ||
        'parallel-city' ||
        'parallel-research' => MinaExpression.delight,
        _ => MinaExpression.normal,
      };

  Future<void> _showExplanation(ContextualTip tip) async {
    final openDestination = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 420),
          child: SizedBox(
            width: double.infinity,
            height: MediaQuery.sizeOf(dialogContext).height,
            child: MissionDialogue(
              key: const Key('contextual-tip-dialogue'),
              text: tip.detail,
              title: tip.title,
              expression: _expressionFor(tip),
              dialogueKey: tip.id,
              actions: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: const Key('close-contextual-tip-dialogue'),
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('閉じる'),
                  ),
                  FilledButton.icon(
                    key: const Key('open-contextual-tip-dialogue'),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(tip.actionLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (openDestination == true && mounted) widget.onOpen(tip);
  }

  @override
  Widget build(BuildContext context) {
    final tip = evaluateContextualTips(
      widget.game,
      dismissedIds: widget.dismissedIds,
      limit: 1,
    ).firstOrNull;
    if (tip == null) return const SizedBox.shrink();
    final needsAttention = tip.priority >= 80;
    final accent = needsAttention ? strategyWarning : strategyBlue;
    return StrategyCard(
      key: const Key('contextual-tips-panel'),
      padding: EdgeInsets.all(widget.compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MinaAvatar(
                size: 32,
                expression: _expressionFor(tip),
                semanticLabel: '秘書ミナからのアドバイス',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tip.title,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const Key('dismiss-contextual-tip'),
                tooltip: 'このTipsを非表示',
                onPressed: () => widget.onDismiss(tip.id),
                icon: const Icon(Icons.close, size: 16),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
          if (needsAttention)
            Text(
              tip.detail,
              style: const TextStyle(
                color: strategyMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              TextButton(
                key: const Key('open-contextual-tip'),
                onPressed: () => widget.onOpen(tip),
                child: Text(
                  tip.actionLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: needsAttention ? strategyCopper : strategyMint,
                  ),
                ),
              ),
              TextButton(
                key: const Key('toggle-contextual-tip-detail'),
                onPressed: () => _showExplanation(tip),
                child: const Text(
                  'ミナの説明',
                  style: TextStyle(fontSize: 11, color: strategyMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
