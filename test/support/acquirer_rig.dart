import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nebula_music_player/services/audio_cache.dart';
import 'package:nebula_music_player/services/playback_failure.dart';
import 'package:nebula_music_player/services/resolved_stream.dart';
import 'package:nebula_music_player/services/song_acquirer.dart';
import 'package:nebula_music_player/services/stream_resolver.dart';

// Named like the real library's exceptions: the classifier recognises them by name.
class RequestLimitExceededException implements Exception {}

class VideoUnavailableException implements Exception {}

const total = 20000;
/// Deterministic bytes that look like an mp4 ("ftyp" at offset 4), so the
/// self-test's "is this real audio" check can pass.
Uint8List fileBytes([int n = total]) {
  final b = Uint8List.fromList(List.generate(n, (i) => i % 251));
  if (n >= 8) b.setRange(4, 8, [0x66, 0x74, 0x79, 0x70]);
  return b;
}

enum B { ok, status403, stall, truncated, oversize, error, slow }

/// A cache whose writes silently fail, like a full disk.
class FullDiskCache extends AudioCache {
  FullDiskCache(super.dir);
  @override
  Future<void> put(String id, Uint8List bytes, {Set<String> protect = const {}}) async {}
}

class Rig {
  Rig({
    this.direct = B.ok,
    this.library = B.ok,
    this.size = total,
    this.cacheBuilder,
    this.resolveKind,
    this.slowMs = 300,
  });

  final B direct, library;
  final int size;
  final AudioCache Function(Directory)? cacheBuilder;
  final FailureKind? resolveKind;
  final int slowMs;

  late final Directory root;
  late final AudioCache cache;
  AudioCache? cacheForAcquirer;
  int resolverCalls = 0, directCalls = 0, libraryCalls = 0;
  final logs = <String>[];
  late final SongAcquirer acquirer;
  bool noCache = false;

  Future<void> init() async {
    root = await Directory.systemTemp.createTemp('nebula_acq');
    cache = (cacheBuilder ?? (d) => AudioCache(d))(Directory('${root.path}/c'));
    await cache.init();
    final resolver = StreamResolver<ResolvedStream>(
      timeouts: const [Duration(seconds: 5)],
      minGap: Duration.zero,
      fetch: (id, c) async {
        resolverCalls++;
        final k = resolveKind;
        if (k != null) {
          switch (k) {
            case FailureKind.rateLimited:
              throw RequestLimitExceededException();
            case FailureKind.network:
              throw Exception('SocketException: Failed host lookup');
            case FailureKind.permanent:
              throw VideoUnavailableException();
            default:
              throw Exception('boom');
          }
        }
        return ResolvedStream(
          url: Uri.parse('https://rr1---sn-x.googlevideo.com/videoplayback?sig=S'),
          totalBytes: size,
          mimeType: 'audio/mp4',
          open: _libraryStream,
          clientIndex: 3,
          userAgent: 'com.google.android.youtube/20 (Linux; U; Android 11) gzip',
        );
      },
    );
    acquirer = SongAcquirer(
      resolver: resolver,
      cache: () => noCache ? null : cache,
      httpClient: _directClient(),
      stallTimeout: const Duration(milliseconds: 120),
      maxDownloadFirstBytes: 1000000,
      log: logs.add,
    );
  }

  Future<void> dispose() async {
    acquirer.cancelAll();
    await root.delete(recursive: true);
  }

  Stream<List<int>> _libraryStream() {
    libraryCalls++;
    final data = fileBytes(total);
    switch (library) {
      case B.ok:
        return Stream.fromIterable([for (var i = 0; i < data.length; i += 4000) data.sublist(i, min(i + 4000, data.length))]);
      case B.slow:
        return Stream.fromFuture(Future.delayed(Duration(milliseconds: slowMs), () => data));
      case B.status403:
        return Stream.error(Exception('FatalFailureException (403)'));
      case B.error:
        return Stream.error(const SocketException('connection reset'));
      case B.truncated:
        return Stream.value(data.sublist(0, 5000));
      case B.oversize:
        return Stream.value(fileBytes(total + 5000));
      case B.stall:
        final c = StreamController<List<int>>();
        c.add(data.sublist(0, 1000));
        return c.stream; // never ends
    }
  }

  http.Client _directClient() {
    return MockClient.streaming((req, body) async {
      directCalls++;
      final data = fileBytes(total);
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(req.headers['Range'] ?? '');
      final start = m == null ? 0 : int.parse(m[1]!);
      final end = m == null ? data.length - 1 : min(int.parse(m[2]!), data.length - 1);
      http.StreamedResponse ok(List<int> b) => http.StreamedResponse(Stream.value(b), 206, request: req);
      switch (direct) {
        case B.ok:
          return ok(data.sublist(start, end + 1));
        case B.slow:
          await Future<void>.delayed(Duration(milliseconds: slowMs));
          return ok(data.sublist(start, end + 1));
        case B.status403:
          return http.StreamedResponse(const Stream.empty(), 403, request: req);
        case B.error:
          throw const SocketException('Failed host lookup');
        case B.truncated:
          return ok(start == 0 ? data.sublist(0, 5000) : const <int>[]);
        case B.oversize:
          return ok(fileBytes(total + 5000));
        case B.stall:
          final c = StreamController<List<int>>();
          c.add(data.sublist(0, 1000));
          return http.StreamedResponse(c.stream, 206, request: req);
      }
    });
  }

  Future<AcquiredSong> acquire({Future<void>? superseded}) => acquirer.acquire(
        'dQw4w9WgXcQ',
        superseded: superseded ?? Completer<void>().future,
      );
}

Future<void> withRig(Rig rig, Future<void> Function(Rig) body) async {
  await rig.init();
  try {
    await body(rig);
  } finally {
    await rig.dispose();
  }
}

