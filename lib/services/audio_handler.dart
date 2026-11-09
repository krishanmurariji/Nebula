import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';
import 'app_log.dart';
import 'audio_cache.dart';
import 'backup_settings.dart';
import 'connectivity_probe.dart';
import 'fallback_sources.dart';
import 'http_range_download.dart';
import 'latest_wins_runner.dart';
import 'playback_failure.dart';
import 'progressive_download.dart';
import 'resolved_stream.dart';
import 'stream_resolver.dart';
import 'youtube_clients.dart';
import 'webview_js_solver.dart';

final audioHandlerProvider =
    Provider<NebulaAudioHandler>((ref) => throw UnimplementedError());

// ── Play mode ─────────────────────────────────────────────────────────────────
// repeatAll  — wraps around when queue ends (default)
// repeatOne  — replays the same song forever
// shuffle    — picks a random song on every advance
// sequential — plays to end of queue then stops
enum PlayMode { repeatAll, repeatOne, shuffle, sequential }

/// Songs up to this size are downloaded completely (into the disk cache) and
/// then played from the local file. Anything bigger streams straight from its
/// URL instead of being held in memory.
const int _kMaxDownloadFirstBytes = 40 * 1024 * 1024;

/// How many different clients/sources a single song may try before giving up.
const int _kMaxStreamAttempts = 4;

class _LoadRequest {
  final Song song;
  final int tok;
  final Duration? resumeAt;
  final int attempt;
  const _LoadRequest(this.song, this.tok, this.resumeAt, this.attempt);
}

class _StreamResolveException implements Exception {
  final FailureKind kind;
  const _StreamResolveException(this.kind);
  @override
  String toString() => 'StreamResolveException($kind)';
}

/// The stream a client handed out could not actually be downloaded (403,
/// stall, truncated …). Carries which client so it can be penalized.
class _DownloadFailure implements Exception {
  final int client;
  final Object cause;
  const _DownloadFailure(this.client, this.cause);
  @override
  String toString() => 'DownloadFailure(client $client): $cause';
}

class _SupersededException implements Exception {
  const _SupersededException();
}

class NebulaAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  // Solves YouTube's JavaScript challenges (the "n" parameter / signatures) in
  // an invisible WebView. Without it most streams are throttled to zero bytes
  // or refused with 403.
  late final WebViewEJSSolver _jsSolver =
      WebViewEJSSolver(log: (m) => nlog('[N] $m'));
  late final YoutubeExplode _yt = YoutubeExplode(jsSolver: _jsSolver);

  Song? _current;
  List<Song> _queue = [];
  int _idx = 0;
  int _tok = 0;

  // Current play mode — changed by the UI via setPlayMode().
  PlayMode _playMode = PlayMode.repeatAll;

  // ── Stream resolution ─────────────────────────────────────────────────────
  // androidVr first — bypasses IP-level blocks that hit android/ios/mweb.
  // Order matters (and the resolver then remembers the last one that worked).
  // The first two are yt-dlp's current default clients and the only ones that
  // were not refused (HTTP 403 / "unplayable") on a real device;
  // androidSdkless and mweb are kept as fallbacks. Dead clients (androidVr,
  // ios, tv, android …) were removed: each one costs seconds and one more
  // request to YouTube, which is how rate limiting gets triggered.
  static final _clients = [
    kVisionOsClient, // worked first on the device, and needs no JS challenge
    kTvSamsungClient,
    YoutubeApiClient.androidSdkless,
    YoutubeApiClient.mweb,
  ];

  // The backup source (Piped/Invidious) comes after every YouTube client.
  static final int _kBackupClient = _clients.length;

  late final FallbackStreamFetcher _fallback =
      FallbackStreamFetcher(instances: loadBackupInstances);

  late final StreamResolver<ResolvedStream> _resolver =
      StreamResolver<ResolvedStream>(
    fetch: _fetchStream,
    log: (m) => nlog('[N] resolver: $m'),
    // Generous: the first lookup also loads and runs the JavaScript solver.
    timeouts: const [
      Duration(seconds: 25), // visionos
      Duration(seconds: 40), // tv_samsung (also runs the JS solver)
      Duration(seconds: 30), // androidSdkless
      Duration(seconds: 30), // mweb
      Duration(seconds: 20), // backup source (up to two instances)
    ],
  );

  final ConnectivityProbe _net = ConnectivityProbe();

  Future<ResolvedStream?> _fetchStream(String videoId, int client) async {
    if (client == _kBackupClient) {
      return (await _fallback.fetch(videoId))?.withClient(client);
    }

    nlog('[N] manifest client=$client for $videoId');
    final m = await _yt.videos.streamsClient
        .getManifest(videoId, ytClients: [_clients[client]]);
    if (m.audioOnly.isEmpty) return null;

    // Lowest bitrate among plain downloadable audio (no HLS/DASH fragments):
    // fastest start and smallest download. Codec does not matter: Android
    // plays both AAC (mp4) and Opus (webm).
    final usable = m.audioOnly.where((s) => s.fragments.isEmpty).toList()
      ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
    if (usable.isEmpty) return null;
    final info = usable.first;
    nlog('[N] ✓ manifest ok client=$client ${info.codec.mimeType} @ ${info.bitrate}');
    return ResolvedStream(
      url: info.url,
      totalBytes: info.size.totalBytes,
      mimeType: info.codec.mimeType,
      open: () => _yt.videos.streamsClient.get(info),
      clientIndex: client,
      userAgent: _clients[client].payload['context']?['client']?['userAgent']
          as String?,
    );
  }

  // ── Disk cache ────────────────────────────────────────────────────────────
  AudioCache? _cache; // null until ready, or if the disk is unusable
  final Completer<void> _cacheReady = Completer<void>();

  // The download feeding the player right now, and the next-song prefetch.
  ProgressiveDownload? _activeDownload;
  ProgressiveDownload? _prefetchDownload;

  // ── Load pipeline state ───────────────────────────────────────────────────
  // All loads go through this runner: one at a time, newest request wins.
  // The native player therefore never sees overlapping stop()/setAudioSource().
  late final LatestWinsRunner<_LoadRequest> _runner =
      LatestWinsRunner<_LoadRequest>(_runLoad);

  Timer? _retryTimer;
  int _consecutiveFailures = 0; // songs in a row that failed (reset on success/user action)
  int _midPlayRetries = 0;      // mid-song recoveries for the current song
  int _mediaRefusals = 0;       // distinct clients whose download got HTTP 403
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

    unawaited(_initCache());
    unawaited(_jsSolver.warmUp().catchError((Object e) {
      nlog('[N] JS solver could not start: $e');
    }));
  }

  // ── Error from the native player while a song is (or should be) playing ──
  // Typically an expired/throttled stream URL. Re-resolve and resume from the
  // same position a couple of times, then give up on the song and skip it.
  void _onPlayerError(Object e) {
    final kind = classifyPlaybackError(e);
    nlog('[N] player error ($kind): $e');
    if (kind == FailureKind.cancelled) return;
    // A load in progress reports its own failures through exceptions.
    if (_runner.isBusy) return;

    final song = _current;
    if (song == null) return;

    if (kind != FailureKind.permanent && _midPlayRetries < 2) {
      _midPlayRetries++;
      _resolver.invalidate(song.videoId);
      _requestLoad(song, resumeAt: _player.position, attempt: 1);
    } else {
      unawaited(_giveUpOnCurrent(song, kind));
    }
  }

  // ── Cache init ────────────────────────────────────────────────────────────

  Future<void> _initCache() async {
    try {
      final base = await getApplicationSupportDirectory();
      final cache = AudioCache(Directory('${base.path}/nebula_cache'));
      await cache.init();
      _cache = cache;
      nlog('[N] cache ready: ${cache.count} songs, ${cache.totalBytes} bytes');
    } catch (e) {
      // No usable disk → just stream without caching.
      nlog('[N] cache disabled: $e');
    } finally {
      if (!_cacheReady.isCompleted) _cacheReady.complete();
    }
  }

  Future<void> _ensureCache() => _cacheReady.future
      .timeout(const Duration(seconds: 5), onTimeout: () {});

  Set<String> get _protectedIds =>
      {if (_current != null) _current!.videoId};

  // ── Public getters ────────────────────────────────────────────────────────

  Song? get currentSong => _current;
  List<Song> get songQueue => List.unmodifiable(_queue);
  int get queueIndex => _idx;
  int get songQueueIndex => _idx;
  AudioPlayer get player => _player;
  int get cachedSongCount => _cache?.count ?? 0;
  int get cacheSizeBytes => _cache?.totalBytes ?? 0;
  PlayMode get playMode => _playMode;
  int get globalCooldownSeconds => _resolver.globalCooldownSeconds;

  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    nlog('[N] playMode → $mode');
  }

  // ── Play / Load ───────────────────────────────────────────────────────────

  Future<void> playSong(Song song, {List<Song>? queue, int index = 0}) {
    if (queue != null && queue.isNotEmpty) {
      _queue = List.from(queue);
      // Trust the song itself, not the caller's index: if it is not in the
      // list (stale UI, deleted entry) it is put in front so the queue and
      // what plays can never disagree.
      final at = _queue.indexOf(song);
      if (at < 0) {
        _queue.insert(0, song);
        _idx = 0;
      } else {
        _idx = at;
      }
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
    _mediaRefusals = 0;
  }

  /// Entry point for every load. Synchronous and cheap: it only records the
  /// request and publishes the new song to the UI immediately.
  void _requestLoad(Song song, {Duration? resumeAt, int attempt = 0}) {
    final tok = ++_tok;
    _retryTimer?.cancel();
    // Stop moving bytes for whatever the user just left behind.
    _activeDownload?.cancel();
    _activeDownload = null;
    _prefetchDownload?.cancel();
    _prefetchDownload = null;
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
      nlog('[N] ▶ ${song.title} (attempt ${req.attempt})');
      if (!song.isPlayable) {
        // Corrupt or tampered entry: skip it, never hand it to the network or disk.
        throw const _StreamResolveException(FailureKind.permanent);
      }
      try {
        await _player.stop();
      } catch (e) {
        nlog('[N] stop() before load ignored: $e');
      }
      if (!live()) return;

      await _ensureCache();
      if (!live()) return;

      final AudioSource source;
      final cachedFile = await _cache?.lookup(song.videoId);
      if (!live()) return;

      if (cachedFile != null) {
        // ── Path 1: on disk — instant, works offline ────────────────────────
        usedDiskCache = true;
        source = AudioSource.file(cachedFile.path);
      } else {
        // ── Resolve the stream (memory cache or network) ────────────────────
        final res =
            await _resolver.resolve(song.videoId, superseded: ctx.superseded);
        if (!live()) return;
        final info = res.value;
        if (info == null) throw _StreamResolveException(res.kind);

        final cache = _cache;
        if (cache != null &&
            info.totalBytes > 0 &&
            info.totalBytes <= _kMaxDownloadFirstBytes) {
          // Download completely, then play the local file. Songs are small
          // (about 1 MB at the chosen bitrate), a failure here is immediate and
          // explicit, and the finished file doubles as the offline cache.
          nlog('[N] downloading ${info.totalBytes} bytes via ${info.origin} '
              '(client ${info.clientIndex})');

          Uint8List bytes;
          try {
            // 1) Plain ranged download with the User-Agent this URL was issued
            //    to: reports the real HTTP status, and does not stall.
            bytes = await _download(
              () => openRangedDownload(info.url, info.totalBytes,
                  userAgent: info.userAgent),
              info.totalBytes,
              ctx,
            );
          } on _SupersededException {
            return;
          } catch (direct) {
            nlog('[N] direct download failed: $direct');
            try {
              // 2) The library's own downloader (it can refresh the stream
              //    address itself when it gets a 403).
              bytes = await _download(info.open, info.totalBytes, ctx);
            } on _SupersededException {
              return;
            } catch (library) {
              nlog('[N] library download failed: $library');
              throw _DownloadFailure(
                  info.clientIndex, 'direct: $direct; library: $library');
            }
          }
          if (!live()) return;

          await cache.put(song.videoId, bytes, protect: _protectedIds);
          final stored = await cache.lookup(song.videoId);
          if (!live()) return;
          if (stored == null) {
            throw _DownloadFailure(
                info.clientIndex, 'could not store the song on disk');
          }
          nlog('[N] ready: ${bytes.length} bytes');
          source = AudioSource.file(stored.path);
        } else {
          // Too large (or no disk): let the native player stream the URL.
          nlog('[N] streaming directly from URL');
          source = AudioSource.uri(info.url);
        }
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
      nlog('[N] ✓ started: ${song.title}');
      _scheduleNextPrefetch(req.tok);
    } catch (e, st) {
      _activeDownload?.cancel();
      if (!live()) return; // superseded: whatever happened is irrelevant now
      if (e is _DownloadFailure) {
        nlog('[N] download failed: $e');
        unawaited(_handleDownloadFailure(req, e));
        return;
      }
      var kind =
          e is _StreamResolveException ? e.kind : classifyPlaybackError(e);
      nlog('[N] load failed ($kind): $e\n$st');
      if (kind == FailureKind.cancelled) kind = FailureKind.transient;
      if (usedDiskCache) unawaited(_cache?.remove(song.videoId)); // maybe corrupt
      unawaited(_handleLoadFailure(req, kind));
    }
  }

  /// Downloads a whole song into memory, abandoning it as soon as the user
  /// moves on ([_SupersededException]) or no data arrives for 10 seconds.
  Future<Uint8List> _download(Stream<List<int>> Function() open, int total,
      RunContext ctx) async {
    final dl = ProgressiveDownload(
      open: open,
      totalBytes: total,
      stallTimeout: const Duration(seconds: 10),
    );
    _activeDownload = dl;
    dl.start();
    try {
      return await Future.any<Uint8List>([
        dl.completed,
        ctx.superseded
            .then<Uint8List>((_) => throw const _SupersededException()),
      ]);
    } catch (_) {
      dl.cancel();
      rethrow;
    }
  }

  /// The stream a client handed out could not be downloaded. Penalize that
  /// client for a while and immediately try the next one, so a client that
  /// returns addresses YouTube refuses to serve cannot wedge playback.
  Future<void> _handleDownloadFailure(
      _LoadRequest req, _DownloadFailure f) async {
    final song = req.song;

    // A server that answered "403" proves we are online, so skip the offline
    // probe. Two different clients refused by the media server means YouTube is
    // refusing audio for this device/network: more attempts cannot help and
    // each one asks YouTube again (which is how rate limiting gets triggered).
    final status = httpStatusInCause(f.cause);
    if (status == 403) {
      _mediaRefusals++;
      if (_mediaRefusals >= 2) {
        if (_tok != req.tok) return;
        _notices.add('YouTube refused the audio download (HTTP 403) for this '
            'device or network. Nothing is wrong with your connection.');
        _setError();
        return;
      }
    }
    if (status == null && !await _net.isOnline()) {
      if (_tok != req.tok) return;
      _handleOffline(song, req.tok, resumeAt: req.resumeAt);
      return;
    }
    if (_tok != req.tok) return;

    // DNS / connection errors are the network's fault, not this client's:
    // do not burn through the other clients (each one costs seconds).
    if (classifyPlaybackError(f.cause) == FailureKind.network) {
      await _handleLoadFailure(req, FailureKind.network);
      return;
    }

    _resolver.invalidate(song.videoId);
    _resolver.penalize(f.client, const Duration(minutes: 5));
    if (req.attempt + 1 < _kMaxStreamAttempts) {
      _requestLoad(song, resumeAt: req.resumeAt, attempt: req.attempt + 1);
    } else {
      await _giveUpOnCurrent(song, FailureKind.transient);
    }
  }

  // ── Failure policy ────────────────────────────────────────────────────────
  // offline      → never burn retries or skip: play downloaded songs, or wait
  //                and resume automatically when the network returns
  // permanent    → skip the song right away
  // rateLimited  → stop and surface the countdown (retrying now makes it worse)
  // transient    → retry with backoff (max 2 retries), then skip
  Future<void> _handleLoadFailure(_LoadRequest req, FailureKind kind) async {
    final song = req.song;
    _resolver.invalidate(song.videoId);

    if (kind != FailureKind.permanent &&
        kind != FailureKind.rateLimited &&
        !await _net.isOnline()) {
      if (_tok != req.tok) return;
      _handleOffline(song, req.tok, resumeAt: req.resumeAt);
      return;
    }
    if (_tok != req.tok) return;

    if (kind == FailureKind.network) {
      // We can reach the internet in general (checked above) but not YouTube:
      // typically broken DNS on this Wi-Fi. Skipping songs would not help.
      _notices.add("Can't reach YouTube from this network (DNS/connection "
          'failed). Try mobile data or a different DNS.');
      _setError();
      return;
    }
    if (kind == FailureKind.rateLimited) {
      // YouTube answered (so we ARE online) but is limiting this network.
      final wait = _resolver.globalCooldownSeconds;
      _notices.add('YouTube is limiting requests from your network'
          '${wait > 0 ? ' — retrying in ${wait}s' : ''}');
      _setError();
      return;
    }
    if (kind == FailureKind.transient && req.attempt < 2) {
      final delay = retryDelay(req.attempt);
      nlog('[N] retry in ${delay.inMilliseconds}ms');
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
    await _giveUpOnCurrent(song, kind);
  }

  /// The current song cannot be played: move on instead of showing a dead end.
  Future<void> _giveUpOnCurrent(Song song, FailureKind kind) async {
    final tok = _tok;
    if (kind != FailureKind.permanent && !await _net.isOnline()) {
      if (_tok != tok) return;
      _handleOffline(song, tok, resumeAt: _player.position);
      return;
    }
    if (_tok != tok) return;

    _consecutiveFailures++;
    final canSkip =
        _queue.length > 1 && _consecutiveFailures < min(_queue.length, 5);
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

  /// No network. Keep the music going from downloaded songs if any exist in
  /// the queue; otherwise wait quietly and resume this song when we are back.
  void _handleOffline(Song song, int tok, {Duration? resumeAt}) {
    final cache = _cache;
    if (cache != null && _queue.length > 1) {
      for (var step = 1; step < _queue.length; step++) {
        final i = (_idx + step) % _queue.length;
        if (cache.contains(_queue[i].videoId)) {
          nlog('[N] offline → playing downloaded "${_queue[i].title}"');
          _notices.add('Offline — playing downloaded songs');
          _idx = i;
          _resetFailureCounters();
          _requestLoad(_queue[i]);
          _queueChanged.add(null);
          return;
        }
      }
    }

    nlog('[N] offline → waiting for connection');
    _notices.add('No connection — will resume when back online');
    _setError();
    unawaited(() async {
      final back = await _net.waitUntilOnline(isCancelled: () => _tok != tok);
      if (!back || _tok != tok) return;
      nlog('[N] back online → resuming "${song.title}"');
      _resetFailureCounters();
      _requestLoad(song, resumeAt: resumeAt);
    }());
  }

  void _setError() {
    playbackState.add(playbackState.value
        .copyWith(processingState: AudioProcessingState.error, playing: false));
  }

  // ── Next-song prefetch ────────────────────────────────────────────────────
  // Runs only when the user is not actively changing songs, and never competes
  // with the current song's download for bandwidth: it waits for that to finish.
  //   1. resolve the next song's stream (shared/de-duplicated with any play)
  //   2. download it fully into the disk cache
  void _scheduleNextPrefetch(int ptok) {
    if (_queue.length < 2) return;
    final next = _queue[(_idx + 1) % _queue.length];
    final cache = _cache;
    if (cache == null || cache.contains(next.videoId)) return;
    if (_resolver.globalCooldownSeconds > 0) return; // do not add load

    unawaited(() async {
      try {
        // Let the current song finish downloading first (if it is streaming).
        final active = _activeDownload;
        if (active != null) {
          await active.completed.then((_) {}, onError: (Object _) {});
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        if (_tok != ptok || _runner.isBusy) return;
        if (cache.contains(next.videoId)) return;

        nlog('[N] prefetch: ${next.title}');
        final res = await _resolver.resolve(next.videoId);
        final info = res.value;
        if (info == null || _tok != ptok || _runner.isBusy) return;

        final dl = ProgressiveDownload(
          open: info.open,
          totalBytes: info.totalBytes,
          stallTimeout: const Duration(seconds: 15),
        );
        _prefetchDownload = dl..start();
        final bytes = await dl.completed;
        if (_tok != ptok) return; // user moved on; bytes are discarded
        await cache.put(next.videoId, bytes, protect: _protectedIds);
        nlog('[N] prefetch done: ${next.title}');
      } catch (e) {
        nlog('[N] prefetch skipped: $e');
      }
    }());
  }

  // ── Cache management ──────────────────────────────────────────────────────

  Future<void> clearCache() async {
    _resolver.clear();
    await _cache?.clear(protect: _protectedIds);
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
  Future<void> seek(Duration position) {
    final total = _player.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (total != null && target > total) target = total;
    return _player.seek(target);
  }

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
      nlog('[N] sequential: end of queue, stopping');
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
    _activeDownload?.cancel();
    _prefetchDownload?.cancel();
    await _cache?.flush();
    await _player.stop();
    await _player.dispose();
    _yt.close();
  }
}
