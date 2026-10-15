import 'package:flutter/material.dart';

import 'strategy_colors.dart';

/// The same portrait accompanies the opening, guide, and contextual advice.
class MinaAvatar extends StatelessWidget {
  const MinaAvatar({super.key, this.size = 40, this.semanticLabel});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    excludeSemantics: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: strategySelected,
        shape: BoxShape.circle,
        border: Border.all(color: strategyBlue.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/mission_control.png',
        fit: BoxFit.cover,
        alignment: Alignment.center,
        cacheWidth: (size * 3).round(),
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) =>
            Icon(Icons.support_agent, size: size * 0.6, color: strategyBlue),
      ),
    ),
  );
}
