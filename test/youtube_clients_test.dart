import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/youtube_clients.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  for (final entry in {'tv_samsung': kTvSamsungClient, 'visionos': kVisionOsClient}.entries) {
    group(entry.key, () {
      final c = entry.value;
      final client = c.payload['context']['client'] as Map;

      test('has the fields the API and the media download need', () {
        for (final k in ['clientName', 'clientVersion', 'userAgent', 'hl', 'osName']) {
          expect(client[k], isA<String>(), reason: k);
          expect((client[k] as String).isNotEmpty, isTrue, reason: k);
        }
        expect(c.apiUrl, startsWith('https://www.youtube.com/youtubei/v1/player'));
      });

      test('sends the numeric client id YouTube expects (the library sends the name)', () {
        expect(int.tryParse(c.headers['X-Youtube-Client-Name'] ?? ''), isNotNull);
        expect(c.headers['X-Youtube-Client-Version'], client['clientVersion']);
      });

      test('asks YouTube to skip content/racy check interstitials', () {
        expect(c.payload['contentCheckOk'], isTrue);
        expect(c.payload['racyCheckOk'], isTrue);
      });
    });
  }

  test('the two clients are distinct and match yt-dlp numbering', () {
    expect(kTvSamsungClient.headers['X-Youtube-Client-Name'], '7');
    expect(kVisionOsClient.headers['X-Youtube-Client-Name'], '101');
    expect(kTvSamsungClient.payload['context']['client']['clientName'], 'TVHTML5');
    expect(kVisionOsClient.payload['context']['client']['clientName'], 'VISIONOS');
  });

  test('they can be used as library clients', () {
    final List<YoutubeApiClient> list = [kTvSamsungClient, kVisionOsClient];
    expect(list.length, 2);
  });
}
