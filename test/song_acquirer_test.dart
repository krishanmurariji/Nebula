import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/playback_failure.dart';
import 'package:nebula_music_player/services/song_acquirer.dart';

import 'support/acquirer_rig.dart';

void main() {
  test('a cached song is returned without touching the network', () async {
    await withRig(Rig(), (r) async {
      await r.cache.put('dQw4w9WgXcQ', fileBytes(), protect: {});
      final got = await r.acquire();
      expect(got.fromCache, isTrue);
      expect(got.file!.lengthSync(), total);
      expect(r.resolverCalls, 0);
    });
  });

  test('happy path: downloads, caches, returns a local file', () async {
    await withRig(Rig(), (r) async {
      final got = await r.acquire();
      expect(got.file, isNotNull);
      expect(got.file!.readAsBytesSync(), fileBytes());
      expect(r.cache.contains('dQw4w9WgXcQ'), isTrue);
      expect(r.libraryCalls, 0, reason: 'direct worked, no need for the fallback');
    });
  });

  test('direct refused (403) → the library downloader is used', () async {
    await withRig(Rig(direct: B.status403), (r) async {
      final got = await r.acquire();
      expect(got.file!.readAsBytesSync(), fileBytes());
      expect(r.logs.any((l) => l.contains('HTTP 403')), isTrue);
    });
  });

  test('both strategies fail → DownloadFailure naming both reasons; nothing cached', () async {
    await withRig(Rig(direct: B.status403, library: B.error), (r) async {
      await expectLater(
          r.acquire(),
          throwsA(isA<DownloadFailure>()
              .having((e) => e.client, 'client', 3)
              .having((e) => e.cause.toString(), 'cause', allOf(contains('HTTP 403'), contains('connection reset')))));
      expect(r.cache.contains('dQw4w9WgXcQ'), isFalse);
      await r.acquirer.activeSettled().timeout(const Duration(seconds: 1));
    });
  });

  test('a stalled connection fails by itself instead of hanging', () async {
    await withRig(Rig(direct: B.stall, library: B.stall), (r) async {
      final t = Stopwatch()..start();
      await expectLater(r.acquire(), throwsA(isA<DownloadFailure>()));
      expect(t.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  test('a truncated body or a body bigger than declared is an error, never a corrupt cached song', () async {
    for (final bad in [B.truncated, B.oversize]) {
      await withRig(Rig(direct: bad, library: bad), (r) async {
        await expectLater(r.acquire(), throwsA(isA<DownloadFailure>()), reason: '$bad');
        expect(r.cache.contains('dQw4w9WgXcQ'), isFalse, reason: '$bad');
      });
    }
  });

  test('skipping mid-download abandons it quickly and caches nothing', () async {
    await withRig(Rig(direct: B.slow, library: B.slow, slowMs: 2000), (r) async {
      final skip = Completer<void>();
      final f = r.acquire(superseded: skip.future);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final t = Stopwatch()..start();
      skip.complete();
      await expectLater(f, throwsA(isA<AcquireSuperseded>()));
      expect(t.elapsed, lessThan(const Duration(milliseconds: 500)));
      expect(r.cache.contains('dQw4w9WgXcQ'), isFalse);
      expect(r.libraryCalls, 0, reason: 'a skipped song must not start the fallback downloader');
    });
  });

  test('cancelActive() (a new load started) abandons the download too', () async {
    await withRig(Rig(direct: B.slow, library: B.slow, slowMs: 2000), (r) async {
      final f = r.acquire();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      r.acquirer.cancelActive();
      await expectLater(f, throwsA(isA<AcquireSuperseded>()));
    });
  });

  group('resolver failures keep their meaning', () {
    for (final k in [FailureKind.rateLimited, FailureKind.network, FailureKind.permanent]) {
      test('$k', () async {
        await withRig(Rig(resolveKind: k), (r) async {
          await expectLater(r.acquire(),
              throwsA(isA<ResolveFailure>().having((e) => e.kind, 'kind', k)));
        });
      });
    }

    test('superseded while resolving → AcquireSuperseded, not a failure', () async {
      await withRig(Rig(), (r) async {
        final done = Completer<void>()..complete();
        await expectLater(r.acquire(superseded: done.future), throwsA(isA<AcquireSuperseded>()));
      });
    });
  });

  group('when the file cannot be played from disk the player streams the URL instead', () {
    test('song larger than the in-memory limit', () async {
      await withRig(Rig(size: 5000000), (r) async {
        final got = await r.acquire();
        expect(got.file, isNull);
        expect(got.url.toString(), contains('googlevideo.com'));
        expect(got.headers['User-Agent'], startsWith('com.google.android.youtube'),
            reason: 'without the matching User-Agent the media server answers 403');
        expect(r.directCalls + r.libraryCalls, 0);
      });
    });

    test('no usable disk (cache unavailable)', () async {
      final rig = Rig()..noCache = true;
      await withRig(rig, (r) async {
        final got = await r.acquire();
        expect(got.url, isNotNull);
      });
    });

    test('unknown size (0 bytes declared)', () async {
      await withRig(Rig(size: 0), (r) async {
        expect((await r.acquire()).url, isNotNull);
      });
    });

    test('disk full: the write fails but the client is NOT blamed', () async {
      await withRig(Rig(cacheBuilder: (d) => FullDiskCache(d)), (r) async {
        final got = await r.acquire();
        expect(got.url, isNotNull);
        expect(r.logs.any((l) => l.contains('could not store')), isTrue);
      });
    });
  });

  group('prefetch', () {
    test('caches the next song and reports true', () async {
      await withRig(Rig(), (r) async {
        expect(await r.acquirer.prefetch('dQw4w9WgXcQ'), isTrue);
        expect(r.cache.contains('dQw4w9WgXcQ'), isTrue);
      });
    });

    test('uses the reliable downloader too (direct 403 → library)', () async {
      await withRig(Rig(direct: B.status403), (r) async {
        expect(await r.acquirer.prefetch('dQw4w9WgXcQ'), isTrue);
      });
    });

    test('never throws, whatever goes wrong', () async {
      for (final rig in [
        Rig(direct: B.error, library: B.error),
        Rig(resolveKind: FailureKind.rateLimited),
        Rig(direct: B.truncated, library: B.truncated),
        Rig(size: 5000000),
      ]) {
        await withRig(rig, (r) async {
          expect(await r.acquirer.prefetch('dQw4w9WgXcQ'), isFalse);
        });
      }
    });

    test('an already cached song is not downloaded again', () async {
      await withRig(Rig(), (r) async {
        await r.cache.put('dQw4w9WgXcQ', fileBytes());
        expect(await r.acquirer.prefetch('dQw4w9WgXcQ'), isTrue);
        expect(r.resolverCalls, 0);
      });
    });

    test('cancelPrefetch() stops it', () async {
      await withRig(Rig(direct: B.slow, library: B.slow, slowMs: 2000), (r) async {
        final f = r.acquirer.prefetch('dQw4w9WgXcQ');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        r.acquirer.cancelPrefetch();
        expect(await f.timeout(const Duration(seconds: 1)), isFalse);
        expect(r.cache.contains('dQw4w9WgXcQ'), isFalse);
      });
    });
  });

  test('CHAOS: 150 random combinations of failures always end cleanly', () async {
    final rnd = Random(20261109);
    const behaviours = B.values;
    for (var i = 0; i < 150; i++) {
      final d = behaviours[rnd.nextInt(behaviours.length)];
      final l = behaviours[rnd.nextInt(behaviours.length)];
      final size = [total, total, total, 0, 5000000][rnd.nextInt(5)];
      final skipAfter = rnd.nextBool() ? null : Duration(milliseconds: rnd.nextInt(150));
      final rig = Rig(direct: d, library: l, size: size, slowMs: 150);
      await withRig(rig, (r) async {
        final skip = Completer<void>();
        if (skipAfter != null) Timer(skipAfter, () => skip.complete());

        Object? outcome;
        try {
          outcome = await r.acquire(superseded: skip.future).timeout(const Duration(seconds: 5));
        } on AcquireSuperseded catch (e) {
          outcome = e;
        } on DownloadFailure catch (e) {
          outcome = e;
        } on ResolveFailure catch (e) {
          outcome = e;
        }
        final reason = 'run $i direct=$d library=$l size=$size skip=$skipAfter';
        expect(outcome, isNotNull, reason: reason);

        if (outcome is AcquiredSong) {
          if (outcome.file != null) {
            expect(outcome.file!.existsSync(), isTrue, reason: reason);
            expect(outcome.file!.lengthSync(), total, reason: 'never a partial file: $reason');
          } else {
            expect(outcome.url, isNotNull, reason: reason);
          }
        } else {
          // Failure or abandon: no half-written song may be left behind.
          final cached = r.cache.contains('dQw4w9WgXcQ');
          if (outcome is! AcquiredSong && cached) {
            expect(r.cache.fileFor('dQw4w9WgXcQ').lengthSync(), total, reason: reason);
          }
        }
        await r.acquirer.activeSettled().timeout(const Duration(seconds: 2));
        // No temp files left in the cache folder.
        final leftovers = Directory('${r.root.path}/c').listSync().whereType<File>().where((f) => f.path.endsWith('.tmp'));
        expect(leftovers, isEmpty, reason: reason);
      });
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
