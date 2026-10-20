import 'package:flutter/material.dart';

import 'strategy_colors.dart';
export 'strategy_colors.dart';

String gameDuration(int ms) {
  final seconds = (ms / 1000).ceil();
  if (seconds >= 86400) {
    final hours = (seconds % 86400) ~/ 3600;
    return '${seconds ~/ 86400}日${hours > 0 ? '$hours時間' : ''}';
  }
  if (seconds >= 3600) {
    final minutes = (seconds % 3600) ~/ 60;
    return '${seconds ~/ 3600}時間${minutes > 0 ? '$minutes分' : ''}';
  }
  return seconds < 60
      ? '$seconds秒'
      : '${seconds ~/ 60}分${seconds % 60 == 0 ? '' : '${seconds % 60}秒'}';
}

String formatInteger(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);
String signedNumber(int value) =>
    value > 0 ? '+${formatInteger(value)}' : formatInteger(value);
String dollars(int value) => '${formatInteger(value)}ドル';
String signedDollars(int value) => '${signedNumber(value)}ドル';
String legacyCurrencyLabel(String value) => value.replaceAllMapped(
  RegExp(r'([+-]?\d+) Cr'),
  (match) {
    final number = int.parse(match[1]!);
    return match[1]!.startsWith('+') ? signedDollars(number) : dollars(number);
  },
);

class StrategyCard extends StatelessWidget {
  const StrategyCard({
    super.key,
    required this.child,
    this.selected = false,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: selected ? strategySelected : strategyPanel,
      border: Border.all(color: selected ? strategyMint : strategyLine),
      borderRadius: BorderRadius.circular(2),
    ),
    child: child,
  );
}

class StrategyHeading extends StatelessWidget {
  const StrategyHeading(this.title, this.subtitle, {super.key});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(color: strategyMuted, fontSize: 12),
        ),
      ],
    ),
  );
}

class StrategyStat extends StatelessWidget {
  const StrategyStat(
    this.label,
    this.value, {
    super.key,
    this.color = strategyMint,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(color: strategyMuted, fontSize: 11)),
      Text(
        value,
        style: TextStyle(
          fontSize: 17,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class StrategyFact extends StatelessWidget {
  const StrategyFact(this.label, this.value, {super.key, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: strategyMuted, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(value, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    ),
  );
}

class StrategySplit extends StatelessWidget {
  const StrategySplit({
    super.key,
    required this.overview,
    required this.detail,
  });
  final Widget overview;
  final Widget? detail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 650 &&
          constraints.maxHeight >= constraints.maxWidth) {
        return Column(
          children: [
            Expanded(child: overview),
            if (detail != null) Expanded(child: detail!),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: overview),
          if (detail != null)
            const VerticalDivider(width: 1, color: strategyLine),
          if (detail != null)
            SizedBox(
              width: constraints.maxWidth > 1100
                  ? 360
                  : constraints.maxWidth < 650
                  ? constraints.maxWidth * .48
                  : 310,
              child: Material(color: strategySurface, child: detail!),
            ),
        ],
      );
    },
  );
}

/// A signed result stays understandable in grayscale and to screen readers.
class StrategyOutcome extends StatelessWidget {
  const StrategyOutcome(
    this.label, {
    super.key,
    required this.tone,
    this.fontSize = 12,
  });
  final String label;
  final StrategyTone tone;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: Icon(
          strategyToneIcon(tone),
          color: strategyToneColor(tone),
          size: 16,
        ),
      ),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          label,
          style: TextStyle(color: strategyToneColor(tone), fontSize: fontSize),
        ),
      ),
    ],
  );
}

class StrategyActionBar extends StatelessWidget {
  const StrategyActionBar({super.key, required this.child, this.message});
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
    decoration: const BoxDecoration(
      color: strategyPanel,
      border: Border(top: BorderSide(color: strategyLine)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              message!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: strategyCopper),
            ),
          ),
        child,
      ],
    ),
  );
}
