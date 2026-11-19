import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/playback_failure.dart';
import 'package:nebula_music_player/services/progressive_download.dart';
import 'package:nebula_music_player/services/resolved_stream.dart';
import 'package:nebula_music_player/services/stream_resolver.dart';

const _t = [Duration(seconds: 5), Duration(seconds: 5), Duration(seconds: 5)];

void main() {
  group('stall watchdog', () {
    test('a download that stops receiving data fails instead of hanging', () async {
      final src = StreamController<List<int>>();
      final dl = ProgressiveDownload(
        open: () => src.stream,
        totalBytes: 1000,
        stallTimeout: const Duration(milliseconds: 150),
      );
      dl.start();
      src.add(Uint8List(100)); // then silence
      await expectLater(dl.completed.timeout(const Duration(seconds: 3)), throwsA(isA<TimeoutException>()));
      expect(dl.isFailed, isTrue);
    });

    test('nothing at all arriving also counts as a stall', () async {
      final src = StreamController<List<int>>();
      final dl = ProgressiveDownload(
        open: () => src.stream,
        totalBytes: 1000,
        stallTimeout: const Duration(milliseconds: 150),
      );
      dl.start();
      await expectLater(dl.completed.timeout(const Duration(seconds: 3)), throwsA(isA<TimeoutException>()));
    });

    test('steady progress never trips the watchdog', () async {
      final src = StreamController<List<int>>();
      final dl = ProgressiveDownload(
        open: () => src.stream,
        totalBytes: 600,
        stallTimeout: const Duration(milliseconds: 300),
      );
      dl.start();
      for (var i = 0; i < 6; i++) {
        src.add(Uint8List(100));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await src.close();
      expect((await dl.completed).length, 600);
    });

    test('watchdog stops after completion or cancel (no late errors)', () async {
      final src = StreamController<List<int>>();
      final dl = ProgressiveDownload(
        open: () => src.stream,
        totalBytes: 10,
        stallTimeout: const Duration(milliseconds: 90),
      );
      dl.start();
      src.add(Uint8List(10));
      await src.close();
      await dl.completed;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(dl.isFailed, isFalse);
    });
  });

  group('resolver: unusable clients', () {
    test('penalize() makes the next resolve skip that client', () async {
      final tried = <int>[];
      final r = StreamResolver<String>(
        timeouts: _t,
        fetch: (id, c) async {
          tried.add(c);
          return 'url-from-$c';
        },
      );
      expect((await r.resolve('a')).value, 'url-from-0');
      r.invalidate('a'); // the stream from client 0 turned out to be a 403
      r.penalize(0, const Duration(minutes: 5));
      tried.clear();
      expect((await r.resolve('a')).value, 'url-from-1');
      expect(tried, [1], reason: 'client 0 is not even asked');
    });

    test('a penalty expires', () async {
      var now = DateTime(2026);
      final tried = <int>[];
      final r = StreamResolver<String>(
        timeouts: _t,
        now: () => now,
        fetch: (id, c) async {
          tried.add(c);
          return 'x';
        },
      );
      r.penalize(0, const Duration(minutes: 5));
      await r.resolve('a');
      expect(tried, [1]);
      now = now.add(const Duration(minutes: 6));
      tried.clear();
      await r.resolve('b');
      // Client 1 worked while 0 was penalized, so it is now the favourite and
      // is asked first; the expired penalty only means 0 is allowed again.
      expect(tried, [1]);
      r.invalidate('b');
      r.penalize(1, const Duration(minutes: 5));
      tried.clear();
      await r.resolve('b');
      expect(tried, [0], reason: 'once 1 is penalized, 0 (no longer penalized) is used');
    });

    test('penalizing out-of-range or negative clients is ignored', () {
      final r = StreamResolver<String>(timeouts: _t, fetch: (id, c) async => 'x');
      expect(() => r.penalize(-1, const Duration(seconds: 1)), returnsNormally);
      expect(() => r.penalize(99, const Duration(seconds: 1)), returnsNormally);
    });

    test('failure reasons are logged for every client that fails', () async {
      final lines = <String>[];
      final r = StreamResolver<String>(
        timeouts: _t,
        log: lines.add,
        fetch: (id, c) async {
          if (c == 0) throw StateError('requires sign in');
          if (c == 1) return null;
          return 'ok';
        },
      );
      expect((await r.resolve('v')).value, 'ok');
      expect(lines.any((l) => l.contains('client 0 failed') && l.contains('requires sign in')), isTrue, reason: '$lines');
      expect(lines.any((l) => l.contains('client 1') && l.contains('no usable audio')), isTrue, reason: '$lines');
    });

    test('every client penalized → no result and a countdown, not a crash', () async {
      final r = StreamResolver<String>(
        timeouts: _t,
        fetch: (id, c) async => 'x',
      );
      for (var i = 0; i < 3; i++) {
        r.penalize(i, const Duration(minutes: 5));
      }
      final res = await r.resolve('v');
      expect(res.value, isNull);
      expect(r.globalCooldownSeconds, greaterThan(0));
    });
  });

  group('network failures (DNS)', () {
    test('the first DNS failure stops the lookup: no other client is asked', () async {
      final tried = <int>[];
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        fetch: (id, c) async {
          tried.add(c);
          throw Exception("ClientException with SocketException: Failed host lookup: 'www.youtube.com'");
        },
      );
      final res = await r.resolve('v');
      expect(res.kind, FailureKind.network);
      expect(tried, [0]);
    });

    test('a network failure does not penalize the client or start a pause', () async {
      var fail = true;
      final r = StreamResolver<String>(
        timeouts: _t,
        minGap: Duration.zero,
        fetch: (id, c) async {
          if (fail) throw Exception('SocketException: Failed host lookup');
          return 'ok-$c';
        },
      );
      await r.resolve('v');
      expect(r.globalCooldownSeconds, 0);
      fail = false;
      expect((await r.resolve('v')).value, 'ok-0', reason: 'client 0 is still in use');
    });
  });

  test('ResolvedStream.withClient keeps everything and records the client', () {
    final s = ResolvedStream(
      url: Uri.parse('https://a.example/x'),
      totalBytes: 5,
      mimeType: 'audio/mp4',
      open: () => const Stream.empty(),
      origin: 'o',
    );
    final c = s.withClient(3);
    expect(c.clientIndex, 3);
    expect(c.url, s.url);
    expect(c.totalBytes, 5);
    expect(c.origin, 'o');
    expect(s.clientIndex, -1);
  });
}
