import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/playback_failure.dart';
import 'package:nebula_music_player/services/stream_resolver.dart';

class RequestLimitExceededException implements Exception {}

class VideoUnavailableException implements Exception {}

const _t = [Duration(seconds: 5), Duration(seconds: 5), Duration(seconds: 5)];

void main() {
  test('concurrent resolves of the same video share one fetch', () async {
    var calls = 0;
    final gate = Completer<void>();
    final r = StreamResolver<String>(
      timeouts: _t,
      fetch: (id, c) async {
        calls++;
        await gate.future;
        return 'url-$id';
      },
    );

    final a = r.resolve('v1');
    final b = r.resolve('v1');
    gate.complete();
    final results = await Future.wait([a, b]);

    expect(calls, 1);
    expect(results.map((e) => e.value), ['url-v1', 'url-v1']);
  });

  test('a fresh value is served from cache, an expired one is refetched', () async {
    var calls = 0;
    var now = DateTime(2026);
    final r = StreamResolver<String>(
      timeouts: _t,
      ttl: const Duration(minutes: 10),
      now: () => now,
      fetch: (id, c) async => 'u${++calls}',
    );

    expect((await r.resolve('v')).value, 'u1');
    expect((await r.resolve('v')).value, 'u1');
    now = now.add(const Duration(minutes: 11));
    expect((await r.resolve('v')).value, 'u2');
  });

  test('falls back to the next client when one fails', () async {
    final tried = <int>[];
    final r = StreamResolver<String>(
      timeouts: _t,
      fetch: (id, c) async {
        tried.add(c);
        if (c == 0) throw Exception('boom');
        return 'ok-from-$c';
      },
    );
    final res = await r.resolve('v');
    expect(res.value, 'ok-from-1');
    expect(tried, [0, 1]);
  });

  test('a client with nothing to offer (null) is skipped', () async {
    final r = StreamResolver<String>(
      timeouts: _t,
      fetch: (id, c) async => c == 0 ? null : 'c$c',
    );
    expect((await r.resolve('v')).value, 'c1');
  });

  group('rate limiting (whole-IP, not per client)', () {
    test('the first "rate limited" answer stops everything: other clients are NOT asked', () async {
      final tried = <int>[];
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        fetch: (id, c) async {
          tried.add(c);
          throw RequestLimitExceededException();
        },
      );
      final res = await r.resolve('v');
      expect(res.kind, FailureKind.rateLimited);
      expect(tried, [0], reason: 'hammering other clients only makes the limit worse');
      expect(r.globalCooldownSeconds, inInclusiveRange(1, 20));
    });

    test('during the pause no request is made at all', () async {
      var calls = 0;
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        fetch: (id, c) async {
          calls++;
          throw RequestLimitExceededException();
        },
      );
      await r.resolve('a');
      calls = 0;
      for (var i = 0; i < 10; i++) {
        expect((await r.resolve('b$i')).kind, FailureKind.rateLimited);
      }
      expect(calls, 0);
    });

    test('a cached stream is still served during the pause', () async {
      var limited = false;
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        fetch: (id, c) async {
          if (limited) throw RequestLimitExceededException();
          return 'cached-$id';
        },
      );
      expect((await r.resolve('x')).value, 'cached-x');
      limited = true;
      await r.resolve('other'); // triggers the pause
      expect((await r.resolve('x')).value, 'cached-x');
    });

    test('the pause grows with consecutive limits (20s, 40s, 80s …) and a success resets it', () async {
      var now = DateTime(2026);
      var limited = true;
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        now: () => now,
        fetch: (id, c) async {
          if (limited) throw RequestLimitExceededException();
          return 'ok';
        },
      );
      await r.resolve('a');
      expect(r.globalCooldownSeconds, 20);
      now = now.add(const Duration(seconds: 21));
      await r.resolve('a');
      expect(r.globalCooldownSeconds, 40);
      now = now.add(const Duration(seconds: 41));
      await r.resolve('a');
      expect(r.globalCooldownSeconds, 80);

      now = now.add(const Duration(seconds: 81));
      limited = false;
      expect((await r.resolve('a')).value, 'ok');
      expect(r.globalCooldownSeconds, 0);
      limited = true;
      await r.resolve('b');
      expect(r.globalCooldownSeconds, 20, reason: 'streak was reset by the success');
    });

    test('the pause never exceeds 10 minutes', () async {
      var now = DateTime(2026);
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        now: () => now,
        fetch: (id, c) async => throw RequestLimitExceededException(),
      );
      for (var i = 0; i < 12; i++) {
        await r.resolve('a');
        now = now.add(const Duration(minutes: 11));
      }
      await r.resolve('a');
      expect(r.globalCooldownSeconds, lessThanOrEqualTo(600));
    });
  });

  test('attempts are spaced by minGap so failures never become a burst', () async {
    final gaps = <Duration>[];
    final r = StreamResolver<String>(
      timeouts: _t,
      minGap: const Duration(milliseconds: 400),
      delay: (d) async => gaps.add(d),
      fetch: (id, c) async => throw Exception('boom'),
    );
    await r.resolve('v');
    expect(gaps, [const Duration(milliseconds: 400), const Duration(milliseconds: 400)]);
  });

  group('remembers the client that worked', () {
    test('the last good client is asked first next time', () async {
      final tried = <int>[];
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        fetch: (id, c) async {
          tried.add(c);
          if (c == 0) throw Exception('refused');
          return 'ok-$c';
        },
      );
      await r.resolve('a');
      expect(tried, [0, 1], reason: 'first time: in order, 0 fails, 1 works');
      tried.clear();
      await r.resolve('b');
      expect(tried, [1], reason: 'client 1 is asked first now and succeeds');
    });

    test('if the remembered client stops working the others are tried again', () async {
      final tried = <int>[];
      var oneWorks = true;
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        fetch: (id, c) async {
          tried.add(c);
          if (c == 1 && !oneWorks) throw Exception('now refused');
          if (c == 0) throw Exception('refused');
          return 'ok-$c';
        },
      );
      await r.resolve('a'); // 1 becomes the good one
      oneWorks = false;
      tried.clear();
      final res = await r.resolve('b');
      expect(res.value, 'ok-2');
      expect(tried, [1, 0, 2], reason: 'remembered first, then the rest in order');
      tried.clear();
      await r.resolve('c');
      expect(tried, [2], reason: '2 is the new favourite');
    });

    test('a client penalized for undownloadable streams is forgotten as the favourite', () async {
      final tried = <int>[];
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        fetch: (id, c) async {
          tried.add(c);
          return 'ok-$c';
        },
      );
      await r.resolve('a'); // 0 is good
      r.invalidate('a');
      r.penalize(0, const Duration(minutes: 5));
      tried.clear();
      await r.resolve('a');
      expect(tried, [1], reason: 'penalized client 0 is skipped, 1 takes over');
    });
  });

  test('unavailable video is reported as permanent', () async {
    var calls = 0;
    final r = StreamResolver<String>(
      timeouts: _t,
      fetch: (id, c) async {
        calls++;
        throw VideoUnavailableException();
      },
    );
    final res = await r.resolve('v');
    expect(res.kind, FailureKind.permanent);
    expect(calls, 3, reason: 'each client once, then stop');
  });

  test('a client that keeps failing is skipped for a while', () async {
    final tried = <int>[];
    final r = StreamResolver<String>(
      timeouts: _t,
      hardFailThreshold: 2,
      fetch: (id, c) async {
        tried.add(c);
        if (c == 0) throw Exception('dead client');
        return 'ok';
      },
    );
    await r.resolve('a');
    await r.resolve('b'); // client 0 reaches its threshold here
    tried.clear();
    await r.resolve('c');
    expect(tried, [1]);
  });

  test('a superseded caller returns immediately with cancelled', () async {
    final never = Completer<String?>();
    final superseded = Completer<void>();
    final r = StreamResolver<String>(
      timeouts: _t,
      fetch: (id, c) => never.future,
    );
    final f = r.resolve('v', superseded: superseded.future);
    superseded.complete();
    final res = await f.timeout(const Duration(seconds: 1));
    expect(res.kind, FailureKind.cancelled);
  });

  test('when every caller gives up, the shared fetch stops trying more clients', () async {
    final tried = <int>[];
    final gate = Completer<void>();
    final superseded = Completer<void>();
    final r = StreamResolver<String>(
      timeouts: _t,
      fetch: (id, c) async {
        tried.add(c);
        await gate.future;
        throw Exception('fail');
      },
    );
    final f = r.resolve('v', superseded: superseded.future);
    await Future<void>.delayed(Duration.zero);
    superseded.complete();
    await f;
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(tried, [0], reason: 'abandoned fetch must not continue to clients 1, 2');
  });
}
