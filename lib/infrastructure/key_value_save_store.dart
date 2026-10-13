import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/save_repository.dart';

class BrowserSaveStoreException implements Exception {
  const BrowserSaveStoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class BrowserSaveConflictException extends SaveConflictException {
  const BrowserSaveConflictException()
    : super(
        'この保存枠は別のタブで使用中か、外部で変更されました。ほかのタブを閉じて、この画面を再読み込みしてください。保存は上書きしていません。',
      );
}

class UnsupportedBrowserSaveVersionException extends BrowserSaveStoreException {
  UnsupportedBrowserSaveVersionException(this.version)
    : super('このセーブ形式（$version）は、このアプリでは読み込めません。データは保持されています。');

  final int version;
}

class CorruptBrowserSaveException extends BrowserSaveStoreException {
  const CorruptBrowserSaveException()
    : super('正常なセーブが見つかりませんでした。既存のデータを上書きせずに停止しました。');
}

/// Portable persistence logic for one atomic string-valued storage entry.
///
/// The browser adapter owns an exclusive Web Lock for the lifetime of the page.
/// Both checksummed generations are replaced in ONE localStorage.setItem call;
/// an unsuccessful write leaves the entire previous bundle intact. Never split
/// the world, processed time, ledger, or generations across separate writes.
///
/// Comparison with the last loaded/written string additionally detects edits
/// outside this repository. It is a guard, NOT a cross-tab mutex: the adapter
/// must retain its Web Lock while using this store.
class KeyValueSaveStore implements SaveRepository {
  KeyValueSaveStore({
    required this.read,
    required this.write,
    this.slot = 'normal',
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(slot)) {
      throw ArgumentError.value(slot, 'slot', '英数字・ハイフン・アンダースコアのみ');
    }
  }

  static const formatVersion = 1;
  static const schemaVersion = 1;

  final String slot;
  final String? Function(String key) read;
  final void Function(String key, String value) write;
  bool _hasObserved = false;
  String? _observedRaw;

  String get storageKey => 'mars_terraforming.save.$slot';

  @override
  Future<SaveLoadResult> load() async {
    final raw = _readRaw();
    final committed = _decodeBundle(raw);
    _observedRaw = raw;
    _hasObserved = true;
    return SaveLoadResult(
      data: committed?.data,
      recovered: committed != null && !committed.isPrimary,
      generation: committed?.generation ?? 0,
    );
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    // This method does not yield: capture, comparison and commit are all
    // synchronous inside the browser adapter's session lock.
    final payload = jsonEncode(snapshot);
    final raw = _readRaw();
    if (_hasObserved && raw != _observedRaw) {
      throw const BrowserSaveConflictException();
    }
    final committed = _decodeBundle(raw);
    final generation = (committed?.generation ?? 0) + 1;
    final envelope = jsonEncode({
      'schemaVersion': schemaVersion,
      'generation': generation,
      'payload': payload,
      'checksum': _checksum(schemaVersion, generation, payload),
    });
    final bundle = jsonEncode({
      'formatVersion': formatVersion,
      'primary': envelope,
      // Preserve the last known-good generation, even when primary was corrupt.
      'previous': committed?.raw,
    });
    try {
      write(storageKey, bundle);
    } catch (error) {
      throw BrowserSaveStoreException(
        'ブラウザへの自動保存に失敗しました。空き容量とサイトデータの保存許可を確認してください。前回のセーブは保持されています。',
        error,
      );
    }
    _observedRaw = bundle;
    _hasObserved = true;
  }

  String? _readRaw() {
    try {
      return read(storageKey);
    } catch (error) {
      throw BrowserSaveStoreException(
        'ブラウザの保存データを読み込めません。サイトデータの保存許可を確認してください。',
        error,
      );
    }
  }

  _Snapshot? _decodeBundle(String? raw) {
    if (raw == null) return null;
    try {
      final bundle = jsonDecode(raw);
      if (bundle is! Map<String, dynamic>) {
        throw const CorruptBrowserSaveException();
      }
      final version = bundle['formatVersion'];
      if (version is int && version != formatVersion) {
        throw UnsupportedBrowserSaveVersionException(version);
      }
      if (version is! int || version != formatVersion) {
        throw const CorruptBrowserSaveException();
      }
      // Inspect both first. An unsupported primary OR previous generation must
      // block an older app from overwriting a newer app's committed data.
      final primary = _decodeEnvelope(bundle['primary'], isPrimary: true);
      final previous = _decodeEnvelope(bundle['previous'], isPrimary: false);
      if (primary != null &&
          (previous == null || primary.generation >= previous.generation)) {
        return primary;
      }
      if (previous != null) return previous;
      throw const CorruptBrowserSaveException();
    } on FormatException {
      throw const CorruptBrowserSaveException();
    }
  }

  _Snapshot? _decodeEnvelope(Object? raw, {required bool isPrimary}) {
    if (raw is! String) return null;
    try {
      final envelope = jsonDecode(raw);
      if (envelope is! Map<String, dynamic>) return null;
      final version = envelope['schemaVersion'];
      if (version is int && version != schemaVersion) {
        throw UnsupportedBrowserSaveVersionException(version);
      }
      final generation = envelope['generation'];
      final payload = envelope['payload'];
      if (version is! int ||
          version != schemaVersion ||
          generation is! int ||
          generation < 1 ||
          payload is! String ||
          envelope['checksum'] != _checksum(version, generation, payload)) {
        return null;
      }
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic>) return null;
      return _Snapshot(raw, generation, data, isPrimary: isPrimary);
    } on FormatException {
      return null;
    }
  }

  static String _checksum(int version, int generation, String payload) =>
      sha256.convert(utf8.encode('$version:$generation:$payload')).toString();
}

class _Snapshot {
  const _Snapshot(
    this.raw,
    this.generation,
    this.data, {
    required this.isPrimary,
  });

  final String raw;
  final int generation;
  final Map<String, dynamic> data;
  final bool isPrimary;
}
