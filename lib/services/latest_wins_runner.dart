import 'dart:async';

/// Handed to every run so the work can notice it has been superseded.
class RunContext {
  final bool Function() _isCurrent;

  /// Completes the moment a newer request is submitted (or [LatestWinsRunner.cancel]
  /// is called). Race slow awaits against this so an obsolete run ends quickly.
  final Future<void> superseded;

  RunContext(this._isCurrent, this.superseded);

  /// True while no newer request has replaced this one.
  bool get isCurrent => _isCurrent();
}

/// Runs requests strictly one at a time, and when several arrive while one is
/// running only the newest is kept ("latest wins").
///
/// This is what makes rapid song changes safe: the platform audio player never
/// sees two overlapping stop/setAudioSource calls, and 50 skips in a second
/// collapse into one load of the final song.
class LatestWinsRunner<T> {
  final Future<void> Function(T request, RunContext ctx) _run;

  T? _pending;
  bool _hasPending = false;
  bool _running = false;
  int _gen = 0;
  Completer<void> _superseded = Completer<void>();
  Completer<void>? _idle;

  LatestWinsRunner(this._run);

  /// True while a request is running or queued.
  bool get isBusy => _running || _hasPending;

  /// Completes when nothing is running or queued.
  Future<void> get idle => isBusy ? (_idle ??= Completer<void>()).future : Future.value();

  /// Replaces any queued request and signals the running one to give up.
  void submit(T request) {
    _signalSuperseded();
    _pending = request;
    _hasPending = true;
    if (!_running) unawaited(_drain());
  }

  /// Drops the queued request and signals the running one to give up.
  void cancel() {
    _signalSuperseded();
    _pending = null;
    _hasPending = false;
  }

  void _signalSuperseded() {
    _gen++;
    if (!_superseded.isCompleted) _superseded.complete();
    _superseded = Completer<void>();
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_hasPending) {
        final request = _pending as T;
        _pending = null;
        _hasPending = false;
        final gen = _gen;
        final ctx = RunContext(() => gen == _gen, _superseded.future);
        try {
          await _run(request, ctx);
        } catch (_) {
          // A failing run must never kill the queue. The callback is
          // responsible for reporting its own errors.
        }
      }
    } finally {
      _running = false;
      final idle = _idle;
      _idle = null;
      if (idle != null && !idle.isCompleted) idle.complete();
    }
  }
}
