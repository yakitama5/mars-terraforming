import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../domain/save_repository.dart';
import 'key_value_save_store.dart';

/// Browser-local save slot. Import only through dart.library.js_interop.
///
/// An exclusive, non-waiting Web Lock is acquired before loading and retained
/// while this page exists. A second tab stops BEFORE loading or advancing the
/// same world. Closing/reloading the owning page releases the lock in the
/// browser, including after a crash. No clock-based lock lease is used.
///
/// Web Locks requires HTTPS or localhost. Saves belong to this browser profile
/// and origin; clearing site data, private browsing, or a different origin can
/// remove/hide them. This is not a cloud backup or a native-app save transfer.
class BrowserSaveStore implements SaveRepository {
  BrowserSaveStore({String slot = 'normal'})
    : _store = KeyValueSaveStore(
        read: (key) => web.window.localStorage.getItem(key),
        write: (key, value) => web.window.localStorage.setItem(key, value),
        slot: slot,
      );

  final KeyValueSaveStore _store;
  final Completer<JSAny?> _lifetime = Completer<JSAny?>();
  Future<void>? _lockReady;
  Object? _lockFailure;

  @override
  Future<SaveLoadResult> load() async {
    await _ensureLock();
    return _store.load();
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    // Capture before the asynchronous lock boundary, including nested lists.
    final payload = jsonEncode(snapshot);
    await _ensureLock();
    return _store.save(jsonDecode(payload) as Map<String, dynamic>);
  }

  Future<void> _ensureLock() async {
    await (_lockReady ??= _acquireLock());
    if (_lockFailure != null) throw _lockFailure!;
  }

  Future<void> _acquireLock() {
    final acquired = Completer<void>();
    try {
      if (!web.window.isSecureContext ||
          web.window.navigator.locks.isUndefinedOrNull) {
        throw const BrowserSaveStoreException(
          'このブラウザでは安全な保存のためのWeb Locksを利用できません。HTTPSまたはlocalhostで、最新のブラウザを使って開いてください。',
        );
      }
      final request = web.window.navigator.locks.request(
        '${_store.storageKey}.session',
        web.LockOptions(mode: 'exclusive', ifAvailable: true),
        ((web.Lock? lock) {
          if (lock == null) {
            acquired.completeError(const BrowserSaveConflictException());
            return Future<JSAny?>.value(null).toJS;
          }
          acquired.complete();
          return _lifetime.future.toJS;
        }).toJS,
      );
      unawaited(
        request.toDart.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            final failure = BrowserSaveStoreException(
              'ブラウザの保存枠を安全に確保できませんでした。サイトデータの保存許可を確認して再読み込みしてください。',
              error,
            );
            _lockFailure = failure;
            if (!acquired.isCompleted) {
              acquired.completeError(failure, stackTrace);
            }
          },
        ),
      );
    } catch (error, stackTrace) {
      if (!acquired.isCompleted) {
        acquired.completeError(error, stackTrace);
      }
    }
    return acquired.future;
  }
}
