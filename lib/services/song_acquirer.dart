import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'audio_cache.dart';
import 'http_range_download.dart';
import 'playback_failure.dart';
import 'progressive_download.dart';
import 'resolved_stream.dart';
import 'stream_resolver.dart';

/// The caller moved on (skipped, changed song): abandon quietly.
class AcquireSuperseded implements Exception {
  const AcquireSuperseded();
  @override
  String toString() => 'AcquireSuperseded';
}

/// No stream could be found for the video.
class ResolveFailure implements Exception {
  const ResolveFailure(this.kind);
  final FailureKind kind;
  @override
  String toString() => 'ResolveFailure($kind)';
}

/// A stream was found but could not be downloaded.
class DownloadFailure implements Exception {
  const DownloadFailure(this.client, this.cause);
  final int client;
  final Object cause;
  @override
  String toString() => 'DownloadFailure(client $client): $cause';
}

/// Where the player can get the song from: a local file (preferred) or, when
/// that is not possible, a URL it streams itself.
class AcquiredSong {
  const AcquiredSong.file(this.file, {this.fromCache = false})
      : url = null,
        headers = const {};
  const AcquiredSong.stream(this.url, {this.headers = const {}})
      : file = null,
        fromCache = false;

  final File? file;
  final Uri? url;
  final Map<String, String> headers;
  final bool fromCache;
}

/// Turns a video id into something playable, as reliably as possible:
///
///  1. the disk cache (instant, works offline);
///  2. resolve a stream, download the whole song (plain ranged request with the
///     right User-Agent first, the library's downloader as a fallback) and put
///     it in the cache;
///  3. if the song is too big or the disk cannot store it, hand the player the
///     URL to stream itself.
///
/// Every step can be abandoned the moment the caller moves on, and no failure
/// leaves a download running.
class SongAcquirer {
  SongAcquirer({
    required this.resolver,
    required this.cache,
    this.httpClient,
    this.stallTimeout = const Duration(seconds: 10),
    this.maxDownloadFirstBytes = 40 * 1024 * 1024,
    this.log,
  });

  final StreamResolver<ResolvedStream> resolver;

  /// Looked up on every call: the cache is created asynchronously at start-up
  /// and may never become available (no usable disk).
  final AudioCache? Function() cache;
  final http.Client? httpClient;
  final Duration stallTimeout;
  final int maxDownloadFirstBytes;
  final void Function(String message)? log;

  ProgressiveDownload? _active;
  ProgressiveDownload? _prefetch;

  /// Stops the download for the song being loaded (the user moved on).
  void cancelActive() {
    _active?.cancel();
    _active = null;
  }

  /// Stops a background prefetch.
  void cancelPrefetch() {
    _prefetch?.cancel();
    _prefetch = null;
  }

  void cancelAll() {
    cancelActive();
    cancelPrefetch();
  }

  /// Completes when the current song's download has ended (either way).
  Future<void> activeSettled() async {
    final a = _active;
    if (a == null) return;
    await a.completed.then((_) {}, onError: (Object _) {});
  }

  Future<AcquiredSong> acquire(
    String videoId, {
    required Future<void> superseded,
    Set<String> protect = const {},
  }) async {
    final store = cache();

    final cached = await store?.lookup(videoId);
    if (cached != null) return AcquiredSong.file(cached, fromCache: true);

    final res = await resolver.resolve(videoId, superseded: superseded);
    final info = res.value;
    if (info == null) {
      if (res.kind == FailureKind.cancelled) throw const AcquireSuperseded();
      throw ResolveFailure(res.kind);
    }

    final canDownload = store != null &&
        info.totalBytes > 0 &&
        info.totalBytes <= maxDownloadFirstBytes;
    if (!canDownload) {
      log?.call('streaming directly from URL');
      return _stream(info);
    }

    log?.call('downloading ${info.totalBytes} bytes via ${info.origin} '
        '(client ${info.clientIndex})');
    final bytes = await _downloadBytes(info, superseded, prefetch: false);

    await store.put(videoId, bytes, protect: protect);
    final stored = await store.lookup(videoId);
    if (stored != null) {
      log?.call('ready: ${bytes.length} bytes');
      return AcquiredSong.file(stored);
    }
    // Disk full / unwritable: the download was fine, so do NOT blame the
    // client. Let the player stream the URL instead.
    log?.call('could not store the song on disk; streaming from URL');
    return _stream(info);
  }

  /// Downloads [videoId] into the cache in the background. Returns true when
  /// the song is (now) cached. Never throws; cancelled by [cancelPrefetch].
  Future<bool> prefetch(String videoId,
      {Set<String> protect = const {}}) async {
    final store = cache();
    if (store == null) return false;
    if (store.contains(videoId)) return true;
    try {
      final res = await resolver.resolve(videoId);
      final info = res.value;
      if (info == null ||
          info.totalBytes <= 0 ||
          info.totalBytes > maxDownloadFirstBytes) {
        return false;
      }
      final bytes = await _downloadBytes(info, Completer<void>().future,
          prefetch: true);
      await store.put(videoId, bytes, protect: protect);
      return store.contains(videoId);
    } catch (e) {
      log?.call('prefetch skipped: $e');
      return false;
    }
  }

  AcquiredSong _stream(ResolvedStream info) => AcquiredSong.stream(
        info.url,
        headers: info.userAgent == null
            ? const {}
            : {'User-Agent': info.userAgent!},
      );

  /// Two strategies, in order. Throws [AcquireSuperseded] or [DownloadFailure].
  Future<Uint8List> _downloadBytes(ResolvedStream info, Future<void> superseded,
      {required bool prefetch}) async {
    Object? directError;
    try {
      return await _download(
        () => openRangedDownload(info.url, info.totalBytes,
            userAgent: info.userAgent, client: httpClient),
        info.totalBytes,
        superseded,
        prefetch: prefetch,
      );
    } on AcquireSuperseded {
      rethrow;
    } catch (e) {
      directError = e;
      log?.call('direct download failed: $e');
    }
    try {
      return await _download(info.open, info.totalBytes, superseded,
          prefetch: prefetch);
    } on AcquireSuperseded {
      rethrow;
    } catch (e) {
      log?.call('library download failed: $e');
      throw DownloadFailure(
          info.clientIndex, 'direct: $directError; library: $e');
    }
  }

  Future<Uint8List> _download(
    Stream<List<int>> Function() open,
    int total,
    Future<void> superseded, {
    required bool prefetch,
  }) async {
    final dl = ProgressiveDownload(
      open: open,
      totalBytes: total,
      stallTimeout: stallTimeout,
    );
    if (prefetch) {
      _prefetch = dl;
    } else {
      _active = dl;
    }
    dl.start();
    try {
      return await Future.any<Uint8List>([
        dl.completed,
        superseded.then<Uint8List>((_) => throw const AcquireSuperseded()),
      ]);
    } catch (e) {
      final wasCancelled = dl.isCancelled;
      dl.cancel();
      if (e is AcquireSuperseded || wasCancelled) {
        throw const AcquireSuperseded();
      }
      rethrow;
    }
  }
}
