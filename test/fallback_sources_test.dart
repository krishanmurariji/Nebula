import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nebula_music_player/services/fallback_sources.dart';

const _piped = {
  'audioStreams': [
    {'url': 'https://p.example/hi', 'bitrate': 128000, 'mimeType': 'audio/mp4', 'contentLength': 5000000},
    {'url': 'https://p.example/lo', 'bitrate': 48000, 'mimeType': 'audio/mp4', 'contentLength': 1800000},
    {'url': 'https://p.example/webm', 'bitrate': 40000, 'mimeType': 'audio/webm', 'contentLength': 1500000},
    {'url': 'https://p.example/vid', 'bitrate': 10, 'mimeType': 'audio/mp4', 'videoOnly': true},
  ],
};

const _invidious = {
  'adaptiveFormats': [
    {'url': 'https://i.example/video', 'type': 'video/mp4; codecs="avc1"', 'bitrate': '100'},
    {'url': 'https://i.example/a2', 'type': 'audio/mp4; codecs="mp4a.40.2"', 'bitrate': '130000', 'clen': '4000000'},
    {'url': 'https://i.example/a1', 'type': 'audio/mp4; codecs="mp4a.40.5"', 'bitrate': '48000', 'clen': '1700000'},
  ],
};

void main() {
  group('parsers', () {
    test('Piped: lowest-bitrate mp4 audio, ignores video-only', () {
      final c = parsePipedStreams(_piped)!;
      expect(c.url, 'https://p.example/lo');
      expect(c.mimeType, 'audio/mp4');
      expect(c.size, 1800000);
    });

    test('Invidious: audio only, codecs stripped, string numbers parsed', () {
      final c = parseInvidiousVideo(_invidious)!;
      expect(c.url, 'https://i.example/a1');
      expect(c.mimeType, 'audio/mp4');
      expect(c.size, 1700000);
    });

    test('garbage input gives null instead of throwing', () {
      expect(parsePipedStreams(null), isNull);
      expect(parsePipedStreams({'audioStreams': 'nope'}), isNull);
      expect(parseInvidiousVideo([]), isNull);
      expect(parseInvidiousVideo({'adaptiveFormats': []}), isNull);
    });
  });

  group('FallbackStreamFetcher', () {
    FallbackStreamFetcher make(MockClientHandler h, List<String> bases,
        {DateTime Function()? now}) {
      return FallbackStreamFetcher(
        instances: () async => bases,
        client: MockClient(h),
        now: now,
      );
    }

    test('resolves through a Piped instance', () async {
      final f = make((req) async {
        if (req.url.path == '/streams/abc') {
          return http.Response(jsonEncode(_piped), 200);
        }
        return http.Response('', 404);
      }, ['https://pipe.example/']);
      final r = await f.fetch('abc');
      expect(r, isNotNull);
      expect(r!.url.toString(), 'https://p.example/lo');
      expect(r.totalBytes, 1800000);
      expect(r.origin, 'pipe.example');
    });

    test('falls back to the Invidious API when Piped path is 404', () async {
      final f = make((req) async {
        if (req.url.path == '/api/v1/videos/abc') {
          expect(req.url.queryParameters['local'], 'true');
          return http.Response(jsonEncode(_invidious), 200);
        }
        return http.Response('not found', 404);
      }, ['https://inv.example']);
      final r = await f.fetch('abc');
      expect(r!.url.toString(), 'https://i.example/a1');
    });

    test('a dead instance is skipped, next one is used, dead one is not retried soon', () async {
      var deadCalls = 0;
      var now = DateTime(2026);
      final f = make((req) async {
        if (req.url.host == 'dead.example') {
          deadCalls++;
          throw http.ClientException('connection refused');
        }
        return http.Response(jsonEncode(_piped), 200);
      }, ['https://dead.example', 'https://ok.example'], now: () => now);

      expect(await f.fetch('a'), isNotNull);
      final firstCalls = deadCalls;
      expect(await f.fetch('b'), isNotNull);
      expect(deadCalls, firstCalls, reason: 'cooling down, not asked again');

      now = now.add(const Duration(minutes: 5));
      await f.fetch('c');
      expect(deadCalls, greaterThan(firstCalls), reason: 'cooldown expired');
    });

    test('missing size triggers a HEAD request', () async {
      final noSize = {
        'audioStreams': [
          {'url': 'https://p.example/lo', 'bitrate': 48000, 'mimeType': 'audio/mp4'},
        ],
      };
      final f = make((req) async {
        if (req.method == 'HEAD') {
          return http.Response('', 200, headers: {'content-length': '999999'});
        }
        return http.Response(jsonEncode(noSize), 200);
      }, ['https://pipe.example']);
      expect((await f.fetch('abc'))!.totalBytes, 999999);
    });

    test('never throws; returns null when every instance fails or none configured', () async {
      final bad = make((req) async => throw Exception('network down'),
          ['https://a.example', 'https://b.example']);
      expect(await bad.fetch('abc'), isNull);
      final none = make((req) async => http.Response('', 500), []);
      expect(await none.fetch('abc'), isNull);
    });

    test('the byte stream is served from the resolved URL', () async {
      final f = make((req) async {
        if (req.url.host == 'p.example') {
          return http.Response.bytes(List.filled(1800000, 7), 200);
        }
        return http.Response(jsonEncode(_piped), 200);
      }, ['https://pipe.example']);
      final r = (await f.fetch('abc'))!;
      final bytes = [for (final c in await r.open().toList()) ...c];
      expect(bytes.length, 1800000);
    });
  });
}
