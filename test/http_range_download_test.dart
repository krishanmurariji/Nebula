import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nebula_music_player/services/http_range_download.dart';

Uint8List _file(int n) => Uint8List.fromList(List.generate(n, (i) => i % 251));

/// A tiny fake media server that honours Range requests.
MockClient server(Uint8List data, {List<http.BaseRequest>? seen, int? failStatus}) {
  return MockClient.streaming((req, body) async {
    seen?.add(req);
    if (failStatus != null) {
      return http.StreamedResponse(const Stream.empty(), failStatus, request: req);
    }
    final range = req.headers['Range'] ?? req.headers['range'];
    if (range == null) {
      return http.StreamedResponse(Stream.value(data), 200, request: req);
    }
    final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
    final start = int.parse(m[1]!);
    final end = int.parse(m[2]!).clamp(0, data.length - 1);
    return http.StreamedResponse(
        Stream.value(data.sublist(start, end + 1)), 206, request: req);
  });
}

Future<Uint8List> collect(Stream<List<int>> s) async =>
    Uint8List.fromList([for (final c in await s.toList()) ...c]);

void main() {
  final url = Uri.parse('https://rr1---sn-x.googlevideo.com/videoplayback?sig=SECRET');

  test('downloads a whole file in several ranged requests', () async {
    final data = _file(2500);
    final seen = <http.BaseRequest>[];
    final out = await collect(openRangedDownload(url, data.length,
        client: server(data, seen: seen), chunkBytes: 1000));
    expect(out, data);
    expect(seen.length, 3);
    expect(seen.map((r) => r.headers['Range']),
        ['bytes=0-999', 'bytes=1000-1999', 'bytes=2000-2499']);
  });

  test('sends the User-Agent the URL was issued to', () async {
    final data = _file(100);
    final seen = <http.BaseRequest>[];
    await collect(openRangedDownload(url, data.length,
        userAgent: 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
        client: server(data, seen: seen)));
    expect(seen.single.headers['User-Agent'], startsWith('com.google.android.youtube/'));
  });

  test('a 403 is reported as "HTTP 403 from <host>", not as a silent stall', () async {
    final stream = openRangedDownload(url, 100, client: server(_file(100), failStatus: 403));
    await expectLater(
        collect(stream),
        throwsA(isA<HttpStatusException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.toString(), 'text', contains('googlevideo.com'))));
  });

  test('the error text never contains the signed query string', () async {
    try {
      await collect(openRangedDownload(url, 100, client: server(_file(100), failStatus: 403)));
      fail('should have thrown');
    } catch (e) {
      expect(e.toString(), isNot(contains('SECRET')));
    }
  });

  test('429 and 404 are reported with their codes', () async {
    for (final code in [404, 429, 500]) {
      await expectLater(
          collect(openRangedDownload(url, 100, client: server(_file(100), failStatus: code))),
          throwsA(isA<HttpStatusException>().having((e) => e.status, 'status', code)));
    }
  });

  test('a server that ignores Range (200 + full body) is accepted once', () async {
    final data = _file(300);
    final client = MockClient.streaming((req, body) async =>
        http.StreamedResponse(Stream.value(data), 200, request: req));
    final out = await collect(openRangedDownload(url, data.length, client: client, chunkBytes: 100));
    expect(out, data);
  });

  test('an empty body is an error, not an endless loop', () async {
    final client = MockClient.streaming((req, body) async =>
        http.StreamedResponse(const Stream.empty(), 206, request: req));
    await expectLater(collect(openRangedDownload(url, 100, client: client)), throwsFormatException);
  });

  test('a server that never answers times out instead of hanging', () async {
    final client = MockClient.streaming((req, body) => Completer<http.StreamedResponse>().future);
    await expectLater(
        collect(openRangedDownload(url, 100,
            client: client, firstByteTimeout: const Duration(milliseconds: 100))),
        throwsA(isA<TimeoutException>()));
  });

  test('cancelling the stream stops further requests', () async {
    final data = _file(10000);
    var requests = 0;
    final client = MockClient.streaming((req, body) async {
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 40)); // slow server
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers['Range']!)!;
      final start = int.parse(m[1]!);
      final end = int.parse(m[2]!).clamp(0, data.length - 1);
      return http.StreamedResponse(Stream.value(data.sublist(start, end + 1)), 206, request: req);
    });
    final sub = openRangedDownload(url, data.length, client: client, chunkBytes: 1000).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();
    final n = requests;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(requests, n, reason: 'no new request after cancel');
    expect(n, lessThan(10));
  });
}
