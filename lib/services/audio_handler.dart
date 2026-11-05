import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';
import 'latest_wins_runner.dart';
import 'playback_failure.dart';

final audioHandlerProvider =
    Provider<NebulaAudioHandler>((ref) => throw UnimplementedError());

const _kMaxCacheBytes = 500 * 1024 * 1024; // 500 MB

// ── How long a fetched manifest URL is considered fresh. ─────────────────────
// YouTube URLs are typically valid for ~6h, but we use 5 min to be safe.
// If a URL expires mid-play the error handler will invalidate and re-fetch.
const _kManifestTtl = Duration(minutes: 5);

// ── Disk-cache entry ──────────────────────────────────────────────────────────
class _CE {
  final String id;
  final int sz;
  int ts;
  _CE(this.id, this.sz, this.ts);
  Map toJson() => {'id': id, 'sz': sz, 'ts': ts};
  factory _CE.fromJson(Map j) =>
      _CE(j['id'] as String, j['sz'] as int, j['ts'] as int);
}

// ── Play mode ─────────────────────────────────────────────────────────────────
// repeatAll  — wraps around when queue ends (default)
// repeatOne  — replays the same song forever
// shuffle    — picks a random song on every advance
// sequential — plays to end of queue then stops
enum PlayMode { repeatAll, repeatOne, shuffle, sequential }

// ── In-memory manifest cache entry ───────────────────────────────────────────
class _ManifestEntry {
  final AudioStreamInfo info;
  final DateTime fetchedAt;
  _ManifestEntry(this.info) : fetchedAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) > _kManifestTtl;
}

class _LoadRequest {
  final Song song;
  final int tok;
  final Duration? resumeAt;
  final int attempt;
  const _LoadRequest(this.song, this.tok, this.resumeAt, this.attempt);
}

class _FetchResult {
  final AudioStreamInfo? info;
  final FailureKind kind; // meaningful only when info == null
  const _FetchResult(this.info, this.kind);
}

class _StreamResolveException implements Exception {
  final FailureKind kind;
  const _StreamResolveException(this.kind);
  @override
  String toString() => 'StreamResolveException($kind)';
}

class _SupersededException implements Exception {
  const _SupersededException();
}

class NebulaAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final YoutubeExplode _yt = YoutubeExplode();

  Song? _current;
  List<Song> _queue = [];
  int _idx = 0;
  int _tok = 0;

  // Current play mode — changed by the UI via setPlayMode().
  PlayMode _playMode = PlayMode.repeatAll;

  Directory? _cacheDir;
  final Map<String, _CE> _index = {};
  final Completer<void> _cacheReadyCompleter = Completer<void>();

  // ── In-memory manifest URL cache ─────────────────────────────────────────
  // Keyed by videoId. Populated by _getInfo and eager prefetch.
  // Checked before hitting the network — makes skip/play near-instant
  // when the next song was prefetched while the current one was playing.
  final Map<String, _ManifestEntry> _manifestCache = {};

  // ── Rate-limit state ──────────────────────────────────────────────────────
  final Map<int, DateTime> _clientCooldownUntil = {};
  final Map<int, int> _clientFailCount = {};

  // androidVr first — bypasses IP-level blocks that hit android/ios/mweb.
  static final _clients = [
    YoutubeApiClient.androidVr,
    YoutubeApiClient.android,
    YoutubeApiClient.ios,
    YoutubeApiClient.mweb,
  ];

  static const _timeouts = [
    Duration(seconds: 20),
    Duration(seconds: 12),
    Duration(seconds: 12),
    Duration(seconds: 12),
  ];

  // ── Load pipeline state ───────────────────────────────────────────────────
  // All loads go through this runner: one at a time, newest request wins.
  // The native player therefore never sees overlapping stop()/setAudioSource().
  late final LatestWinsRunner<_LoadRequest> _runner =
      LatestWinsRunner<_LoadRequest>(_runLoad);

  Timer? _retryTimer;
  int _consecutiveFailures = 0; // songs in a row that failed (reset on success/user action)
  int _midPlayRetries = 0;      // mid-song recoveries for the current song
  int _completedTok = -1;       // guards against double "completed" events

  final StreamController<String> _notices = StreamController.broadcast();

  /// Short human-readable messages ("Skipped unavailable song") for the UI.
  Stream<String> get notices => _notices.stream;

  /// Fired whenever the queue or its index is changed by the handler itself.
  final StreamController<void> _queueChanged = StreamController.broadcast();
  Stream<void> get queueChanges => _queueChanged.stream;

  NebulaAudioHandler() {
    _player.playbackEventStream.listen(
      _broadcast,
      onError: (Object e, StackTrace st) => _onPlayerError(e),
    );
    _player.processingStateStream.listen((s) {
      // Song finished by itself. Ignore while a load is running, and make sure
      // one finished song can only advance the queue once.
      if (s == ProcessingState.completed &&
          !_runner.isBusy &&
          _completedTok != _tok) {
        _completedTok = _tok;
        skipToNext();
      }
    });

    _initCache();
  }

  // ── Error from the native player while a song is (or should be) playing ──
  // Typically an expired/throttled stream URL. Re-resolve and resume from the
  // same position a couple of times, then give up on the song and skip it.
  void _onPlayerError(Object e) {
    final kind = classifyPlaybackError(e);
    debugPrint('[N] player error ($kind): $e');
    if (kind == FailureKind.cancelled) return;
    // A load in progress reports its own failures through exceptions.
    if (_runner.isBusy) return;

    final song = _current;
    if (song == null) return;

    if (kind != FailureKind.permanent && _midPlayRetries < 2) {
      _midPlayRetries++;
      _manifestCache.remove(song.videoId);
      _requestLoad(song, resumeAt: _player.position);
    } else {
      _giveUpOnCurrent(song, kind);
    }
  }

  // ── Cache init ────────────────────────────────────────────────────────────

  void _initCache() async {
    try {
      final candidates = <String>[];
      final tmp = Platform.environment['TMPDIR'] ?? '';
      if (tmp.isNotEmpty) {
        candidates.add(
            tmp.replaceAll(RegExp(r'[/\\]cache$'), '/files/nebula_cache'));
        candidates.add('$tmp/nebula_cache');
      }
      candidates.addAll([
        '/data/data/com.nebula.nebula_music_player/files/nebula_cache',
        '/data/user/0/com.nebula.nebula_music_player/files/nebula_cache',
        '${Directory.systemTemp.path}/nebula_cache',
      ]);
      for (final path in candidates) {
        try {
          final d = Directory(path);
          await d.create(recursive: true);
          final t = File('$path/.test');
          t.writeAsStringSync('ok');
          t.deleteSync();
          _cacheDir = d;
          debugPrint('[N] cache: $path');
          break;
        } catch (_) {}
      }
      _cacheDir ??= Directory.systemTemp;
      final idx = File('${_cacheDir!.path}/index.json');
      if (idx.existsSync()) {
        try {
          final raw = jsonDecode(idx.readAsStringSync()) as List;
          for (final e in raw) {
            final ce = _CE.fromJson(e as Map);
            if (File('${_cacheDir!.path}/${ce.id}.mp4').existsSync()) {
              _index[ce.id] = ce;
            }
          }
          debugPrint('[N] index: ${_index.length} songs');
        } catch (_) {}
      }
    } catch (e) {
      _cacheDir = Directory.systemTemp;
    } finally {
      if (!_cacheReadyCompleter.isCompleted) _cacheReadyCompleter.complete();
    }
  }

  void _saveIndex() {
    try {
      File('${_cacheDir!.path}/index.json').writeAsStringSync(
          jsonEncode(_index.values.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  File _cf(String id) => File('${_cacheDir!.path}/$id.mp4');
  File _tf(String id) => File('${_cacheDir!.path}/$id.tmp');

  bool _isCached(String id) {
    final f = _cf(id);
    return _index.containsKey(id) && f.existsSync() && f.lengthSync() > 4096;
  }

  void _markUsed(String id) {
    _index[id]?.ts = DateTime.now().millisecondsSinceEpoch;
    _saveIndex();
  }

  void _evict() {
    int total = _index.values.fold(0, (s, e) => s + e.sz);
    if (total <= _kMaxCacheBytes) return;
    final sorted = _index.values.toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));
    for (final e in sorted) {
      if (e.id == _current?.videoId) continue; // never delete what is playing
      if (total <= (_kMaxCacheBytes * 0.8).toInt()) break;
      try {
        _cf(e.id).deleteSync();
        total -= e.sz;
        _index.remove(e.id);
      } catch (_) {}
    }
    _saveIndex();
  }

  Future<void> _ensureCache() async {
    await _cacheReadyCompleter.future
        .timeout(const Duration(seconds: 5), onTimeout: () {});
    _cacheDir ??= Directory.systemTemp;
  }

  // ── Public getters ────────────────────────────────────────────────────────

  Song? get currentSong => _current;
  List<Song> get songQueue => List.unmodifiable(_queue);
  int get queueIndex => _idx;
  int get songQueueIndex => _idx;
  AudioPlayer get player => _player;
  int get cachedSongCount => _index.length;
  int get cacheSizeBytes => _index.values.fold(0, (s, e) => s + e.sz);
  PlayMode get playMode => _playMode;

  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    debugPrint('[N] playMode → $mode');
  }

  // ── Rate-limit helpers ────────────────────────────────────────────────────

  Duration _backoffFor(int clientIndex) {
    final n = _clientFailCount[clientIndex] ?? 0;
    final secs = min(4 * pow(2, n).toInt(), 60);
    return Duration(seconds: secs);
  }

  void _markClientRateLimited(int clientIndex) {
    final count = (_clientFailCount[clientIndex] ?? 0) + 1;
    _clientFailCount[clientIndex] = count;
    final cooldown = _backoffFor(clientIndex);
    _clientCooldownUntil[clientIndex] = DateTime.now().add(cooldown);
    debugPrint(
        '[N] client=$clientIndex rate-limited → backoff ${cooldown.inSeconds}s (fail #$count)');
  }

  void _markClientSuccess(int clientIndex) {
    _clientFailCount.remove(clientIndex);
    _clientCooldownUntil.remove(clientIndex);
  }

  bool _clientIsOnCooldown(int clientIndex) {
    final until = _clientCooldownUntil[clientIndex];
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  int get globalCooldownSeconds {
    final now = DateTime.now();
    for (int i = 0; i < _clients.length; i++) {
      if (!_clientIsOnCooldown(i)) return 0;
    }
    int minRemaining = 999;
    for (int i = 0; i < _clients.length; i++) {
      final until = _clientCooldownUntil[i];
      if (until != null) {
        final remaining = until.difference(now).inSeconds;
        if (remaining < minRemaining) minRemaining = remaining;
      }
    }
    return max(0, minRemaining);
  }

  // ── Play / Load ───────────────────────────────────────────────────────────

  Future<void> playSong(Song song, {List<Song>? queue, int index = 0}) {
    if (queue != null && queue.isNotEmpty) {
      _queue = List.from(queue);
      _idx = index.clamp(0, queue.length - 1);
    } else if (!_queue.contains(song)) {
      _queue.add(song);
      _idx = _queue.length - 1;
    } else {
      _idx = _queue.indexOf(song);
    }
    _resetFailureCounters();
    _requestLoad(song);
    _queueChanged.add(null);
    return _runner.idle;
  }

  void _resetFailureCounters() {
    _consecutiveFailures = 0;
    _midPlayRetries = 0;
  }

  /// Entry point for every load. Synchronous and cheap: it only records the
  /// request and publishes the new song to the UI immediately.
  void _requestLoad(Song song, {Duration? resumeAt, int attempt = 0}) {
    final tok = ++_tok;
    _retryTimer?.cancel();
    _current = song;

    playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: false,
        queueIndex: _idx));
    mediaItem.add(MediaItem(
      id: song.videoId,
      title: song.title,
      artist: song.artist,
      artUri:
          song.thumbnailUrl.isNotEmpty ? Uri.tryParse(song.thumbnailUrl) : null,
    ));

    _runner.submit(_LoadRequest(song, tok, resumeAt, attempt));
  }

  /// Runs on the single worker. Never overlaps with another load.
  Future<void> _runLoad(_LoadRequest req, RunContext ctx) async {
    final song = req.song;
    bool live() => ctx.isCurrent && _tok == req.tok;
    var usedDiskCache = false;

    try {
      debugPrint('[N] ▶ ${song.title} (attempt ${req.attempt})');
      try {
        await _player.stop();
      } catch (e) {
        debugPrint('[N] stop() before load ignored: $e');
      }
      if (!live()) return;

      await _ensureCache();
      if (!live()) return;

      final AudioSource source;
      AudioStreamInfo? info;

      if (_isCached(song.videoId)) {
        usedDiskCache = true;
        _markUsed(song.videoId);
        source = AudioSource.file(_cf(song.videoId).path);
      } else {
        final cached = _manifestCache[song.videoId];
        if (cached != null && !cached.isExpired) {
          info = cached.info;
        } else {
          final res = await _getInfo(song.videoId, req.tok,
              superseded: ctx.superseded);
          if (!live()) return;
          info = res.info;
          if (info == null) {
            throw _StreamResolveException(res.kind);
          }
        }
        source = AudioSource.uri(info.url);
      }

      await _player.setAudioSource(source, initialPosition: req.resumeAt);
      if (!live()) return;

      // IMPORTANT: play() only completes when playback pauses or ends, so it
      // must NOT be awaited here or the worker would be blocked for the whole
      // song and skipping would stall.
      unawaited(_player.play().catchError((Object e) {
        if (live()) _onPlayerError(e);
      }));

      _consecutiveFailures = 0;
      debugPrint('[N] ✓ started: ${song.title}');

      if (info != null) _cacheInBackground(info, song.videoId, req.tok);
      _scheduleNextPrefetch(req.tok);
    } catch (e, st) {
      if (!live()) return; // superseded: whatever happened is irrelevant now
      var kind =
          e is _StreamResolveException ? e.kind : classifyPlaybackError(e);
      debugPrint('[N] load failed ($kind): $e\n$st');
      if (kind == FailureKind.cancelled) kind = FailureKind.transient;
      if (usedDiskCache) _dropFromCache(song.videoId); // maybe corrupt
      _handleLoadFailure(req, kind);
    }
  }

  // ── Failure policy ────────────────────────────────────────────────────────
  // permanent    → skip the song right away
  // rateLimited  → stop and surface the countdown (retrying now makes it worse)
  // transient    → retry with backoff (max 2 retries), then skip
  void _handleLoadFailure(_LoadRequest req, FailureKind kind) {
    final song = req.song;
    _manifestCache.remove(song.videoId);

    if (kind == FailureKind.rateLimited) {
      _setError();
      return;
    }
    if (kind == FailureKind.transient && req.attempt < 2) {
      final delay = retryDelay(req.attempt);
      debugPrint('[N] retry in ${delay.inMilliseconds}ms');
      final tok = req.tok;
      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () {
        // Only retry if nothing newer has happened in the meantime.
        if (_tok == tok && _current == song) {
          _requestLoad(song, resumeAt: req.resumeAt, attempt: req.attempt + 1);
        }
      });
      return;
    }
    _giveUpOnCurrent(song, kind);
  }

  /// The current song cannot be played: move on instead of showing a dead end.
  void _giveUpOnCurrent(Song song, FailureKind kind) {
    _consecutiveFailures++;
    final canSkip = _queue.length > 1 &&
        _consecutiveFailures < min(_queue.length, 5);
    if (canSkip && _advance(forced: true)) {
      _notices.add('Skipped "${song.title}" — unavailable');
      _midPlayRetries = 0;
      _requestLoad(_queue[_idx]);
      _queueChanged.add(null);
    } else {
      _notices.add('Could not play "${song.title}"');
      _setError();
    }
  }

  void _setError() {
    playbackState.add(playbackState.value
        .copyWith(processingState: AudioProcessingState.error, playing: false));
  }

  void _dropFromCache(String id) {
    try {
      _cf(id).deleteSync();
    } catch (_) {}
    _index.remove(id);
    _saveIndex();
  }

  void _cacheInBackground(AudioStreamInfo info, String videoId, int tok) {
    Future.microtask(() async {
      try {
        await _download(info, videoId, tok);
        debugPrint('[N] bg cache done: $videoId');
      } catch (e) {
        debugPrint('[N] bg cache err: $e');
      }
    });
  }

  // ── Manifest fetch with per-client exponential backoff ───────────────────

  Future<_FetchResult> _getInfo(String videoId, int tok,
      {Future<void>? superseded}) async {
    if (_tok != tok) return const _FetchResult(null, FailureKind.cancelled);

    final existing = _manifestCache[videoId];
    if (existing != null && !existing.isExpired) {
      return _FetchResult(existing.info, FailureKind.transient);
    }

    debugPrint('[N] manifest fetch for $videoId');
    var sawPermanent = false;

    for (int pass = 0; pass < 2; pass++) {
      for (int ci = 0; ci < _clients.length; ci++) {
        if (_tok != tok) return const _FetchResult(null, FailureKind.cancelled);

        if (_clientIsOnCooldown(ci)) {
          final remaining =
              _clientCooldownUntil[ci]!.difference(DateTime.now()).inSeconds;
          debugPrint('[N] client=$ci skipped (cooldown ${remaining}s)');
          continue;
        }

        try {
          debugPrint('[N] manifest client=$ci for $videoId');
          final fetch = _yt.videos.streamsClient
              .getManifest(videoId, ytClients: [_clients[ci]])
              .timeout(_timeouts[ci]);
          // Race against "user moved on" so a slow client never delays the
          // next song by up to its full timeout.
          final m = superseded == null
              ? await fetch
              : await Future.any<StreamManifest>([
                  fetch,
                  superseded.then<StreamManifest>(
                      (_) => throw const _SupersededException()),
                ]);

          if (m.audioOnly.isEmpty) {
            debugPrint('[N] client=$ci no audio streams, trying next');
            continue;
          }

          // Lowest-bitrate mp4 (AAC) first: fastest start, smallest download.
          final mp4 = m.audioOnly
              .where((s) => s.codec.mimeType.contains('mp4'))
              .toList()
            ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
          final chosen = mp4.isNotEmpty
              ? mp4.first
              : (m.audioOnly.toList()
                    ..sort((a, b) => a.bitrate.compareTo(b.bitrate)))
                  .first;

          debugPrint(
              '[N] ✓ manifest ok client=$ci ${chosen.codec.mimeType} @ ${chosen.bitrate}');
          _markClientSuccess(ci);
          _manifestCache[videoId] = _ManifestEntry(chosen);
          return _FetchResult(chosen, FailureKind.transient);
        } on _SupersededException {
          return const _FetchResult(null, FailureKind.cancelled);
        } on RequestLimitExceededException {
          _markClientRateLimited(ci);
        } on TimeoutException {
          debugPrint('[N] client=$ci timeout, trying next');
        } catch (e) {
          final kind = classifyPlaybackError(e);
          debugPrint('[N] client=$ci error ($kind): $e');
          if (kind == FailureKind.permanent) sawPermanent = true;
          if (kind == FailureKind.rateLimited) {
            _markClientRateLimited(ci);
            }
        }
      }

      // A permanent verdict ("video unavailable") will not change on retry.
      if (sawPermanent) break;

      if (pass == 0) {
        final now = DateTime.now();
        var anyAvailableNow = false;
        Duration? shortestWait;
        for (int ci = 0; ci < _clients.length; ci++) {
          final until = _clientCooldownUntil[ci];
          if (until == null || now.isAfter(until)) {
            anyAvailableNow = true;
            break;
          }
          final wait = until.difference(now);
          if (shortestWait == null || wait < shortestWait) shortestWait = wait;
        }

        if (anyAvailableNow) continue;

        if (shortestWait != null && shortestWait.inSeconds <= 30) {
          debugPrint('[N] all clients on cooldown, waiting ${shortestWait.inSeconds}s');
          for (int s = 0; s < shortestWait.inSeconds + 1; s++) {
            if (_tok != tok) return const _FetchResult(null, FailureKind.cancelled);
            await Future.delayed(const Duration(seconds: 1));
          }
        } else {
          debugPrint('[N] all clients need >30s cooldown, aborting');
          break;
        }
      }
    }

    debugPrint('[N] all clients failed for $videoId');
    if (sawPermanent) return const _FetchResult(null, FailureKind.permanent);
    // Every client throttled → wait it out; otherwise treat as a transient failure.
    return _FetchResult(
        null,
        globalCooldownSeconds > 0
            ? FailureKind.rateLimited
            : FailureKind.transient);
  }

  // ── Download ──────────────────────────────────────────────────────────────

  Future<File?> _download(
      AudioStreamInfo info, String videoId, int tok) async {
    final dest = _cf(videoId);
    final tmp = _tf(videoId);
    if (tmp.existsSync()) tmp.deleteSync();

    IOSink? sink;
    StreamSubscription<List<int>>? sub;
    try {
      sink = tmp.openWrite();
      int bytes = 0;
      final totalKB = (info.size.totalBytes / 1024).toStringAsFixed(0);
      debugPrint('[N] downloading $totalKB KB...');

      final comp = Completer<void>();
      final timer = Timer(const Duration(seconds: 180), () {
        if (!comp.isCompleted) {
          comp.completeError(TimeoutException('download timeout 180s'));
        }
      });

      sub = _yt.videos.streamsClient.get(info).listen(
        (chunk) {
          if (_tok != tok) {
            sub?.cancel();
            if (!comp.isCompleted) comp.complete();
            return;
          }
          sink?.add(chunk);
          bytes += chunk.length;
          if (bytes % (512 * 1024) < chunk.length) {
            debugPrint(
                '[N] dl ${(bytes / 1024).toStringAsFixed(0)}/$totalKB KB');
          }
        },
        onDone: () {
          if (!comp.isCompleted) comp.complete();
        },
        onError: (Object e, StackTrace st) {
          debugPrint('[N] stream error: $e');
          if (!comp.isCompleted) comp.completeError(e, st);
        },
        cancelOnError: true,
      );

      await comp.future;
      timer.cancel();
      sub = null;

      if (_tok != tok) {
        if (sink != null) {
          try {
            await sink.close();
          } catch (_) {}
        }
        _del(tmp);
        return null;
      }

      debugPrint('[N] flushing $bytes bytes...');
      await sink!.flush();
      await sink!.close();
      sink = null;

      if (bytes < 1024) throw Exception('file too small: $bytes bytes');

      final result = await tmp.rename(dest.path);
      debugPrint('[N] ✓ saved $bytes bytes → ${result.path}');
      _index[videoId] =
          _CE(videoId, bytes, DateTime.now().millisecondsSinceEpoch);
      _saveIndex();
      _evict();
      return result;
    } on TimeoutException catch (e) {
      debugPrint('[N] dl timeout: $e');
      sub?.cancel();
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      _del(tmp);
      rethrow;
    } on RequestLimitExceededException catch (e) {
      debugPrint('[N] dl rate limit: $e');
      sub?.cancel();
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      _del(tmp);
      rethrow;
    } catch (e, st) {
      debugPrint('[N] dl error: $e\n$st');
      sub?.cancel();
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      _del(tmp);
      rethrow;
    }
  }

  void _del(File? f) {
    try {
      f?.deleteSync();
    } catch (_) {}
  }

  // ── Next-song prefetch ────────────────────────────────────────────────────
  //
  // Two-phase approach:
  //   Phase 1 (5s after current song starts): fetch manifest URL only.
  //            Stored in _manifestCache — makes the next skip near-instant.
  //   Phase 2 (immediately after Phase 1): download the file in background.
  //            If already disk-cached, skip both phases.
  //
  // The 5s delay ensures the current song's manifest fetch + stream start
  // completes first, so we never fire concurrent manifest requests (which
  // triggers YouTube rate limiting).

  void _scheduleNextPrefetch(int ptok) {
    if (_queue.length < 2) return;
    final next = _queue[(_idx + 1) % _queue.length];
    if (_isCached(next.videoId)) {
      debugPrint('[N] next song already disk-cached, skipping prefetch');
      return;
    }
    final manifestAlreadyCached = _manifestCache[next.videoId];
    if (manifestAlreadyCached != null && !manifestAlreadyCached.isExpired) {
      // Manifest already in memory — just kick off the background download.
      debugPrint('[N] next manifest already cached, scheduling bg download');
      Future.delayed(const Duration(seconds: 5), () async {
        if (_tok != ptok) return;
        if (_isCached(next.videoId)) return;
        try {
          await _download(manifestAlreadyCached.info, next.videoId, ptok);
          if (_tok == ptok) debugPrint('[N] prefetch download done: ${next.title}');
        } catch (e) {
          debugPrint('[N] prefetch download err: $e');
        }
      });
      return;
    }

    debugPrint('[N] prefetch queued (5s): ${next.title}');
    Future.delayed(const Duration(seconds: 5), () async {
      if (_tok != ptok) return;
      if (_isCached(next.videoId)) return;

      // Phase 1: Fetch and cache the manifest URL.
      debugPrint('[N] prefetch manifest start: ${next.title}');
      AudioStreamInfo? info;
      try {
        // Use a special "prefetch token" check: we pass ptok so the fetch
        // aborts if the user skips. _getInfo already checks _tok == tok.
        info = (await _getInfo(next.videoId, ptok)).info;
      } catch (e) {
        debugPrint('[N] prefetch manifest err: $e');
        return;
      }
      if (info == null || _tok != ptok) return;
      debugPrint('[N] prefetch manifest done: ${next.title}');
      // _manifestCache is now populated by _getInfo — next play is instant.

      // Phase 2: Download to disk in background.
      if (_isCached(next.videoId)) return;
      try {
        await _download(info, next.videoId, ptok);
        if (_tok == ptok) debugPrint('[N] prefetch download done: ${next.title}');
      } catch (e) {
        debugPrint('[N] prefetch download err: $e');
      }
    });
  }

  // ── Cache management ──────────────────────────────────────────────────────

  Future<void> clearCache() async {
    try {
      for (final f in _cacheDir!.listSync().whereType<File>()) {
        f.deleteSync();
      }
      _index.clear();
      _manifestCache.clear();
    } catch (_) {}
  }

  // ── AudioHandler overrides ────────────────────────────────────────────────

  @override
  Future<void> play() async {
    // just_audio's play() completes only when playback pauses/ends; don't await.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration p) => _player.seek(p);

  @override
  Future<void> stop() async {
    _tok++;
    _runner.cancel();
    _retryTimer?.cancel();
    try {
      await _player.stop();
    } catch (_) {}
    playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle, playing: false));
  }

  /// Moves [_idx] to the next song according to [_playMode].
  /// Returns false when there is nothing to advance to (end of a sequential queue).
  /// [forced] is used after a failure: repeat-one must not retry a dead song forever.
  bool _advance({bool forced = false}) {
    if (_queue.isEmpty) return false;
    var mode = _playMode;
    if (forced && mode == PlayMode.repeatOne) mode = PlayMode.repeatAll;
    switch (mode) {
      case PlayMode.repeatOne:
        return true;
      case PlayMode.shuffle:
        if (_queue.length > 1) {
          int next;
          do {
            next = Random().nextInt(_queue.length);
          } while (next == _idx);
          _idx = next;
        }
        return true;
      case PlayMode.sequential:
        if (_idx < _queue.length - 1) {
          _idx++;
          return true;
        }
        return false;
      case PlayMode.repeatAll:
        _idx = (_idx + 1) % _queue.length;
        return true;
    }
  }

  // Skips only move the index and queue a load. Ten rapid taps move the index
  // ten times but cause a single load of the final song.
  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    _resetFailureCounters();
    if (_advance()) {
      _requestLoad(_queue[_idx]);
      _queueChanged.add(null);
    } else {
      debugPrint('[N] sequential: end of queue, stopping');
      await stop();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    _resetFailureCounters();
    _idx = (_idx - 1 + _queue.length) % _queue.length;
    _requestLoad(_queue[_idx]);
    _queueChanged.add(null);
  }

  // ── Queue editing (keeps the real playback queue in sync with the UI) ─────

  /// [newIndex] is the position after the item has been removed (as the UI
  /// already adjusts it for ReorderableListView).
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    final current = _current;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex.clamp(0, _queue.length), item);
    if (current != null) {
      final i = _queue.indexOf(current);
      if (i >= 0) _idx = i;
    }
    _publishQueue();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    final removingCurrent = index == _idx;
    _queue.removeAt(index);

    if (_queue.isEmpty) {
      _idx = 0;
      _publishQueue();
      unawaited(stop());
      return;
    }
    if (index < _idx) {
      _idx--;
    } else if (removingCurrent) {
      _idx = _idx.clamp(0, _queue.length - 1); // next song slides into this slot
    }
    _publishQueue();
    if (removingCurrent) {
      _resetFailureCounters();
      _requestLoad(_queue[_idx]);
    }
  }

  void _publishQueue() {
    queue.add(_queue
        .map((s) => MediaItem(
              id: s.videoId,
              title: s.title,
              artist: s.artist,
              artUri:
                  s.thumbnailUrl.isNotEmpty ? Uri.tryParse(s.thumbnailUrl) : null,
            ))
        .toList());
    _queueChanged.add(null);
  }

  void _broadcast(PlaybackEvent e) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _idx,
    ));
  }

  @override
  Future<void> onTaskRemoved() async {
    _tok++;
    _runner.cancel();
    _retryTimer?.cancel();
    await _player.stop();
    await _player.dispose();
    _yt.close();
    try {
      for (final f in _cacheDir!.listSync().whereType<File>()) {
        if (f.path.endsWith('.tmp')) f.deleteSync();
      }
    } catch (_) {}
  }
}