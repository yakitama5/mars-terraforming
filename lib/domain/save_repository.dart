/// Persistence boundary; game progress is independent of the disk and Flutter.
abstract interface class SaveRepository {
  Future<SaveLoadResult> load();
  Future<void> save(Map<String, dynamic> snapshot);
}

/// A committed, complete world snapshot. Domain content validation is separate.
class SaveLoadResult {
  const SaveLoadResult({
    required this.data,
    required this.recovered,
    required this.generation,
  });

  final Map<String, dynamic>? data;
  final bool recovered;
  final int generation;
}

/// A different owner changed this world. Continuing or retrying a stale
/// snapshot would replace another session's progress, so the caller must stop.
class SaveConflictException implements Exception {
  const SaveConflictException(this.message);

  final String message;

  @override
  String toString() => message;
}
