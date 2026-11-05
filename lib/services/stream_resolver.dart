import 'dart:async';
import 'dart:math';

import 'playback_failure.dart';

/// Result of resolving a video id into something playable.
class ResolveResult<T> {
  final T? value;

  /// Why [value] is null (meaningless when [value] is set).
  final FailureKind kind;

  const ResolveResult(this.value, this.kind);
  const ResolveResult.ok(T this.value) : kind = FailureKind.transient;
  const ResolveResult.failed(this.kind) : value = null;
}

/// Fetches one stream description for [videoId] using client number
/// [clientIndex]. Return null when that client found no usable audio stream.
/// Throw on failure (rate limits are recognised by [classifyPlaybackError]).
typedef StreamFetcher<T> = Future<T?> Function(String videoId, int clientIndex);

class _Breaker {
  int rateLimitFails = 0;
  int hardFails = 0;
  DateTime? openUntil;
}

class _InFlight<T> {
  late final Future<ResolveResult<T>> future;
  int waiters = 0;
  bool abandoned = false;
  bool done = false;
}

/// Turns a video id into a playable stream description, robustly:
///
///  * **De-duplication** – concurrent requests for the same video (user tap +
///    prefetch) share one network fetch.
///  * **Client fallback** – tries each client in order until one works.
///  * **Circuit breaker per client** – a client that is rate limited backs off
///    exponentially; one that fails repeatedly is skipped for a short while.
///  * **Abandonment** – when every caller has given up (user skipped) the
///    shared fetch stops instead of burning requests nobody wants.
///  * **TTL cache** – a resolved stream is reused until it is probably stale.
class StreamResolver<T> {
  StreamResolver({
    required this.fetch,
    required this.timeouts,
    this.ttl = const Duration(minutes: 30),
    this.hardFailThreshold = 3,
    this.hardFailCooldown = const Duration(seconds: 15),
    this.maxInlineWait = const Duration(seconds: 30),
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  })  : _now = now ?? DateTime.now,
        _delay = delay ?? Future.delayed,
        _breakers = List.generate(timeouts.length, (_) => _Breaker());

  final StreamFetcher<T> fetch;

  /// One entry per client, in priority order.
  final List<Duration> timeouts;
  final Duration ttl;
  final int hardFailThreshold;
  final Duration hardFailCooldown;

  /// If every client is cooling down for no longer than this, wait for it
  /// instead of failing right away.
  final Duration maxInlineWait;

  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final List<_Breaker> _breakers;
  final Map<String, ({T value, DateTime at})> _cache = {};
  final Map<String, _InFlight<T>> _inFlight = {};

  int get clientCount => timeouts.length;

  /// A fresh cached value, without touching the network.
  T? peek(String videoId) {
    final e = _cache[videoId];
    if (e == null) return null;
    if (_now().difference(e.at) > ttl) {
      _cache.remove(videoId);
      return null;
    }
    return e.value;
  }

  /// Forget a value that turned out to be bad (expired URL, 403, …).
  void invalidate(String videoId) => _cache.remove(videoId);

  void clear() => _cache.clear();

  bool _isOpen(int i) {
    final until = _breakers[i].openUntil;
    return until != null && _now().isBefore(until);
  }

  /// Seconds until at least one client is usable again; 0 if one is usable now.
  int get globalCooldownSeconds {
    Duration? shortest;
    for (var i = 0; i < clientCount; i++) {
      if (!_isOpen(i)) return 0;
      final left = _breakers[i].openUntil!.difference(_now());
      if (shortest == null || left < shortest) shortest = left;
    }
    return shortest == null ? 0 : max(0, shortest.inSeconds);
  }

  void _onRateLimited(int i) {
    final b = _breakers[i];
    b.rateLimitFails++;
    final secs = min(4 * pow(2, b.rateLimitFails - 1).toInt(), 60);
    b.openUntil = _now().add(Duration(seconds: secs));
  }

  void _onHardFail(int i) {
    final b = _breakers[i];
    b.hardFails++;
    if (b.hardFails >= hardFailThreshold) {
      b.openUntil = _now().add(hardFailCooldown);
      b.hardFails = 0;
    }
  }

  void _onSuccess(int i) {
    final b = _breakers[i];
    b.rateLimitFails = 0;
    b.hardFails = 0;
    b.openUntil = null;
  }

  /// Resolves [videoId]. Pass [superseded] (completes when the caller no
  /// longer cares) so a slow fetch never delays whatever the user does next.
  Future<ResolveResult<T>> resolve(String videoId,
      {Future<void>? superseded}) async {
    final cached = peek(videoId);
    if (cached != null) return ResolveResult.ok(cached);

    var flight = _inFlight[videoId];
    if (flight == null || flight.abandoned) {
      flight = _InFlight<T>();
      final created = flight;
      created.future = _run(videoId, created).whenComplete(() {
        created.done = true;
        if (identical(_inFlight[videoId], created)) _inFlight.remove(videoId);
      });
      _inFlight[videoId] = created;
    }

    flight.waiters++;
    try {
      if (superseded == null) return await flight.future;
      return await Future.any<ResolveResult<T>>([
        flight.future,
        superseded.then((_) => const ResolveResult.failed(FailureKind.cancelled)),
      ]);
    } finally {
      flight.waiters--;
      if (flight.waiters == 0 && !flight.done) flight.abandoned = true;
    }
  }

  Future<ResolveResult<T>> _run(String videoId, _InFlight<T> flight) async {
    const cancelled = ResolveResult<Never>.failed(FailureKind.cancelled);
    var sawPermanent = false;

    for (var pass = 0; pass < 2; pass++) {
      for (var ci = 0; ci < clientCount; ci++) {
        if (flight.abandoned) return cancelled;
        if (_isOpen(ci)) continue;

        try {
          final value = await fetch(videoId, ci).timeout(timeouts[ci]);
          if (value == null) continue; // this client had nothing; try next
          _onSuccess(ci);
          _cache[videoId] = (value: value, at: _now());
          return ResolveResult.ok(value);
        } on TimeoutException {
          _onHardFail(ci);
        } catch (e) {
          switch (classifyPlaybackError(e)) {
            case FailureKind.rateLimited:
              _onRateLimited(ci);
            case FailureKind.permanent:
              sawPermanent = true;
            case FailureKind.cancelled:
            case FailureKind.transient:
              _onHardFail(ci);
          }
        }
      }

      // "Video unavailable" will not change by asking again.
      if (sawPermanent) return const ResolveResult.failed(FailureKind.permanent);

      if (pass == 0) {
        // If everything is cooling down briefly, wait it out and try once more.
        Duration? shortest;
        var anyUsable = false;
        for (var ci = 0; ci < clientCount; ci++) {
          if (!_isOpen(ci)) {
            anyUsable = true;
            break;
          }
          final left = _breakers[ci].openUntil!.difference(_now());
          if (shortest == null || left < shortest) shortest = left;
        }
        if (anyUsable) continue;
        if (shortest == null || shortest > maxInlineWait) break;
        for (var s = 0; s <= shortest.inSeconds; s++) {
          if (flight.abandoned) return cancelled;
          await _delay(const Duration(seconds: 1));
        }
      }
    }

    return ResolveResult.failed(globalCooldownSeconds > 0
        ? FailureKind.rateLimited
        : FailureKind.transient);
  }
}
