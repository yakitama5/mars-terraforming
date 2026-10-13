import 'package:flutter/material.dart';

const strategyMint = Color(0xffa2dfc8);
const strategyMuted = Color(0xffa4b6c1);
const strategyCopper = Color(0xffedb48c);
const strategyLine = Color(0xff2d434f);
const strategyPanel = Color(0xff142630);

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

String signedNumber(int value) => value > 0 ? '+$value' : '$value';

class StrategyCard extends StatelessWidget {
  const StrategyCard({
    super.key,
    required this.child,
    this.selected = false,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: selected ? const Color(0xff203d40) : strategyPanel,
      border: Border.all(color: selected ? strategyMint : strategyLine),
      borderRadius: BorderRadius.circular(12),
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
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
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
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: const TextStyle(color: strategyMuted, fontSize: 12),
          ),
        ),
        Expanded(
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
  final Widget detail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 650) {
        return Column(
          children: [
            Expanded(child: overview),
            Expanded(child: detail),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: overview),
          const VerticalDivider(width: 1, color: strategyLine),
          SizedBox(
            width: constraints.maxWidth > 1100 ? 360 : 310,
            child: detail,
          ),
        ],
      );
    },
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
