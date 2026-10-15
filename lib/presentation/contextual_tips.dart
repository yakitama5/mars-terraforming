import 'package:flutter/material.dart';

import '../domain/contextual_tips.dart';
import '../domain/game_state.dart';
import 'strategy_widgets.dart';

/// Shows one suggestion at a time. The host owns dismissal persistence and
/// navigation; tips never create notifications or interrupt ongoing work.
class ContextualTipsPanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final tip = evaluateContextualTips(
      game,
      dismissedIds: dismissedIds,
      limit: 1,
    ).firstOrNull;
    if (tip == null) return const SizedBox.shrink();
    return StrategyCard(
      key: const Key('contextual-tips-panel'),
      padding: EdgeInsets.all(compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                tip.priority >= 80
                    ? Icons.info_outline
                    : Icons.lightbulb_outline,
                size: 17,
                color: strategyCopper,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tip.title,
                  style: const TextStyle(
                    color: strategyCopper,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: const Key('dismiss-contextual-tip'),
                tooltip: 'このTipsを非表示',
                onPressed: () => onDismiss(tip.id),
                icon: const Icon(Icons.close, size: 16),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
          Text(
            tip.detail,
            style: const TextStyle(color: strategyMuted, fontSize: 11),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('open-contextual-tip'),
              onPressed: () => onOpen(tip),
              child: Text(
                tip.actionLabel,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
