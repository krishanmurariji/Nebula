import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nebula_music_player/services/app_log.dart';
import 'package:nebula_music_player/services/audio_cache.dart';
import 'package:nebula_music_player/services/fallback_sources.dart';
import 'package:nebula_music_player/services/progressive_download.dart';

void main() {
  group('AudioCache: untrusted ids can never escape the cache folder', () {
    late Directory root, dir;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('nebula_sec');
      dir = Directory('${root.path}/cache');
    });
    tearDown(() async => root.delete(recursive: true));

    final evil = ['../escape', '../../escape', 'a/b', r'a\b', '', '.', '..', 'x' * 200, 'a b', 'a\u0000b', '%2e%2e%2fx'];

    test('isSafeId', () {
      expect(AudioCache.isSafeId('dQw4w9WgXcQ'), isTrue);
      expect(AudioCache.isSafeId('a-b_C9'), isTrue);
      for (final id in evil) {
        expect(AudioCache.isSafeId(id), isFalse, reason: id);
      }
    });

    test('put / lookup / remove / contains ignore unsafe ids and write nothing outside', () async {
      final c = AudioCache(dir);
      await c.init();
      final bytes = Uint8List(10000);
      for (final id in evil) {
        await c.put(id, bytes);
        expect(c.contains(id), isFalse);
        expect(await c.lookup(id), isNull);
        await c.remove(id); // must not delete anything either
      }
      expect(await root.list(recursive: true).where((e) => e is File).toList(), isEmpty);
    });

    test('remove() cannot delete a file outside the cache', () async {
      final victim = File('${root.path}/victim.mp4')..writeAsBytesSync([1, 2, 3]);
      final c = AudioCache(dir);
      await c.init();
      await c.remove('../victim');
      expect(victim.existsSync(), isTrue);
    });

    test('a tampered index.json with unsafe ids is ignored', () async {
      await dir.create(recursive: true);
      File('${root.path}/outside.mp4').writeAsBytesSync(Uint8List(9000));
      File('${dir.path}/index.json').writeAsStringSync(jsonEncode([
        {'id': '../outside', 'sz': 9000, 'ts': 1},
        {'id': 5, 'sz': 'x', 'ts': null},
      ]));
      final c = AudioCache(dir);
      await c.init();
      expect(c.count, 0);
      expect(File('${root.path}/outside.mp4').existsSync(), isTrue, reason: 'init must not delete outside files');
    });
  });

  group('ProgressiveDownload: hostile server', () {
    test('sending more than declared fails instead of filling memory', () async {
      final src = StreamController<List<int>>();
      final dl = ProgressiveDownload(open: () => src.stream, totalBytes: 100);
      dl.start();
      src.add(Uint8List(60));
      src.add(Uint8List(60)); // 120 > 100
      await expectLater(dl.completed, throwsStateError);
      expect(dl.receivedBytes, 60, reason: 'the oversized chunk is not stored');
    });

    test('a download that never ends can be cancelled', () async {
      var cancelled = false;
      final src = StreamController<List<int>>(onCancel: () => cancelled = true);
      final dl = ProgressiveDownload(open: () => src.stream, totalBytes: 1 << 30);
      dl.start();
      src.add(Uint8List(10));
      dl.cancel();
      expect(cancelled, isTrue);
    });

    test('opening throws synchronously → surfaced as failure, not a crash', () async {
      final dl = ProgressiveDownload(open: () => throw Exception('boom'), totalBytes: 10);
      dl.start();
      await expectLater(dl.completed, throwsException);
    });
  });

  group('log redaction', () {
    test('query strings of URLs are removed, host and path stay', () {
      final r = redactSecrets(
          'GET https://rr3---sn-x.googlevideo.com/videoplayback?expire=1&ip=1.2.3.4&sig=SECRET&n=abc failed');
      expect(r, contains('googlevideo.com/videoplayback'));
      expect(r, isNot(contains('SECRET')));
      expect(r, isNot(contains('1.2.3.4')));
    });

    test('key=value secrets are removed even outside URLs', () {
      final r = redactSecrets('retry with token=abcdef123 and Password=hunter2 key=zzz');
      expect(r, isNot(contains('abcdef123')));
      expect(r, isNot(contains('hunter2')));
      expect(r, isNot(contains('zzz')));
    });

    test('exception text inside quotes is redacted too', () {
      final r = redactSecrets('ClientException: Failed, uri=https://x.example/a?token=T0P');
      expect(r, isNot(contains('T0P')));
    });

    test('ordinary lines are untouched', () {
      expect(redactSecrets('[N] ▶ Song title (attempt 0)'), '[N] ▶ Song title (attempt 0)');
    });

    test('AppLog applies it to everything it stores', () {
      AppLog.instance.clear();
      AppLog.instance.add('https://a.example/p?sig=ABC123');
      expect(AppLog.instance.dump(), isNot(contains('ABC123')));
    });
  });

  group('normalizeInstanceUrl', () {
    test('accepts public https servers and cleans them', () {
      expect(normalizeInstanceUrl('https://pipedapi.kavin.rocks/'), 'https://pipedapi.kavin.rocks');
      expect(normalizeInstanceUrl('  https://yewtu.be  '), 'https://yewtu.be');
      expect(normalizeInstanceUrl('https://my.server.com:8443/api//'), 'https://my.server.com:8443/api');
    });

    test('rejects everything risky', () {
      const bad = [
        '', '   ', 'http://pipedapi.kavin.rocks', 'ftp://x.example.com', 'file:///etc/passwd',
        'javascript:alert(1)', 'https://localhost', 'https://127.0.0.1', 'https://10.0.0.5',
        'https://192.168.1.2', 'https://172.16.0.1', 'https://172.31.255.1', 'https://169.254.169.254',
        'https://0.0.0.0', 'https://user:pw@example.com', 'https://example.com/?q=1',
        'https://example.com/#frag', 'https://printer.local', 'https://db.internal', 'https://intranet',
        'https://[::1]', 'not a url', 'https://', 'https://exa mple.com',
      ];
      for (final b in bad) {
        expect(normalizeInstanceUrl(b), isNull, reason: 'should reject "$b"');
      }
      expect(normalizeInstanceUrl('https://${'a' * 300}.com'), isNull);
    });

    test('public IPs and 172.x outside the private range are fine', () {
      expect(normalizeInstanceUrl('https://172.32.0.1'), isNotNull);
      expect(normalizeInstanceUrl('https://8.8.8.8'), isNotNull);
    });
  });

  group('FallbackStreamFetcher: hostile or broken servers', () {
    const piped = {
      'audioStreams': [
        {'url': 'https://m.example/a', 'bitrate': 48000, 'mimeType': 'audio/mp4', 'contentLength': 1000000},
      ],
    };

    FallbackStreamFetcher make(MockClientHandler h, List<String> bases) =>
        FallbackStreamFetcher(instances: () async => bases, client: MockClient(h));

    test('a server that points media at http:// is rejected', () async {
      final f = make((r) async => http.Response(
              jsonEncode({'audioStreams': [{'url': 'http://m.example/a', 'bitrate': 1, 'mimeType': 'audio/mp4', 'contentLength': 5000}]}), 200),
          ['https://p.example.com']);
      expect(await f.fetch('abc'), isNull);
    });

    test('a server declaring an enormous size is rejected', () async {
      final f = make((r) async => http.Response(
              jsonEncode({'audioStreams': [{'url': 'https://m.example/a', 'bitrate': 1, 'mimeType': 'audio/mp4', 'contentLength': 50 * 1024 * 1024 * 1024}]}), 200),
          ['https://p.example.com']);
      expect(await f.fetch('abc'), isNull);
    });

    test('invalid / dangerous instance entries are never contacted', () async {
      final contacted = <String>[];
      final f = make((r) async {
        contacted.add(r.url.toString());
        return http.Response(jsonEncode(piped), 200);
      }, ['http://evil.example.com', 'https://192.168.0.10', 'https://localhost', 'https://good.example.com']);
      expect(await f.fetch('abc'), isNotNull);
      expect(contacted.every((u) => u.startsWith('https://good.example.com')), isTrue, reason: '$contacted');
    });

    test('garbage bodies (HTML, truncated JSON, empty, huge nesting) never throw', () async {
      for (final body in ['<html>blocked</html>', '{"audioStreams":[', '', 'null', '[]', '{"audioStreams":[null,1,"x",{}]}']) {
        final f = make((r) async => http.Response(body, 200), ['https://p.example.com']);
        expect(await f.fetch('abc'), isNull, reason: body);
      }
    });

    test('HTTP errors and timeouts are just "no result"', () async {
      for (final code in [403, 404, 429, 500, 503]) {
        final f = make((r) async => http.Response('', code), ['https://p.example.com']);
        expect(await f.fetch('abc'), isNull, reason: '$code');
      }
    });

    test('at most 8 instances are tried (a huge saved list cannot cause a request storm)', () async {
      var calls = 0;
      final f = FallbackStreamFetcher(
        instances: () async => [for (var i = 0; i < 100; i++) 'https://s$i.example.com'],
        client: MockClient((r) async {
          calls++;
          return http.Response('', 500);
        }),
      );
      await f.fetch('abc');
      expect(calls, lessThanOrEqualTo(16)); // 8 instances × (piped + invidious)
    });
  });
}
