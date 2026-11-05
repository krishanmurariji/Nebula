import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

/// Downloads a stream once into memory while any number of readers consume it
/// as it arrives. One network download therefore feeds both the player and the
/// disk cache (previously the song was streamed AND downloaded separately).
///
/// Songs are small (a few MB), so holding one in memory is fine.
class ProgressiveDownload {
  ProgressiveDownload({
    required Stream<List<int>> Function() open,
    required this.totalBytes,
  }) : _open = open {
    // Callers that never look at [completed] must not trigger
    // "unhandled async error" when a download fails or is cancelled.
    _completer.future.ignore();
  }

  final Stream<List<int>> Function() _open;
  final int totalBytes;

  final List<Uint8List> _chunks = [];
  final List<int> _starts = []; // _starts[i] = byte offset of _chunks[i]
  int _received = 0;

  StreamSubscription<List<int>>? _sub;
  bool _started = false;
  bool _done = false;
  bool _cancelled = false;
  Object? _error;
  StackTrace? _stack;

  final Completer<Uint8List> _completer = Completer<Uint8List>();
  Completer<void> _signal = Completer<void>();

  int get receivedBytes => _received;
  bool get isComplete => _done;
  bool get isCancelled => _cancelled;
  bool get isFailed => _error != null;

  /// Completes with all bytes, or with an error if the download failed or was
  /// cancelled.
  Future<Uint8List> get completed => _completer.future;

  /// Starts downloading (idempotent).
  void start() {
    if (_started) return;
    _started = true;
    try {
      _sub = _open().listen(
        _onData,
        onError: (Object e, StackTrace st) => _fail(e, st),
        onDone: _onDone,
        cancelOnError: true,
      );
    } catch (e, st) {
      _fail(e, st);
    }
  }

  void _onData(List<int> data) {
    if (_cancelled || _done) return;
    final chunk = data is Uint8List ? data : Uint8List.fromList(data);
    _starts.add(_received);
    _chunks.add(chunk);
    _received += chunk.length;
    _wake();
  }

  void _onDone() {
    if (_cancelled || _error != null) return;
    if (_received != totalBytes) {
      _fail(StateError('incomplete download: $_received of $totalBytes bytes'),
          StackTrace.current);
      return;
    }
    _done = true;
    final out = Uint8List(_received);
    for (var i = 0; i < _chunks.length; i++) {
      out.setRange(_starts[i], _starts[i] + _chunks[i].length, _chunks[i]);
    }
    if (!_completer.isCompleted) _completer.complete(out);
    _wake();
  }

  void _fail(Object e, StackTrace st) {
    if (_error != null || _done) return;
    _error = e;
    _stack = st;
    if (!_completer.isCompleted) _completer.completeError(e, st);
    _wake();
  }

  /// Stops the network transfer immediately and wakes any waiting readers.
  void cancel() {
    if (_done || _cancelled) return;
    _cancelled = true;
    _sub?.cancel();
    _sub = null;
    if (!_completer.isCompleted) {
      _completer.completeError(StateError('download cancelled'));
    }
    _wake();
  }

  void _wake() {
    final s = _signal;
    _signal = Completer<void>();
    if (!s.isCompleted) s.complete();
  }

  Uint8List _slice(int from, int to) {
    // Find the chunk containing [from].
    var lo = 0, hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= from) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final out = Uint8List(to - from);
    var written = 0;
    for (var i = lo; i < _chunks.length && written < out.length; i++) {
      final chunk = _chunks[i];
      final chunkStart = _starts[i];
      final begin = max(from, chunkStart) - chunkStart;
      final end = min(to, chunkStart + chunk.length) - chunkStart;
      if (end <= begin) continue;
      out.setRange(written, written + (end - begin), chunk, begin);
      written += end - begin;
    }
    return out;
  }

  /// Streams bytes `[from, to)`, waiting for the download whenever the
  /// requested bytes have not arrived yet. Safe for seeking: any range can be
  /// read at any time.
  Stream<List<int>> read(int from, [int? to]) async* {
    start();
    final stop = min(to ?? totalBytes, totalBytes);
    var pos = from;
    while (pos < stop) {
      final error = _error;
      if (error != null) Error.throwWithStackTrace(error, _stack!);
      if (_cancelled) throw StateError('download cancelled');

      if (pos < _received) {
        final upTo = min(stop, _received);
        yield _slice(pos, upTo);
        pos = upTo;
      } else if (_done) {
        break; // asked past the end
      } else {
        await _signal.future;
      }
    }
  }
}
