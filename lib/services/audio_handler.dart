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

  NebulaAudioHandler() {
    _player.playbackEventStream.listen(
      _broadcast,
      onError: (Object e, StackTrace st) {
        // Broadcast error state AND attempt manifest-invalidation + retry.
        debugPrint('[N] event err: $e');
        playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.error));
        _handlePlaybackError(e, st);
      },
    );
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) skipToNext();
    });

    _initCache();
  }

  // ── Playback error handler ────────────────────────────────────────────────
  // Called when just_audio reports an error on the playbackEventStream.
  //
  // IMPORTANT: We must NOT retry on every error. Specifically:
  //   - "abort" / "Loading interrupted" — means we called stop() ourselves
  //     (e.g. user skipped). Retrying would cause "player already exists".
  //   - HTTP 403/410 or "Source error" — genuine URL expiry. Safe to retry
  //     after invalidating the manifest cache entry.
  void _handlePlaybackError(Object e, StackTrace st) {
    final errStr = e.toString().toLowerCase();

    // Never retry self-inflicted interruptions.
    if (errStr.contains('abort') ||
        errStr.contains('loading interrupted') ||
        errStr.contains('already exists')) {
      debugPrint('[N] playback error ignored (self-inflicted): $e');
      return;
    }

    final song = _current;
    if (song == null) return;
    debugPrint('[N] playback error for ${song.videoId}: $e — invalidating manifest cache and retrying');
    _manifestCache.remove(song.videoId);

    // Capture tok BEFORE the microtask so we abort if user skips in the meantime.
    final tok = _tok;
    Future.microtask(() async {
      if (_tok != tok) return;
      debugPrint('[N] retrying load after URL expiry: ${song.title}');
      await _load(song);
    });
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

  Future<void> playSong(Song song, {List<Song>? queue, int index = 0}) async {
    if (queue != null) {
      _queue = List.from(queue);
      _idx = index.clamp(0, queue.length - 1);
    } else if (!_queue.contains(song)) {
      _queue.add(song);
      _idx = _queue.length - 1;
    } else {
      _idx = _queue.indexOf(song);
    }
    await _load(song);
  }

  Future<void> _load(Song song) async {
    final tok = ++_tok;
    try {
      // Await stop() so the platform player fully tears down before we call
      // setAudioSource. Without this, just_audio throws:
      //   PlatformException(abort, Loading interrupted)
      // because the old source teardown races with the new source setup.
      await _player.stop();
      playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.loading, playing: false));
      mediaItem.add(MediaItem(
        id: song.videoId,
        title: song.title,
        artist: song.artist,
        artUri: song.thumbnailUrl.isNotEmpty
            ? Uri.tryParse(song.thumbnailUrl)
            : null,
      ));

      debugPrint('[N] ▶ ${song.title}');
      await _ensureCache();
      if (_tok != tok) return;

      // ── Path 1: Disk cache hit — instant playback ─────────────────────────
      if (_isCached(song.videoId)) {
        _markUsed(song.videoId);
        debugPrint('[N] disk cache hit');
        await _player.setAudioSource(
            AudioSource.file(_cf(song.videoId).path));
        if (_tok != tok) {
          _player.stop();
          return;
        }
        _current = song;
        await _player.play();
        debugPrint('[N] ✓ PLAYING (disk cached): ${song.title}');
        _scheduleNextPrefetch(tok);
        return;
      }

      // ── Path 2: Manifest cache hit — stream with near-zero delay ──────────
      // If the next song was prefetched while the current one was playing,
      // its manifest URL is already in _manifestCache — no network call needed.
      final cached = _manifestCache[song.videoId];
      if (cached != null && !cached.isExpired) {
        debugPrint('[N] manifest cache hit — streaming immediately');
        await _player.setAudioSource(AudioSource.uri(cached.info.url));
        if (_tok != tok) {
          _player.stop();
          return;
        }
        _current = song;
        await _player.play();
        debugPrint('[N] ✓ STREAMING (manifest cached): ${song.title}');
        _cacheInBackground(cached.info, song.videoId, tok);
        _scheduleNextPrefetch(tok);
        return;
      }

      // ── Path 3: Cold start — fetch manifest then stream ───────────────────
      debugPrint('[N] cold manifest fetch for ${song.title}');
      final info = await _getInfo(song.videoId, tok);
      if (_tok != tok) return;
      if (info == null) {
        debugPrint('[N] ✗ no stream info for ${song.videoId}');
        playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.error));
        return;
      }

      await _player.setAudioSource(AudioSource.uri(info.url));
      if (_tok != tok) {
        _player.stop();
        return;
      }
      _current = song;
      await _player.play();
      debugPrint('[N] ✓ STREAMING (cold): ${song.title}');
      _cacheInBackground(info, song.videoId, tok);
      _scheduleNextPrefetch(tok);
    } catch (e, st) {
      if (_tok != tok) return;
      debugPrint('[N] _load error: $e\n$st');
      playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error));
    }
  }

  void _cacheInBackground(
      AudioStreamInfo info, String videoId, int tok) {
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

  Future<AudioStreamInfo?> _getInfo(String videoId, int tok) async {
    if (_tok != tok) return null;

    // Return a fresh cached entry without any network call.
    final existing = _manifestCache[videoId];
    if (existing != null && !existing.isExpired) {
      debugPrint('[N] _getInfo: manifest cache hit for $videoId');
      return existing.info;
    }

    debugPrint('[N] manifest fetch for $videoId');

    for (int pass = 0; pass < 2; pass++) {
      for (int ci = 0; ci < _clients.length; ci++) {
        if (_tok != tok) return null;

        if (_clientIsOnCooldown(ci)) {
          final until = _clientCooldownUntil[ci]!;
          final remaining = until.difference(DateTime.now()).inSeconds;
          debugPrint(
              '[N] client=$ci skipped (cooldown ${remaining}s remaining)');
          continue;
        }

        try {
          debugPrint('[N] manifest client=$ci for $videoId');
          final m = await _yt.videos.streamsClient
              .getManifest(videoId, ytClients: [_clients[ci]])
              .timeout(_timeouts[ci]);

          if (m.audioOnly.isEmpty) {
            debugPrint('[N] client=$ci no audio streams, trying next');
            continue;
          }

          // ── Quality selection: always pick lowest bitrate ─────────────────
          // Caller said latency > quality. Lowest bitrate = fastest buffering
          // start and smallest background download. Typically 48kbps AAC.
          final mp4 = m.audioOnly
              .where((s) => s.codec.mimeType.contains('mp4'))
              .toList()
            ..sort((a, b) => a.bitrate.compareTo(b.bitrate));

          // Pick the absolute lowest mp4; fall back to lowest of any codec
          // if no mp4 streams exist (preserves existing fallback behaviour).
          final chosen = mp4.isNotEmpty
              ? mp4.first
              : (m.audioOnly.toList()
                    ..sort((a, b) => a.bitrate.compareTo(b.bitrate)))
                  .first;

          debugPrint(
              '[N] ✓ manifest ok client=$ci ${chosen.codec.mimeType} @ ${chosen.bitrate}');
          _markClientSuccess(ci);

          // Store in manifest cache so next play / prefetch is instant.
          _manifestCache[videoId] = _ManifestEntry(chosen);

          return chosen;
        } on RequestLimitExceededException {
          _markClientRateLimited(ci);
        } on TimeoutException {
          debugPrint('[N] client=$ci timeout, trying next');
        } catch (e) {
          debugPrint('[N] client=$ci error: $e');
        }
      }

      if (pass == 0) {
        final now = DateTime.now();
        bool anyAvailableNow = false;
        Duration? shortestWait;

        for (int ci = 0; ci < _clients.length; ci++) {
          final until = _clientCooldownUntil[ci];
          if (until == null || now.isAfter(until)) {
            anyAvailableNow = true;
            break;
          }
          final wait = until.difference(now);
          if (shortestWait == null || wait < shortestWait) {
            shortestWait = wait;
          }
        }

        if (anyAvailableNow) continue;

        if (shortestWait != null && shortestWait.inSeconds <= 30) {
          debugPrint(
              '[N] all clients on cooldown, waiting ${shortestWait.inSeconds}s');
          for (int s = 0; s < shortestWait.inSeconds + 1; s++) {
            if (_tok != tok) return null;
            await Future.delayed(const Duration(seconds: 1));
          }
          debugPrint('[N] cooldown wait done, retrying pass 2');
        } else {
          debugPrint('[N] all clients need >30s cooldown, aborting');
          break;
        }
      }
    }

    debugPrint('[N] all clients failed for $videoId');
    return null;
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
        info = await _getInfo(next.videoId, ptok);
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
  Future<void> play() async => _player.play();

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> seek(Duration p) async => _player.seek(p);

  @override
  Future<void> stop() async {
    _tok++;
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.idle, playing: false));
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    switch (_playMode) {
      case PlayMode.repeatOne:
        // Stay on the same song — just reload from the top.
        await _load(_queue[_idx]);
        break;
      case PlayMode.shuffle:
        // Pick a random index different from the current one.
        if (_queue.length > 1) {
          int next;
          do {
            next = Random().nextInt(_queue.length);
          } while (next == _idx);
          _idx = next;
        }
        await _load(_queue[_idx]);
        break;
      case PlayMode.sequential:
        // Advance but stop at the end — do not wrap.
        if (_idx < _queue.length - 1) {
          _idx++;
          await _load(_queue[_idx]);
        } else {
          // End of queue — stop playback entirely.
          debugPrint('[N] sequential: end of queue, stopping');
          await stop();
        }
        break;
      case PlayMode.repeatAll:
      default:
        _idx = (_idx + 1) % _queue.length;
        await _load(_queue[_idx]);
        break;
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    _idx = (_idx - 1 + _queue.length) % _queue.length;
    await _load(_queue[_idx]);
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