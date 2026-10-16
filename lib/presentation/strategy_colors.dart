import 'package:flutter/material.dart';

// Earth blue identifies controls and selection. Outcomes always include a
// symbol or wording as well as color, so red/green discrimination is not needed.
const strategyBlue = Color(0xff8ac8ff);
const strategyBenefit = Color(0xff70ded6);
const strategyWarning = Color(0xffffd080);
const strategyDanger = Color(0xffffb5a8);
const strategyMuted = Color(0xffb5c9db);
const strategyText = Color(0xffeef5ff);
const strategyLine = Color(0xff34516b);
const strategyPanel = Color(0xff10273c);
const strategySurface = Color(0xff0c2033);
const strategyBackground = Color(0xff081728);
const strategySelected = Color(0xff173e60);

// Compatibility names for screens that have not yet adopted outcome roles.
const strategyMint = strategyBlue;
const strategyCopper = strategyWarning;

enum StrategyTone { benefit, warning, loss, neutral }

Color strategyToneColor(StrategyTone tone) => switch (tone) {
  StrategyTone.benefit => strategyBenefit,
  StrategyTone.warning => strategyWarning,
  StrategyTone.loss => strategyDanger,
  StrategyTone.neutral => strategyMuted,
};

IconData strategyToneIcon(StrategyTone tone) => switch (tone) {
  StrategyTone.benefit => Icons.add_circle_outline,
  StrategyTone.warning => Icons.info_outline,
  StrategyTone.loss => Icons.remove_circle_outline,
  StrategyTone.neutral => Icons.drag_handle,
};
