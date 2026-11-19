import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_log.dart';
import '../services/connectivity_probe.dart';
import '../services/audio_handler.dart';

/// Whether Noor can reach the internet well enough to search and stream.
enum Connection { online, offline }

/// Watches the connection.
///
/// * checks once at start, then every [onlineEvery] while online and every
///   [offlineEvery] while offline, so it notices quickly when it is back;
/// * anything that just failed for network reasons (a search timing out,
///   playback finding no connection) calls [reportFailure]: the app shows
///   "offline" at once and checks again;
/// * anything that just worked over the network calls [reportSuccess].
///
/// "Weak" internet that cannot load a song or a search counts as offline:
/// the user gets the saved-songs experience instead of endless waiting.
class ConnectionNotifier extends StateNotifier<Connection> {
  ConnectionNotifier({
    Future<bool> Function()? check,
    this.onlineEvery = const Duration(seconds: 45),
    this.offlineEvery = const Duration(seconds: 5),
    bool start = true,
  })  : _check = check ?? ConnectivityProbe().isOnline,
        _auto = start,
        super(Connection.online) {
    if (start) unawaited(recheck());
  }

  /// Whether checks repeat on their own (off in widget tests, which drive
  /// the connection themselves and must not touch the real network).
  final bool _auto;

  final Future<bool> Function() _check;
  final Duration onlineEvery;
  final Duration offlineEvery;
  Timer? _timer;
  bool _checking = false;

  bool get isOffline => state == Connection.offline;

  void _set(Connection c) {
    if (!mounted) return;
    if (state != c) nlog('[N] connection: ${c.name}');
    state = c;
    _timer?.cancel();
    if (!_auto) return;
    _timer = Timer(c == Connection.online ? onlineEvery : offlineEvery,
        () => unawaited(recheck()));
  }

  /// Checks the internet now.
  Future<void> recheck() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final ok = await _check();
      _set(ok ? Connection.online : Connection.offline);
    } catch (_) {
      _set(Connection.offline);
    } finally {
      _checking = false;
    }
  }

  void reportFailure() {
    _set(Connection.offline);
  }

  void reportSuccess() => _set(Connection.online);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, Connection>((ref) {
  // Under `flutter test` nothing is checked automatically.
  final n = ConnectionNotifier(
      start: !Platform.environment.containsKey('FLUTTER_TEST'));
  // Playback's own view of the network.
  try {
    final sub = ref
        .read(audioHandlerProvider)
        .offlineChanges
        .listen((offline) => offline ? n.reportFailure() : n.reportSuccess());
    ref.onDispose(sub.cancel);
  } catch (_) {/* no audio handler (tests) */}
  return n;
});
