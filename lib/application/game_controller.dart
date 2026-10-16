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
  String? get commandNotice => _commandNotice;
  bool busy = false;
  bool finishingOpening = false;
  bool _disposed = false;
  bool _saveConflict = false;
  Timer? _timer;
  Timer? _commandNoticeTimer;
  String? _commandNotice;
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
      final candidate = GameEngine(initial);
      if (initial.openingStarted && !initial.openingSeen) {
        initial.lastWallClockMs = now().millisecondsSinceEpoch;
      } else {
        candidate.advanceTo(now());
      }
      await repository.save(candidate.state.toJson());
      if (_disposed) return;
      engine = candidate;
      error = null;
      if (loaded.recovered) notice = '直前の正常な保存から回復しました';
      if (startTimer && !_disposed) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (busy || engine == null) return;
          _advanceClock();
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
    if (_disposed || engine == null || busy) return;
    busy = true;
    try {
      _advanceClock();
      final message = action(engine!);
      if (message != null) {
        notice = message;
        _showCommandNotice(message);
      }
      await save();
    } finally {
      busy = false;
      _emit();
    }
  }

  /// Initial story reading is outside the economy; replaying a story is not.
  /// Persist the started flag so a closed app cannot spend its opening budget.
  void beginOpening() {
    if (engine == null || state.openingSeen || state.openingStarted) return;
    state.openingStarted = true;
    state.lastWallClockMs = now().millisecondsSinceEpoch;
    unawaited(save());
  }

  void _advanceClock() {
    if (state.openingStarted && !state.openingSeen) {
      state.lastWallClockMs = now().millisecondsSinceEpoch;
    } else {
      engine!.advanceTo(now());
    }
  }

  Future<bool> updateMissionIdentity({
    required Map<String, String> cities,
    required String rocket,
    bool finishOpening = false,
  }) async {
    if (_disposed || engine == null || busy) return false;
    final wasSeen = state.openingSeen;
    finishingOpening = finishOpening && !wasSeen;
    var accepted = false;
    await command((game) {
      try {
        final identity = game.state.identity.renamed(
          cities: cities,
          rocket: rocket,
        );
        game.state.identity = identity;
        accepted = true;
        if (finishOpening) game.state.openingSeen = true;
        return finishOpening ? null : '名前を保存しました';
      } on FormatException {
        return '名前を確認してください。1〜24文字で設定できます。';
      }
    });
    if (finishOpening && !wasSeen && engine != null && error != null) {
      // Keep the naming screen open until the whole snapshot is durable.
      state.openingSeen = false;
      _emit();
    }
    finishingOpening = false;
    _emit();
    return accepted && engine != null && error == null;
  }

  Future<void> skipOpening() async {
    if (_disposed || engine == null || busy) return;
    final wasSeen = state.openingSeen;
    finishingOpening = !wasSeen;
    await command((game) {
      game.state.openingSeen = true;
      return null;
    });
    if (!wasSeen && engine != null && error != null) {
      state.openingSeen = false;
    }
    finishingOpening = false;
    _emit();
  }

  void _showCommandNotice(String message) {
    _commandNoticeTimer?.cancel();
    _commandNotice = message;
    _commandNoticeTimer = Timer(const Duration(seconds: 8), () {
      _commandNoticeTimer = null;
      _commandNotice = null;
      _emit();
    });
    // Report rejected actions even while their unchanged snapshot is saving.
    _emit();
  }

  Future<void> advanceForDevelopment({
    Duration duration = const Duration(minutes: 5),
  }) async {
    if (!devTools || duration <= Duration.zero) return;
    await command((game) {
      game.advanceBy(duration);
      final label = duration.inDays > 0 && duration.inHours % 24 == 0
          ? '${duration.inDays}日'
          : duration.inHours > 0 && duration.inMinutes % 60 == 0
          ? '${duration.inHours}時間'
          : '${duration.inMinutes}分';
      return '開発用セーブだけを$label進めました';
    });
  }

  Future<void> resume() async {
    if (engine == null || busy) return;
    _advanceClock();
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
    _commandNoticeTimer?.cancel();
    _commandNoticeTimer = null;
    super.dispose();
  }
}
