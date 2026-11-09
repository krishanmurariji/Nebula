import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/playback_failure.dart';

class VideoUnavailableException implements Exception {}

class RequestLimitExceededException implements Exception {}

void main() {
  group('classifyPlaybackError', () {
    test('self-inflicted interruptions are ignored', () {
      expect(
          classifyPlaybackError(
              Exception('PlatformException(abort, Loading interrupted)')),
          FailureKind.cancelled);
      expect(classifyPlaybackError(Exception('player already exists')),
          FailureKind.cancelled);
    });

    test('rate limiting is detected by type and by message', () {
      expect(classifyPlaybackError(RequestLimitExceededException()),
          FailureKind.rateLimited);
      expect(classifyPlaybackError(Exception('HTTP 429 Too Many Requests')),
          FailureKind.rateLimited);
    });

    test('unavailable videos are permanent', () {
      expect(classifyPlaybackError(VideoUnavailableException()),
          FailureKind.permanent);
      expect(classifyPlaybackError(Exception('Private video')),
          FailureKind.permanent);
    });

    test('everything else is transient (worth a retry)', () {
      expect(classifyPlaybackError(Exception('Source error 403')),
          FailureKind.transient);
      expect(classifyPlaybackError(Exception('Timeout while waiting')),
          FailureKind.transient);
    });
  });

  test('DNS and connection failures are classified as network problems', () {
    for (final msg in [
      "ClientException with SocketException: Failed host lookup: 'www.youtube.com' (OS Error: No address associated with hostname, errno = 7)",
      'SocketException: Connection refused',
      'Connection reset by peer',
      'Network is unreachable',
    ]) {
      expect(classifyPlaybackError(Exception(msg)), FailureKind.network, reason: msg);
    }
  });

  test('retryDelay backs off and is capped', () {
    expect(retryDelay(0), const Duration(milliseconds: 800));
    expect(retryDelay(1), const Duration(milliseconds: 1600));
    expect(retryDelay(2), const Duration(milliseconds: 3200));
    expect(retryDelay(10), const Duration(seconds: 6));
  });
}
