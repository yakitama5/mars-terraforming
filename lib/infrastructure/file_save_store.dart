import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/save_repository.dart';

export '../domain/save_repository.dart' show SaveLoadResult;

class SaveStoreException implements Exception {
  const SaveStoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class UnsupportedSaveVersionException extends SaveStoreException {
  UnsupportedSaveVersionException(this.version)
    : super('このセーブ形式（$version）は、このアプリでは読み込めません。データは保持されています。');

  final int version;
}

class CorruptSaveException extends SaveStoreException {
  const CorruptSaveException()
    : super('正常なセーブが見つかりませんでした。既存のデータを上書きせずに停止しました。');
}

/// Two committed generations, plus one uncommitted staging file.
///
/// The entire snapshot (including its processed clock and award ledger) is one
/// checksummed payload. A flushed pending file is committed only by renaming it
/// to the primary path. Pending files are NEVER replayed on load: a termination
/// before commit must not grant an operation that was not committed.
///
/// Before commit, the last valid primary becomes the backup by atomic rename.
/// If the process exits between the two renames, the backup is the latest valid
/// snapshot. A corrupt primary is never rotated over a valid backup. Unknown
/// schema versions in either committed file block both load and save.
///
/// Writes and reads for the same absolute path are serialized within this Dart
/// isolate, including across store instances. Multiple processes/isolates must
/// not write the same slot. File flush + same-directory rename protects against
/// process termination; directory fsync/power-loss durability is not guaranteed
/// by Dart's portable file API.
class FileSaveStore implements SaveRepository {
  FileSaveStore(this.directory, {this.slot = 'normal'}) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(slot)) {
      throw ArgumentError.value(slot, 'slot', '英数字・ハイフン・アンダースコアのみ');
    }
  }

  static const schemaVersion = 1;
  static final Map<String, Future<void>> _operations = {};

  final Directory directory;
  final String slot;

  File get _primary => File('${directory.path}/$slot.json');
  File get _previous => File('${directory.path}/$slot.previous.json');
  File get _pending => File('${directory.path}/$slot.pending.json');

  @override
  Future<SaveLoadResult> load() => _serial(() async {
    final committed = await _readCommitted();
    return SaveLoadResult(
      data: committed?.data,
      recovered: committed != null && committed.path != _primary.path,
      generation: committed?.generation ?? 0,
    );
  });

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    // Capture the call's state before waiting for any preceding disk operation.
    // This also rejects non-JSON values before touching existing save files.
    final payload = jsonEncode(snapshot);
    await _serial(() async {
      try {
        await directory.create(recursive: true);
        final committed = await _readCommitted();
        final generation = (committed?.generation ?? 0) + 1;
        final encoded = jsonEncode({
          'schemaVersion': schemaVersion,
          'generation': generation,
          'payload': payload,
          'checksum': _checksum(schemaVersion, generation, payload),
        });
        await _pending.writeAsString(encoded, flush: true);
        if (committed?.path == _primary.path) {
          // On our native iOS/Android targets rename replaces the old file.
          // There is always at least one complete committed generation.
          await _primary.rename(_previous.path);
        }
        await _pending.rename(_primary.path);
      } on FileSystemException catch (error) {
        throw SaveStoreException('自動保存に失敗しました。前回のセーブは保持されています。', error);
      }
    });
  }

  Future<_Snapshot?> _readCommitted() async {
    try {
      // Inspect both before selecting. A valid old backup must not allow an
      // older application to overwrite an unsupported newer primary (or vice
      // versa). A truncated/corrupt file, however, can fall back safely.
      final primary = await _read(_primary);
      final previous = await _read(_previous);
      final current = primary.snapshot;
      final backup = previous.snapshot;
      if (current != null &&
          (backup == null || current.generation >= backup.generation)) {
        return current;
      }
      if (backup != null) return backup;
      if (primary.exists || previous.exists) throw const CorruptSaveException();
      return null;
    } on FileSystemException catch (error) {
      // Access failures are not equivalent to no save or content corruption.
      throw SaveStoreException('セーブを読み込めませんでした。データは保持されています。', error);
    }
  }

  Future<_ReadResult> _read(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return const _ReadResult(exists: false);
    }
    if (type != FileSystemEntityType.file) {
      throw SaveStoreException('保存先に通常のファイル以外があります。データは変更していません。');
    }
    try {
      // Decode explicitly: readAsString wraps malformed UTF-8 in a
      // FileSystemException, which must remain reserved for access failures.
      final raw = utf8.decode(await file.readAsBytes());
      final envelope = jsonDecode(raw);
      if (envelope is! Map<String, dynamic>) {
        return const _ReadResult(exists: true);
      }
      final version = envelope['schemaVersion'];
      if (version is int && version != schemaVersion) {
        throw UnsupportedSaveVersionException(version);
      }
      final generation = envelope['generation'];
      final payload = envelope['payload'];
      if (version is! int ||
          version != schemaVersion ||
          generation is! int ||
          generation < 1 ||
          payload is! String ||
          envelope['checksum'] != _checksum(version, generation, payload)) {
        return const _ReadResult(exists: true);
      }
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic>) {
        return const _ReadResult(exists: true);
      }
      return _ReadResult(
        exists: true,
        snapshot: _Snapshot(file.path, generation, data),
      );
    } on FormatException {
      return const _ReadResult(exists: true);
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final key = _primary.absolute.path;
    final previous = _operations[key] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    // A failed operation must reach its caller without poisoning later writes.
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _operations[key] = tail;
    tail.then((_) {
      if (identical(_operations[key], tail)) _operations.remove(key);
    });
    return result;
  }

  static String _checksum(int version, int generation, String payload) =>
      sha256.convert(utf8.encode('$version:$generation:$payload')).toString();
}

class _ReadResult {
  const _ReadResult({required this.exists, this.snapshot});

  final bool exists;
  final _Snapshot? snapshot;
}

class _Snapshot {
  const _Snapshot(this.path, this.generation, this.data);

  final String path;
  final int generation;
  final Map<String, dynamic> data;
}
