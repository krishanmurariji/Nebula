import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/playback_failure.dart';
import 'package:nebula_music_player/services/self_test.dart';

import 'support/acquirer_rig.dart';

/// A valid-looking mp4 header followed by filler.
Uint8List mp4Like(int n) {
  final b = Uint8List(n);
  b.setRange(4, 8, [0x66, 0x74, 0x79, 0x70]); // "ftyp"
  return b;
}

void main() {
  test('sniffAudioContainer recognises mp4/m4a and webm/opus, nothing else', () {
    expect(sniffAudioContainer(mp4Like(16)), 'mp4/m4a');
    expect(sniffAudioContainer([0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0]), 'webm/opus');
    expect(sniffAudioContainer('<html>blocked</html>'.codeUnits), isNull);
    expect(sniffAudioContainer(const []), isNull);
    expect(sniffAudioContainer([1, 2, 3]), isNull);
  });

  Future<List<SelfTestStep>> run(Rig r) => runSelfTest(
        acquirer: r.acquirer,
        cache: () => r.noCache ? null : r.cache,
        videoId: 'dQw4w9WgXcQ',
        timeout: const Duration(seconds: 5),
      );

  test('a healthy pipeline passes and leaves the cache as it found it', () async {
    await withRig(Rig(), (r) async {
      final steps = await run(r);
      final names = steps.map((s) => s.name).toList();
      expect(names, ['Disk cache', 'Find and download', 'File is real audio', 'Saved for offline', 'Total']);
      expect(steps.every((s) => s.ok), isTrue, reason: steps.join('\n'));
      expect(selfTestVerdict(steps), startsWith('PASS'));
      expect(r.cache.contains('dQw4w9WgXcQ'), isFalse, reason: 'no trace of the test is left');
    });
  });

  test('a song already in the cache is re-downloaded, so the network path is what is tested', () async {
    await withRig(Rig(), (r) async {
      await r.cache.put('dQw4w9WgXcQ', fileBytes());
      await run(r);
      expect(r.resolverCalls, greaterThan(0));
    });
  });

  test('YouTube refusing every download is reported with a clear reason', () async {
    await withRig(Rig(direct: B.status403, library: B.status403), (r) async {
      final steps = await run(r);
      final bad = steps.firstWhere((s) => !s.ok && s.name != 'Total');
      expect(bad.name, 'Download the audio');
      expect(bad.detail, contains('403'));
      expect(selfTestVerdict(steps), allOf(startsWith('FAIL'), contains('Download the audio')));
    });
  });

  for (final k in [FailureKind.rateLimited, FailureKind.network, FailureKind.permanent]) {
    test('lookup failure $k gives specific advice', () async {
      await withRig(Rig(resolveKind: k), (r) async {
        final steps = await run(r);
        final bad = steps.firstWhere((s) => !s.ok && s.name != 'Total');
        expect(bad.name, 'Find the audio stream');
        final expected = {
          FailureKind.rateLimited: 'rate limiting',
          FailureKind.network: 'Network check',
          FailureKind.permanent: 'refused every client',
        }[k]!;
        expect(bad.detail, contains(expected));
      });
    });
  }

  test('a hung pipeline times out instead of freezing the dialog', () async {
    await withRig(Rig(direct: B.slow, library: B.slow, slowMs: 30000), (r) async {
      final steps = await runSelfTest(
        acquirer: r.acquirer,
        cache: () => r.cache,
        videoId: 'dQw4w9WgXcQ',
        timeout: const Duration(milliseconds: 300),
      );
      expect(steps.any((s) => s.detail.contains('timed out')), isTrue);
      expect(steps.last.ok, isFalse);
    });
  });

  test('no usable disk: reports it, still finds a stream', () async {
    final rig = Rig()..noCache = true;
    await withRig(rig, (r) async {
      final steps = await run(r);
      expect(steps.first.name, 'Disk cache');
      expect(steps.first.ok, isFalse);
      expect(steps.firstWhere((s) => s.name == 'Find and download').ok, isTrue);
    });
  });

  test('verdict text', () {
    expect(selfTestVerdict(const [SelfTestStep('Total', true, 1, '')]), startsWith('PASS'));
    expect(selfTestVerdict(const []), startsWith('FAIL'));
  });
}
