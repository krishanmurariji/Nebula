import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'resolved_stream.dart';

/// No backup servers are built in: public Piped/Invidious instances are
/// frequently blocked, rate limited or shut down (both former defaults were
/// unreachable on the first real device). Add your own in Settings → Backup
/// Sources. An empty list simply switches this fallback off.
const List<String> kDefaultBackupInstances = [];

/// Validates a user-entered backup server address. Returns the cleaned base
/// URL (no trailing slash) or null when it is not acceptable: only https, a
/// real host, no embedded credentials, no query/fragment, and not a local or
/// private-network address.
String? normalizeInstanceUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text.length > 200) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https') return null;
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  if (uri.hasQuery || uri.hasFragment) return null;
  final host = uri.host.toLowerCase();
  // Plain DNS names / IPv4 only (Uri silently percent-encodes odd characters).
  if (!RegExp(r'^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$').hasMatch(host)) return null;
  if (!host.contains('.')) return null; // "localhost", bare names
  if (host.endsWith('.local') || host.endsWith('.internal')) return null;
  final ip = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
  if (ip != null) {
    final a = int.parse(ip[1]!), b = int.parse(ip[2]!);
    final isPrivate = a == 10 ||
        a == 127 ||
        a == 0 ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
    if (isPrivate) return null;
  }
  if (host.contains(':')) return null; // IPv6 literal
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return 'https://${uri.host}$port$path';
}

/// The most bytes we will accept for one song from a backup server.
const int kMaxBackupBytes = 300 * 1024 * 1024;

class _Candidate {
  _Candidate(this.url, this.bitrate, this.mimeType, this.size);
  final String url;
  final int bitrate;
  final String mimeType;
  final int? size;
}

/// Picks the lowest-bitrate mp4 audio (fast start, small), else lowest of any.
_Candidate? _pickLowest(List<_Candidate> all) {
  if (all.isEmpty) return null;
  int byBitrate(_Candidate a, _Candidate b) => a.bitrate.compareTo(b.bitrate);
  final mp4 = all.where((c) => c.mimeType.contains('mp4')).toList()
    ..sort(byBitrate);
  if (mp4.isNotEmpty) return mp4.first;
  return (all.toList()..sort(byBitrate)).first;
}

String _cleanMime(String raw) => raw.split(';').first.trim();

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Parses a Piped `GET /streams/{id}` response.
_Candidate? parsePipedStreams(Object? json) {
  if (json is! Map) return null;
  final list = json['audioStreams'];
  if (list is! List) return null;
  final out = <_Candidate>[];
  for (final s in list) {
    if (s is! Map) continue;
    final url = s['url'];
    if (url is! String || url.isEmpty) continue;
    if (s['videoOnly'] == true) continue;
    out.add(_Candidate(
      url,
      _asInt(s['bitrate']) ?? 0,
      _cleanMime((s['mimeType'] as String?) ?? 'audio/mp4'),
      _asInt(s['contentLength']),
    ));
  }
  return _pickLowest(out);
}

/// Parses an Invidious `GET /api/v1/videos/{id}` response.
_Candidate? parseInvidiousVideo(Object? json) {
  if (json is! Map) return null;
  final list = json['adaptiveFormats'];
  if (list is! List) return null;
  final out = <_Candidate>[];
  for (final s in list) {
    if (s is! Map) continue;
    final url = s['url'];
    final type = s['type'];
    if (url is! String || url.isEmpty) continue;
    if (type is! String || !type.startsWith('audio/')) continue;
    out.add(_Candidate(
      url,
      _asInt(s['bitrate']) ?? 0,
      _cleanMime(type),
      _asInt(s['clen']),
    ));
  }
  return _pickLowest(out);
}

/// Resolves a video through Piped / Invidious instances when YouTube itself
/// refuses. Never throws: any failure is "no result", so a dead backup can
/// never be mistaken for a dead video.
class FallbackStreamFetcher {
  FallbackStreamFetcher({
    required this.instances,
    http.Client? client,
    this.perInstanceTimeout = const Duration(seconds: 8),
    this.deadInstanceCooldown = const Duration(seconds: 90),
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now;

  /// Called on every fetch so edits in Settings apply immediately.
  final Future<List<String>> Function() instances;
  final http.Client _client;
  final Duration perInstanceTimeout;
  final Duration deadInstanceCooldown;
  final DateTime Function() _now;
  final Map<String, DateTime> _deadUntil = {};

  Future<ResolvedStream?> fetch(String videoId) async {
    List<String> bases;
    try {
      bases = await instances();
    } catch (_) {
      bases = kDefaultBackupInstances;
    }
    for (final raw in bases.take(8)) {
      final base = normalizeInstanceUrl(raw);
      if (base == null) {
        nlog('[N] backup entry ignored (not a valid https address)');
        continue;
      }
      final dead = _deadUntil[base];
      if (dead != null && _now().isBefore(dead)) continue;
      try {
        final r = await _fromInstance(base, videoId)
            .timeout(perInstanceTimeout * 2);
        if (r != null) {
          nlog('[N] backup ok via ${Uri.parse(base).host}');
          return r;
        }
      } catch (e) {
        nlog('[N] backup ${Uri.tryParse(base)?.host ?? base} failed: $e');
        _deadUntil[base] = _now().add(deadInstanceCooldown);
      }
    }
    return null;
  }

  Future<Object?> _getJson(String url) async {
    final res =
        await _client.get(Uri.parse(url)).timeout(perInstanceTimeout);
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body);
  }

  Future<ResolvedStream?> _fromInstance(String base, String videoId) async {
    var c = parsePipedStreams(await _getJson('$base/streams/$videoId'));
    // `local=true` makes Invidious proxy the media through itself, so the
    // URL is not locked to the instance's IP address.
    c ??= parseInvidiousVideo(
        await _getJson('$base/api/v1/videos/$videoId?local=true'));
    if (c == null) return null;

    var url = Uri.parse(c.url);
    if (!url.hasScheme) url = Uri.parse(base).resolveUri(url);
    // Media must come over https; never follow an instance to http/file/etc.
    if (url.scheme != 'https') return null;

    var size = c.size;
    if (size == null || size <= 0) {
      final head = await _client.head(url).timeout(perInstanceTimeout);
      size = int.tryParse(head.headers['content-length'] ?? '');
    }
    if (size == null || size <= 0 || size > kMaxBackupBytes) return null;

    return ResolvedStream(
      url: url,
      totalBytes: size,
      mimeType: c.mimeType,
      origin: Uri.parse(base).host,
      open: () => _openStream(url, size!),
    );
  }

  Stream<List<int>> _openStream(Uri url, int total) async* {
    final req = http.Request('GET', url);
    final res = await _client.send(req);
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw http.ClientException('HTTP ${res.statusCode}', url);
    }
    yield* res.stream;
  }
}
