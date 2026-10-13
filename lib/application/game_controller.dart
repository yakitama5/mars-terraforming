import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/game_engine.dart';
import '../domain/game_state.dart';
import '../domain/save_repository.dart';

/// Owns the clock and commits entire snapshots. Rendering never advances time.
class GameController extends ChangeNotifier {
  GameController(
    this.repository, {
    this.devTools = false,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final SaveRepository repository;
  final bool devTools;
  final DateTime Function() now;
  GameEngine? engine;
  GameState get state => engine!.state;
  String? error;
  String notice = '端末内に自動保存します';
  bool busy = false;
  bool _disposed = false;
  bool _saveConflict = false;
  Timer? _timer;
  int _ticks = 0;
  Future<void> _saving = Future.value();

  Future<void> initialize({bool startTimer = true}) async {
    if (_disposed || _saveConflict) return;
    try {
      final loaded = await repository.load();
      if (_disposed) return;
      final initial = loaded.data == null
          ? GameState.initial(now())
          : GameState.fromJson(loaded.data!);
      // Keep the playable world private until its first complete save succeeds.
      // A failed initial save must never start an unsaved game or its timer.
      final candidate = GameEngine(initial)..advanceTo(now());
      await repository.save(candidate.state.toJson());
      if (_disposed) return;
      engine = candidate;
      error = null;
      if (loaded.recovered) notice = '直前の正常な保存から回復しました';
      if (startTimer && !_disposed) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (busy || engine == null) return;
          engine!.advanceTo(now());
          _emit();
          if (++_ticks % 5 == 0) unawaited(save());
        });
      }
    } catch (exception) {
      _saveConflict = exception is SaveConflictException;
      engine = null;
      _timer?.cancel();
      error = '進行状態を安全に読み込み・保存できませんでした。開始せずに停止しています。\n$exception';
    }
    _emit();
  }

  Future<void> command(String? Function(GameEngine) action) async {
    if (engine == null || busy) return;
    busy = true;
    try {
      engine!.advanceTo(now());
      final message = action(engine!);
      if (message != null) notice = message;
      await save();
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> advanceForDevelopment() async {
    if (!devTools) return;
    await command((game) {
      game.advanceBy(const Duration(minutes: 5));
      return '開発用セーブだけを5分進めました';
    });
  }

  Future<void> resume() async {
    if (engine == null || busy) return;
    engine!.advanceTo(now());
    await save();
    _emit();
  }

  Future<void> save() {
    if (engine == null || _saveConflict) return Future.value();
    // Capture before asynchronous IO so state and its clock always agree.
    final snapshot = state.toJson();
    _saving = _saving.then((_) async {
      // A conflict also invalidates snapshots already queued behind this save.
      if (_saveConflict) return;
      try {
        await repository.save(snapshot);
        error = null;
      } on SaveConflictException catch (exception) {
        _saveConflict = true;
        _timer?.cancel();
        engine = null;
        error = '保存内容の競合を検出したため、進行を停止しました。\n$exception';
      } catch (exception) {
        error = '自動保存に失敗しました。空き容量を確認してください。\n$exception';
      }
      _emit();
    });
    return _saving;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
