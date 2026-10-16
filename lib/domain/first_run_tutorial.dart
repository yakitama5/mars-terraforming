/// The short, required first-world walkthrough. Longer guidance stays optional.
/// Names are persisted; an absent field means a pre-walkthrough world.
enum FirstRunTutorialStep {
  placeHousing,
  finishConstruction,
  income,
  startResearch,
  researchStarted,
  completed;

  static FirstRunTutorialStep fromSaved(Object? value) {
    if (value == null) return completed;
    for (final step in values) {
      if (step.name == value) return step;
    }
    throw const FormatException('初回チュートリアルの段階が不正です');
  }
}
