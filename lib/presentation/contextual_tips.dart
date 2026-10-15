import 'package:flutter/material.dart';

import '../domain/contextual_tips.dart';
import '../domain/game_state.dart';
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
  String? expandedTipId;

  @override
  Widget build(BuildContext context) {
    final tip = evaluateContextualTips(
      widget.game,
      dismissedIds: widget.dismissedIds,
      limit: 1,
    ).firstOrNull;
    if (tip == null) return const SizedBox.shrink();
    final needsAttention = tip.priority >= 80;
    final expanded = needsAttention || expandedTipId == tip.id;
    final accent = needsAttention ? strategyCopper : strategyMuted;
    return StrategyCard(
      key: const Key('contextual-tips-panel'),
      padding: EdgeInsets.all(widget.compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                needsAttention ? Icons.info_outline : Icons.lightbulb_outline,
                size: 17,
                color: accent,
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
          Text(
            tip.detail,
            maxLines: expanded ? null : 2,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
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
              if (!needsAttention)
                TextButton(
                  key: const Key('toggle-contextual-tip-detail'),
                  onPressed: () => setState(() {
                    expandedTipId = expanded ? null : tip.id;
                  }),
                  child: Text(
                    expanded ? '説明を閉じる' : '詳しく',
                    style: const TextStyle(fontSize: 11, color: strategyMuted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
