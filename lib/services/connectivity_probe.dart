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

  static Future<bool> _dnsCheck() async {
    for (final host in const ['www.youtube.com', 'www.google.com']) {
      try {
        final r = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 3));
        if (r.isNotEmpty && r.first.rawAddress.isNotEmpty) return true;
      } catch (_) {}
    }
    return false;
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
