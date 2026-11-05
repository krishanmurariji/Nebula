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

  test('a rate-limited client is skipped on the next resolve', () async {
    final tried = <int>[];
    final r = StreamResolver<String>(
      timeouts: _t,
      fetch: (id, c) async {
        tried.add(c);
        if (c == 0) throw RequestLimitExceededException();
        return 'ok';
      },
    );
    await r.resolve('a');
    tried.clear();
    await r.resolve('b');
    expect(tried, [1], reason: 'client 0 is cooling down');
  });

  test('all clients rate limited, long wait → rateLimited with countdown', () async {
    final r = StreamResolver<String>(
      timeouts: _t,
      maxInlineWait: Duration.zero, // never wait inline
      fetch: (id, c) async => throw RequestLimitExceededException(),
    );
    final res = await r.resolve('v');
    expect(res.value, isNull);
    expect(res.kind, FailureKind.rateLimited);
    expect(r.globalCooldownSeconds, greaterThan(0));
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
