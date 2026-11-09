import 'dart:async';

import 'package:http/http.dart' as http;

/// The server answered, but not with the audio (403, 404, 429 …).
class HttpStatusException implements Exception {
  const HttpStatusException(this.status, this.host);
  final int status;
  final String host;
  @override
  String toString() => 'HTTP $status from $host';
}

/// Downloads [url] with plain ranged GET requests, sending [userAgent].
///
/// Why this exists: YouTube issues each stream URL to a specific client (the
/// Android app, the TV app …) and the media server expects that client's
/// User-Agent. The library's downloader sends a desktop-Chrome User-Agent for
/// everything, and on a real phone the server then accepted the connection and
/// never sent a byte. This one also reports the real HTTP status, so a refusal
/// shows up as "HTTP 403" instead of a silent stall.
Stream<List<int>> openRangedDownload(
  Uri url,
  int totalBytes, {
  String? userAgent,
  http.Client? client,
  int chunkBytes = 8 * 1024 * 1024,
  Duration firstByteTimeout = const Duration(seconds: 12),
}) async* {
  final c = client ?? http.Client();
  try {
    var pos = 0;
    while (pos < totalBytes) {
      final end = (pos + chunkBytes < totalBytes ? pos + chunkBytes : totalBytes) - 1;
      final req = http.Request('GET', url)
        ..headers['Range'] = 'bytes=$pos-$end'
        ..headers['Accept'] = '*/*'
        ..headers['Accept-Language'] = 'en-US,en;q=0.5';
      if (userAgent != null) req.headers['User-Agent'] = userAgent;

      final res = await c.send(req).timeout(firstByteTimeout);
      if (res.statusCode != 200 && res.statusCode != 206) {
        // Drain so the connection can be reused/closed, then report the status.
        unawaited(res.stream.drain<void>().catchError((Object _) {}));
        throw HttpStatusException(res.statusCode, url.host);
      }

      var got = 0;
      await for (final data in res.stream) {
        got += data.length;
        yield data;
      }
      if (got == 0) {
        throw const FormatException('server returned an empty body');
      }
      pos += got;
      // A 200 means the server ignored the range and sent everything.
      if (res.statusCode == 200) return;
    }
  } finally {
    if (client == null) c.close();
  }
}
