import 'dart:async';
import 'dart:io';

/// Dependency-free "is the internet reachable?" check, used only on the failure
/// path to decide between "this song is broken, skip it" and "we are offline,
/// wait and resume".
class ConnectivityProbe {
  ConnectivityProbe({
    Future<bool> Function()? check,
    this.pollInterval = const Duration(seconds: 3),
    Future<void> Function(Duration)? delay,
  })  : _check = check ?? _dnsCheck,
        _delay = delay ?? Future.delayed;

  final Future<bool> Function() _check;
  final Duration pollInterval;
  final Future<void> Function(Duration) _delay;

  /// Online if ANY of several hosts resolves, asked in parallel with a
  /// generous timeout. Slow or flaky DNS on one host (or YouTube answering
  /// slowly) must never be mistaken for "no internet".
  static Future<bool> _dnsCheck() async {
    const hosts = ['www.google.com', 'www.youtube.com', 'one.one.one.one'];
    final done = Completer<bool>();
    var pending = hosts.length;
    for (final host in hosts) {
      InternetAddress.lookup(host).timeout(const Duration(seconds: 6)).then((r) {
        if (r.isNotEmpty && !done.isCompleted) done.complete(true);
      }).catchError((Object _) {}).whenComplete(() {
        if (--pending == 0 && !done.isCompleted) done.complete(false);
      });
    }
    return done.future;
  }

  Future<bool> isOnline() async {
    try {
      return await _check();
    } catch (_) {
      return false;
    }
  }

  /// Completes true once the network is back, or false as soon as
  /// [isCancelled] reports true (the user moved on).
  Future<bool> waitUntilOnline({required bool Function() isCancelled}) async {
    while (!isCancelled()) {
      if (await isOnline()) return !isCancelled();
      await _delay(pollInterval);
    }
    return false;
  }
}
