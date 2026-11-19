import 'dart:async';
import 'dart:io';

import 'audio_cache.dart';
import 'playback_failure.dart';
import 'song_acquirer.dart';

/// One stage of the self-test.
class SelfTestStep {
  const SelfTestStep(this.name, this.ok, this.millis, this.detail);
  final String name;
  final bool ok;
  final int millis;
  final String detail;

  @override
  String toString() => '${ok ? '✓' : '✗'} $name  ${millis}ms  $detail';
}

/// A short, very stable public video (the first video ever uploaded to
/// YouTube, 19 seconds): used so a failure means "the app/network", never
/// "that video was removed".
const kSelfTestVideoId = 'jNQXAC9IVRw';

/// Recognises the audio containers YouTube serves.
String? sniffAudioContainer(List<int> head) {
  if (head.length >= 8 &&
      head[4] == 0x66 && head[5] == 0x74 && head[6] == 0x79 && head[7] == 0x70) {
    return 'mp4/m4a';
  }
  if (head.length >= 4 &&
      head[0] == 0x1A && head[1] == 0x45 && head[2] == 0xDF && head[3] == 0xA3) {
    return 'webm/opus';
  }
  return null;
}

/// Runs the whole song pipeline exactly as playback does (lookup, download,
/// cache) for one known video and reports every stage. It does not play audio
/// and leaves the cache as it found it.
Future<List<SelfTestStep>> runSelfTest({
  required SongAcquirer acquirer,
  required AudioCache? Function() cache,
  Future<void> Function()? ensureCache,
  String videoId = kSelfTestVideoId,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final steps = <SelfTestStep>[];
  final total = Stopwatch()..start();

  await ensureCache?.call();
  final store = cache();
  steps.add(SelfTestStep('Disk cache', store != null, 0,
      store != null ? 'available' : 'unavailable: songs will stream without caching'));

  // Test the network path, not a leftover from an earlier test.
  await store?.remove(videoId);

  final t = Stopwatch()..start();
  AcquiredSong? got;
  try {
    got = await acquirer
        .acquire(videoId, superseded: Completer<void>().future)
        .timeout(timeout);
  } on ResolveFailure catch (e) {
    steps.add(SelfTestStep('Find the audio stream', false, t.elapsedMilliseconds,
        _resolveAdvice(e.kind)));
  } on DownloadFailure catch (e) {
    steps.add(SelfTestStep('Download the audio', false, t.elapsedMilliseconds,
        _downloadAdvice(e.cause)));
  } on TimeoutException {
    steps.add(SelfTestStep('Find and download', false, t.elapsedMilliseconds,
        'timed out after ${timeout.inSeconds}s'));
  } catch (e) {
    steps.add(SelfTestStep('Find and download', false, t.elapsedMilliseconds,
        'unexpected: ${e.runtimeType}'));
  }

  if (got != null) {
    final file = got.file;
    if (file == null) {
      steps.add(SelfTestStep('Find and download', true, t.elapsedMilliseconds,
          'stream address found (the player will stream it; not cached)'));
    } else {
      final size = await file.length();
      steps.add(SelfTestStep('Find and download', true, t.elapsedMilliseconds,
          '$size bytes'));

      final head = await _readHead(file);
      final kind = sniffAudioContainer(head);
      steps.add(SelfTestStep('File is real audio', kind != null && size > 10000, 0,
          kind ?? 'not a recognised audio file'));
      steps.add(SelfTestStep('Saved for offline', store?.contains(videoId) ?? false, 0,
          store?.contains(videoId) == true ? 'in the cache' : 'not cached'));
    }
  }

  await store?.remove(videoId); // leave no trace of the test
  steps.add(SelfTestStep('Total', steps.every((s) => s.ok), total.elapsedMilliseconds, ''));
  return steps;
}

Future<List<int>> _readHead(File f) async {
  try {
    final raf = await f.open();
    try {
      return await raf.read(16);
    } finally {
      await raf.close();
    }
  } catch (_) {
    return const [];
  }
}

String _resolveAdvice(FailureKind k) {
  switch (k) {
    case FailureKind.rateLimited:
      return 'YouTube is rate limiting this network. Wait, or use mobile data.';
    case FailureKind.network:
      return "can't reach YouTube (DNS/connection). Run Network check.";
    case FailureKind.permanent:
      return 'YouTube refused every client for this video.';
    default:
      return 'no client could find a stream. YouTube may have changed; see the log.';
  }
}

String _downloadAdvice(Object cause) {
  final status = httpStatusInCause(cause);
  if (status == 403) {
    return 'YouTube refused the download (HTTP 403). The client definitions may '
        'need updating.';
  }
  return 'download failed: ${cause.toString().split(';').first}';
}

/// Plain-language verdict for the dialog.
String selfTestVerdict(List<SelfTestStep> steps) {
  if (steps.isNotEmpty && steps.last.ok) {
    return 'PASS: the song pipeline works end to end on this device and network. '
        '(This checks finding, downloading and saving; use a song to check sound.)';
  }
  final firstBad = steps.where((s) => !s.ok && s.name != 'Total').toList();
  return firstBad.isEmpty
      ? 'FAIL: see the log.'
      : 'FAIL at "${firstBad.first.name}": ${firstBad.first.detail}';
}
