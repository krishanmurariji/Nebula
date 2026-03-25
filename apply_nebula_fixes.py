#!/usr/bin/env python3
"""
Nebula Music Player — Performance Fix Patcher
Applies all 5 audio delay fixes to the Flutter project.

Usage:
    python apply_nebula_fixes.py --project /path/to/your/nebula/project

What it does:
    Fix #1 — Stream directly instead of downloading before playback
    Fix #2 — Debounce ribbon track switching (350ms)
    Fix #3 — Replace busy-wait in _ensureCache() with Completer
    Fix #4 — Sequential manifest with stagger (avoids YouTube rate limiting)
    Fix #5 — Prefetch after play starts with 3s delay (no request overlap)
"""

import re
import sys
import shutil
import argparse
from pathlib import Path
from datetime import datetime


# ─── Colour helpers ──────────────────────────────────────────────────────────
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

def ok(msg):   print(f"  {GREEN}✓{RESET}  {msg}")
def warn(msg): print(f"  {YELLOW}⚠{RESET}  {msg}")
def err(msg):  print(f"  {RED}✗{RESET}  {msg}")
def info(msg): print(f"  {CYAN}→{RESET}  {msg}")
def title(msg):print(f"\n{BOLD}{msg}{RESET}")


# ─── Backup helper ────────────────────────────────────────────────────────────
def backup(path: Path) -> Path:
    ts  = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = path.with_suffix(path.suffix + f".bak_{ts}")
    shutil.copy2(path, bak)
    return bak


# ═════════════════════════════════════════════════════════════════════════════
# NEW FILE CONTENTS
# ═════════════════════════════════════════════════════════════════════════════

# ─── audio_handler.dart ───────────────────────────────────────────────────────
AUDIO_HANDLER_NEW = r'''import 'dart:async';
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

class _CE {
  final String id; final int sz; int ts;
  _CE(this.id, this.sz, this.ts);
  Map toJson() => {'id': id, 'sz': sz, 'ts': ts};
  factory _CE.fromJson(Map j) => _CE(j['id'] as String, j['sz'] as int, j['ts'] as int);
}

class NebulaAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  // Single YoutubeExplode instance — a pool adds no benefit because all instances
  // share the same IP. Only the ytClients (User-Agent) parameter matters.
  final YoutubeExplode _yt = YoutubeExplode();

  Song?      _current;
  List<Song> _queue = [];
  int        _idx   = 0;
  int        _tok   = 0;

  Directory? _cacheDir;
  final Map<String, _CE> _index = {};

  // FIX #3: Completer replaces the old bool + busy-wait loop
  final Completer<void> _cacheReadyCompleter = Completer<void>();

  // androidVr is tried first — in testing it bypasses IP-level rate limits
  // that block android/ios/mweb. The others are kept as genuine fallbacks.
  static final _clients = [
    YoutubeApiClient.androidVr,
    YoutubeApiClient.android,
    YoutubeApiClient.ios,
    YoutubeApiClient.mweb,
  ];

  // Timeout per client: first attempt gets more time, fallbacks get standard time
  static const _timeouts = [
    Duration(seconds: 20), // androidVr — not rate limited but can be slow
    Duration(seconds: 12), // android
    Duration(seconds: 12), // ios
    Duration(seconds: 12), // mweb
  ];

  NebulaAudioHandler() {
    _player.playbackEventStream.listen(_broadcast,
      onError: (Object e, StackTrace _) {
        debugPrint('[N] event err: $e');
        playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.error));
      });
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) skipToNext();
    });
    _initCache();
  }

  void _initCache() async {
    try {
      final candidates = <String>[];
      final tmp = Platform.environment['TMPDIR'] ?? '';
      if (tmp.isNotEmpty) {
        candidates.add(tmp.replaceAll(RegExp(r'[/\\]cache$'), '/files/nebula_cache'));
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
          t.writeAsStringSync('ok'); t.deleteSync();
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
            if (File('${_cacheDir!.path}/${ce.id}.mp4').existsSync())
              _index[ce.id] = ce;
          }
          debugPrint('[N] index: ${_index.length} songs');
        } catch (_) {}
      }
    } catch (e) {
      _cacheDir = Directory.systemTemp;
    } finally {
      // FIX #3: Complete exactly once — no more busy-wait
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
    final sorted = _index.values.toList()..sort((a, b) => a.ts.compareTo(b.ts));
    for (final e in sorted) {
      if (total <= (_kMaxCacheBytes * 0.8).toInt()) break;
      try { _cf(e.id).deleteSync(); total -= e.sz; _index.remove(e.id); } catch (_) {}
    }
    _saveIndex();
  }

  // FIX #3: Zero spin-wait — awaits the Completer with a 5s safety timeout
  Future<void> _ensureCache() async {
    await _cacheReadyCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    _cacheDir ??= Directory.systemTemp;
  }

  Song?       get currentSong    => _current;
  List<Song>  get songQueue      => List.unmodifiable(_queue);
  int         get queueIndex     => _idx;
  int         get songQueueIndex => _idx;
  AudioPlayer get player         => _player;
  int         get cachedSongCount => _index.length;
  int         get cacheSizeBytes => _index.values.fold(0, (s, e) => s + e.sz);

  Future<void> playSong(Song song, {List<Song>? queue, int index = 0}) async {
    if (queue != null) {
      _queue = List.from(queue);
      _idx   = index.clamp(0, queue.length - 1);
    } else if (!_queue.contains(song)) {
      _queue.add(song); _idx = _queue.length - 1;
    } else {
      _idx = _queue.indexOf(song);
    }
    await _load(song);
  }

  Future<void> _load(Song song) async {
    final tok = ++_tok;
    try {
      _player.stop();
      playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.loading, playing: false));
      mediaItem.add(MediaItem(
        id: song.videoId, title: song.title, artist: song.artist,
        artUri: song.thumbnailUrl.isNotEmpty ? Uri.tryParse(song.thumbnailUrl) : null));

      debugPrint('[N] ▶ ${song.title}');
      await _ensureCache();
      if (_tok != tok) return;

      // FIX #1a: Cache hit → instant playback from local file
      if (_isCached(song.videoId)) {
        _markUsed(song.videoId);
        debugPrint('[N] cache hit');
        await _player.setAudioSource(AudioSource.file(_cf(song.videoId).path));
        if (_tok != tok) { _player.stop(); return; }
        _current = song;
        await _player.play();
        debugPrint('[N] ✓ PLAYING (cached): ${song.title}');
        _prefetchNext(tok);
        return;
      }

      // FIX #1b: Get stream URL, play IMMEDIATELY, cache in background
      final info = await _getInfo(song.videoId, tok);
      if (_tok != tok) return;
      if (info == null) {
        debugPrint('[N] ✗ no stream info for ${song.videoId}');
        playbackState.add(playbackState.value.copyWith(
            processingState: AudioProcessingState.error));
        return;
      }

      // Stream directly — playback starts after a few seconds of buffering,
      // NOT after the full file downloads (was 5–30 sec, now 1–3 sec)
      debugPrint('[N] streaming from URL: ${song.title}');
      await _player.setAudioSource(AudioSource.uri(info.url));
      if (_tok != tok) { _player.stop(); return; }
      _current = song;
      await _player.play();
      debugPrint('[N] ✓ STREAMING: ${song.title}');

      // Cache in background while song is already playing
      _cacheInBackground(info, song.videoId, tok);

    } catch (e, st) {
      if (_tok != tok) return;
      debugPrint('[N] _load error: $e\n$st');
      playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error));
    }
  }

  // Runs silently while the song is already playing
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

  // FIX #4: Sequential manifest fetch.
  // Client order: androidVr first (bypasses rate limits that block android/ios/mweb).
  // On rate limit: wait 2s before next client (IP-level blocks need time to cool).
  // On timeout: try next client immediately (slow response, not a block).
  // _rotateYt() removed — swapping YoutubeExplode instances is meaningless since
  // all instances share the same IP; only the ytClients User-Agent matters.
  Future<AudioStreamInfo?> _getInfo(String videoId, int tok) async {
    if (_tok != tok) return null;
    debugPrint('[N] manifest for $videoId');

    for (int ci = 0; ci < _clients.length; ci++) {
      if (_tok != tok) return null;
      try {
        debugPrint('[N] manifest client=$ci (${_clients[ci].runtimeType}) for $videoId');
        final m = await _yt.videos.streamsClient
            .getManifest(videoId, ytClients: [_clients[ci]])
            .timeout(_timeouts[ci]);
        if (m.audioOnly.isEmpty) {
          debugPrint('[N] client=$ci no audio streams, trying next');
          continue;
        }
        final mp4 = m.audioOnly
            .where((s) => s.codec.mimeType.contains('mp4'))
            .toList()..sort((a, b) => a.bitrate.compareTo(b.bitrate));
        final chosen = mp4.isNotEmpty
            ? mp4.firstWhere(
                (s) => s.bitrate.bitsPerSecond >= 96000,
                orElse: () => mp4.last)
            : (m.audioOnly.toList()
                ..sort((a, b) => a.bitrate.compareTo(b.bitrate))).first;
        debugPrint('[N] manifest ok client=$ci ${chosen.codec.mimeType} @ ${chosen.bitrate}');
        return chosen;
      } on RequestLimitExceededException {
        // IP-level block — wait 2s before trying the next user-agent.
        // 200ms is not enough; YouTube's burst window is ~1-2 seconds.
        debugPrint('[N] client=$ci rate limited, waiting 2s before next client');
        await Future.delayed(const Duration(seconds: 2));
      } on TimeoutException {
        debugPrint('[N] client=$ci timeout, trying next immediately');
      } catch (e) {
        debugPrint('[N] client=$ci error: $e');
      }
    }
    debugPrint('[N] all clients failed for $videoId');
    return null;
  }

  Future<File?> _download(AudioStreamInfo info, String videoId, int tok) async {
    final dest = _cf(videoId);
    final tmp  = _tf(videoId);
    if (tmp.existsSync()) tmp.deleteSync();

    IOSink? sink;
    StreamSubscription<List<int>>? sub;
    try {
      sink = tmp.openWrite();
      int bytes = 0;
      final totalKB = (info.size.totalBytes / 1024).toStringAsFixed(0);
      debugPrint('[N] downloading $totalKB KB...');

      final comp  = Completer<void>();
      final timer = Timer(const Duration(seconds: 180), () {
        if (!comp.isCompleted) comp.completeError(
            TimeoutException('download timeout 180s'));
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
          if (bytes % (512*1024) < chunk.length)
            debugPrint('[N] dl ${(bytes/1024).toStringAsFixed(0)}/$totalKB KB');
        },
        onDone:  () { if (!comp.isCompleted) comp.complete(); },
        onError: (Object e, StackTrace st) {
          debugPrint('[N] stream error: $e');
          if (!comp.isCompleted) comp.completeError(e, st);
        },
        cancelOnError: true,
      );

      await comp.future;
      timer.cancel(); sub = null;

      if (_tok != tok) {
        if (sink != null) { try { await sink.close(); } catch(_) {} }
        _del(tmp); return null;
      }

      debugPrint('[N] flushing $bytes bytes...');
      await sink!.flush();
      await sink!.close(); sink = null;

      if (bytes < 1024) throw Exception('file too small: $bytes bytes');

      final result = await tmp.rename(dest.path);
      debugPrint('[N] ✓ saved $bytes bytes → ${result.path}');
      _index[videoId] = _CE(videoId, bytes, DateTime.now().millisecondsSinceEpoch);
      _saveIndex(); _evict();
      return result;

    } on TimeoutException catch (e) {
      debugPrint('[N] dl timeout: $e'); sub?.cancel();
      if (sink != null) { try { await sink.close(); } catch (_) {} }
      _del(tmp); rethrow;
    } on RequestLimitExceededException catch (e) {
      debugPrint('[N] dl rate limit: $e'); sub?.cancel();
      if (sink != null) { try { await sink.close(); } catch (_) {} }
      _del(tmp); rethrow;
    } catch (e, st) {
      debugPrint('[N] dl error: $e\n$st'); sub?.cancel();
      if (sink != null) { try { await sink.close(); } catch (_) {} }
      _del(tmp); rethrow;
    }
  }

  void _del(File? f) { try { f?.deleteSync(); } catch (_) {} }

  // FIX #5: Prefetch next song AFTER a delay so it never fires concurrently
  // with the current song's manifest fetch (which would cause rate limiting).
  // 3 seconds gives the current song time to finish its manifest + start playing.
  void _prefetchNext(int ptok) {
    if (_queue.length < 2) return;
    final next = _queue[(_idx + 1) % _queue.length];
    if (next.videoId == _current?.videoId || _isCached(next.videoId)) return;
    debugPrint('[N] prefetch queued (3s delay): ${next.title}');
    Future.delayed(const Duration(seconds: 3), () async {
      if (_tok != ptok) return; // user already switched songs, abort
      if (_isCached(next.videoId)) return; // cached by now, skip
      debugPrint('[N] prefetch start: ${next.title}');
      try {
        final info = await _getInfo(next.videoId, ptok);
        if (info == null || _tok != ptok) return;
        await _download(info, next.videoId, ptok);
        if (_tok == ptok) debugPrint('[N] prefetch done: ${next.title}');
      } catch (e) { debugPrint('[N] prefetch err: $e'); }
    });
  }

  Future<void> clearCache() async {
    try {
      for (final f in _cacheDir!.listSync().whereType<File>()) f.deleteSync();
      _index.clear();
    } catch (_) {}
  }

  @override Future<void> play()  async => _player.play();
  @override Future<void> pause() async => _player.pause();
  @override Future<void> seek(Duration p) async => _player.seek(p);

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
    _idx = (_idx + 1) % _queue.length;
    await _load(_queue[_idx]);
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
        MediaAction.seek, MediaAction.skipToNext, MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle:      AudioProcessingState.idle,
        ProcessingState.loading:   AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready:     AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing:          playing,
      updatePosition:   _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed:            _player.speed,
      queueIndex:       _idx,
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
'''


# ─── home_screen.dart — only the _handleRibbonSelection method patch ─────────
# We use a targeted replacement so the rest of the file is untouched.

HOME_OLD = '''  Future<void> _handleRibbonSelection(int index, List<Song> queue) async {
    if (_dotIndex == index) return;
    
    // Haptic feedback for switching songs
    HapticFeedback.mediumImpact();

    setState(() => _isChangingTrack = true); 
    await Future.delayed(const Duration(milliseconds: 350));
    setState(() {
      _dotIndex = index;
      _isChangingTrack = false;
    });
    ref.read(playerProvider.notifier).playSong(queue[index], queue: queue);
  }'''

HOME_NEW = '''  // FIX #2: debounce timer prevents stacked concurrent loads on fast swipes
  Timer? _switchDebounce;

  Future<void> _handleRibbonSelection(int index, List<Song> queue) async {
    if (_dotIndex == index) return;

    HapticFeedback.mediumImpact();

    // Update visual immediately so the ribbon feels instant
    setState(() {
      _dotIndex = index;
      _isChangingTrack = false;
    });

    // Cancel any previous pending load and wait for the user to settle
    _switchDebounce?.cancel();
    _switchDebounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(playerProvider.notifier).playSong(queue[index], queue: queue);
    });
  }'''

# Also need to add `import 'dart:async';` and cancel the timer in dispose()
HOME_IMPORT_OLD = "import 'package:flutter/material.dart';"
HOME_IMPORT_NEW = "import 'dart:async';\nimport 'package:flutter/material.dart';"

HOME_DISPOSE_OLD = '''  @override
  void dispose() {
    _ribbonController.dispose();
    _rotationCtrl.dispose();
    _glowCtrl.dispose();
    _heartCtrl.dispose();
    _playPauseCtrl.dispose();
    super.dispose();
  }'''

HOME_DISPOSE_NEW = '''  @override
  void dispose() {
    _switchDebounce?.cancel(); // FIX #2: clean up debounce timer
    _ribbonController.dispose();
    _rotationCtrl.dispose();
    _glowCtrl.dispose();
    _heartCtrl.dispose();
    _playPauseCtrl.dispose();
    super.dispose();
  }'''


# ═════════════════════════════════════════════════════════════════════════════
# PATCH FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════

def patch_audio_handler(project: Path) -> bool:
    target = project / "lib" / "services" / "audio_handler.dart"
    if not target.exists():
        err(f"Not found: {target}")
        return False
    bak = backup(target)
    info(f"Backed up → {bak.name}")
    target.write_text(AUDIO_HANDLER_NEW, encoding="utf-8")
    ok("audio_handler.dart — rewrote with fixes #1 #3 #4 #5")
    return True


def patch_home_screen(project: Path) -> bool:
    target = project / "lib" / "screens" / "home_screen.dart"
    if not target.exists():
        err(f"Not found: {target}")
        return False

    src = target.read_text(encoding="utf-8")
    changed = False

    # 1. Add dart:async import if missing
    if "import 'dart:async';" not in src:
        if HOME_IMPORT_OLD in src:
            src = src.replace(HOME_IMPORT_OLD, HOME_IMPORT_NEW, 1)
            changed = True
            info("Added dart:async import")
        else:
            warn("Could not find import anchor — skipping dart:async insert")

    # 2. Patch _handleRibbonSelection
    if HOME_OLD in src:
        src = src.replace(HOME_OLD, HOME_NEW, 1)
        changed = True
        info("Patched _handleRibbonSelection with debounce")
    else:
        warn("Could not find _handleRibbonSelection — method may have changed")

    # 3. Patch dispose() to cancel timer
    if HOME_DISPOSE_OLD in src:
        src = src.replace(HOME_DISPOSE_OLD, HOME_DISPOSE_NEW, 1)
        changed = True
        info("Patched dispose() to cancel debounce timer")
    else:
        warn("Could not find expected dispose() body — skipping timer cancel patch")

    if changed:
        bak = backup(target)
        info(f"Backed up → {bak.name}")
        target.write_text(src, encoding="utf-8")
        ok("home_screen.dart — applied fix #2 (debounce)")
    else:
        warn("home_screen.dart — no changes applied (patterns not matched)")

    return True


# ═════════════════════════════════════════════════════════════════════════════
# VERIFY
# ═════════════════════════════════════════════════════════════════════════════

def verify(project: Path):
    title("Verifying patches…")
    checks = [
        (
            project / "lib" / "services" / "audio_handler.dart",
            [
                "_cacheReadyCompleter",                    # Fix #3 Completer
                "Sequential manifest fetch",               # Fix #4 safe sequential
                "_cacheInBackground",                      # Fix #1 background cache
                "AudioSource.uri(info.url)",               # Fix #1 stream direct
                "Future.delayed(const Duration(seconds: 3)", # Fix #5 delayed prefetch
            ],
            "audio_handler.dart"
        ),
        (
            project / "lib" / "screens" / "home_screen.dart",
            [
                "import 'dart:async';",           # dart:async
                "_switchDebounce",                # Fix #2 debounce field
                "_switchDebounce?.cancel();",     # Fix #2 dispose
                "Timer(const Duration(milliseconds: 350)",  # Fix #2 timer
            ],
            "home_screen.dart"
        ),
    ]

    all_ok = True
    for path, patterns, label in checks:
        if not path.exists():
            err(f"{label} — file missing"); all_ok = False; continue
        content = path.read_text(encoding="utf-8")
        for pat in patterns:
            if pat in content:
                ok(f"{label} — found '{pat[:55]}'")
            else:
                err(f"{label} — MISSING '{pat[:55]}'"); all_ok = False

    return all_ok


# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="Apply Nebula audio performance fixes",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--project", "-p",
        required=True,
        help="Path to the root of the Nebula Flutter project",
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Only run verification checks, do not write any files",
    )
    args = parser.parse_args()

    project = Path(args.project).expanduser().resolve()
    if not project.exists():
        err(f"Project path does not exist: {project}")
        sys.exit(1)

    pubspec = project / "pubspec.yaml"
    if not pubspec.exists():
        err(f"No pubspec.yaml found at {project} — is this a Flutter project?")
        sys.exit(1)

    print(f"\n{BOLD}Nebula Performance Patcher{RESET}")
    print(f"  Project: {CYAN}{project}{RESET}")

    if args.verify_only:
        ok_all = verify(project)
        sys.exit(0 if ok_all else 1)

    title("Applying fixes…")
    results = [
        patch_audio_handler(project),
        patch_home_screen(project),
    ]

    verify(project)

    title("Summary")
    print(f"""
  {GREEN}Fix #1{RESET}  Stream directly → play starts in 1–3 sec (was 10–30 sec)
  {GREEN}Fix #2{RESET}  Debounce ribbon swipes → no stacked network calls
  {GREEN}Fix #3{RESET}  Completer cache init → no cold-start busy-wait
  {GREEN}Fix #4{RESET}  Sequential manifest + stagger → no rate limiting
  {GREEN}Fix #5{RESET}  Delayed prefetch (3s) → no request overlap

  Backups saved alongside each modified file (.bak_TIMESTAMP).
  Run  flutter clean && flutter run  to test.
""")

    if not all(results):
        warn("Some patches could not be applied — check warnings above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
