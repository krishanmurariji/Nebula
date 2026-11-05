import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'resolved_stream.dart';

/// Default backup instances. Public instances come and go, so the list is
/// user-editable (Settings → Backup Sources) and dead ones are skipped
/// automatically.
const List<String> kDefaultBackupInstances = [
  'https://pipedapi.kavin.rocks',
  'https://yewtu.be',
];

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
    for (final raw in bases) {
      final base = raw.trim().replaceAll(RegExp(r'/+$'), '');
      if (base.isEmpty) continue;
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

    var size = c.size;
    if (size == null || size <= 0) {
      final head = await _client.head(url).timeout(perInstanceTimeout);
      size = int.tryParse(head.headers['content-length'] ?? '');
    }
    if (size == null || size <= 0) return null;

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
