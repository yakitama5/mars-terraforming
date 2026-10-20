import 'package:flutter/material.dart';

import '../domain/research_catalog.dart';

/// Artwork and presentation only; research rules stay in the domain.
extension ResearchFieldTheme on ResearchField {
  Color get color => switch (this) {
    ResearchField.bio => const Color(0xff87e0b1),
    ResearchField.mechanics => const Color(0xffffce8b),
    ResearchField.materials => const Color(0xff83dceb),
    ResearchField.energy => const Color(0xffd0b5ff),
  };

  Color get shadowColor => switch (this) {
    ResearchField.bio => const Color(0xff103b30),
    ResearchField.mechanics => const Color(0xff422d22),
    ResearchField.materials => const Color(0xff123c4c),
    ResearchField.energy => const Color(0xff30244d),
  };

  IconData get icon => switch (this) {
    ResearchField.bio => Icons.biotech_outlined,
    ResearchField.mechanics => Icons.precision_manufacturing_outlined,
    ResearchField.materials => Icons.diamond_outlined,
    ResearchField.energy => Icons.bolt_outlined,
  };

  Alignment get cardAlignment => switch (this) {
    ResearchField.bio => Alignment.centerRight,
    ResearchField.mechanics => Alignment.bottomRight,
    ResearchField.materials => Alignment.center,
    ResearchField.energy => Alignment.topRight,
  };
}

class ResearchArtwork extends StatelessWidget {
  const ResearchArtwork({
    super.key,
    required this.field,
    this.alignment = Alignment.center,
    this.opacity = 1,
  });

  final ResearchField field;
  final Alignment alignment;
  final double opacity;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Opacity(
      opacity: opacity,
      child: Image.asset(
        field.assetPath,
        fit: BoxFit.cover,
        alignment: alignment,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [field.shadowColor, const Color(0xff071626)],
            ),
          ),
          child: Center(
            child: Icon(
              field.icon,
              color: field.color.withValues(alpha: .18),
              size: 80,
            ),
          ),
        ),
      ),
    ),
  );
}
