/// A read-only impression of the saved Mars development for the title scene.
///
/// The environment channels are artistic accents, not physical measurements or
/// a judgement that Mars is habitable. Gameplay owns all progress and saves.
class TitleSceneSnapshot {
  const TitleSceneSnapshot({
    this.settlementCount = 0,
    this.infrastructureCount = 0,
    this.greenhouseCount = 0,
    this.residentCount = 0,
    this.activity = 0,
    this.greenery = 0,
    this.atmosphere = 0,
    this.cloudCoverage = 0,
    this.hasExploration = false,
  });

  static const pristine = TitleSceneSnapshot();

  final int settlementCount,
      infrastructureCount,
      greenhouseCount,
      residentCount;

  /// Normalized visual channels. Clouds and colour hint at a future Mars,
  /// without adding environmental simulation or achievement conditions.
  final double activity, greenery, atmosphere, cloudCoverage;
  final bool hasExploration;

  bool hasSameModel(TitleSceneSnapshot other) =>
      settlementCount == other.settlementCount &&
      infrastructureCount == other.infrastructureCount &&
      greenhouseCount == other.greenhouseCount &&
      residentCount == other.residentCount &&
      activity == other.activity &&
      greenery == other.greenery &&
      atmosphere == other.atmosphere &&
      cloudCoverage == other.cloudCoverage &&
      hasExploration == other.hasExploration;
}
