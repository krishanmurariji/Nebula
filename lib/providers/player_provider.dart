import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';

enum NebulaPlayerStatus { idle, loading, playing, paused, error }

class NebulaPlayerState {
  final Song? song;
  final Song? pendingSong;   // Set instantly on tap — drives UI before audio confirms
  final NebulaPlayerStatus status;
  final String? error;
  final Duration position;
  final Duration duration;
  final List<Song> queue;
  final int queueIndex;
  final int cooldownSeconds; // Seconds until auto-retry fires (0 = not counting down)

  const NebulaPlayerState({
    this.song,
    this.pendingSong,
    this.status = NebulaPlayerStatus.idle,
    this.error,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.queueIndex = 0,
    this.cooldownSeconds = 0,
  });

  /// The song to display — pendingSong wins so UI updates instantly on tap
  Song? get displaySong => pendingSong ?? song;

  NebulaPlayerState copyWith({
    Song? song,
    Song? pendingSong,
    bool clearPending = false,
    NebulaPlayerStatus? status,
    String? error,
    bool clearError = false,
    Duration? position,
    Duration? duration,
    List<Song>? queue,
    int? queueIndex,
    int? cooldownSeconds,
  }) =>
      NebulaPlayerState(
        song: song ?? this.song,
        pendingSong: clearPending ? null : (pendingSong ?? this.pendingSong),
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        position: position ?? this.position,
        duration: duration ?? this.duration,
        queue: queue ?? this.queue,
        queueIndex: queueIndex ?? this.queueIndex,
        cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      );
}

class PlayerNotifier extends StateNotifier<NebulaPlayerState> {
  final NebulaAudioHandler _handler;
  Timer? _countdownTimer;

  PlayerNotifier(this._handler) : super(const NebulaPlayerState()) {
    _handler.playbackState.listen(_onPlayback);
    _handler.player.positionStream.listen(
        (pos) => state = state.copyWith(position: pos));
    _handler.player.durationStream.listen(
        (dur) { if (dur != null) state = state.copyWith(duration: dur); });
  }

  void _onPlayback(PlaybackState ps) {
    NebulaPlayerStatus st;
    switch (ps.processingState) {
      case AudioProcessingState.loading:
      case AudioProcessingState.buffering:
        st = NebulaPlayerStatus.loading;
        break;
      case AudioProcessingState.ready:
        st = ps.playing
            ? NebulaPlayerStatus.playing
            : NebulaPlayerStatus.paused;
        break;
      case AudioProcessingState.error:
        st = NebulaPlayerStatus.error;
        break;
      default:
        st = NebulaPlayerStatus.idle;
    }

    final handlerSong = _handler.currentSong ?? state.song;
    final isNowActive = st == NebulaPlayerStatus.playing ||
        st == NebulaPlayerStatus.paused;

    if (st == NebulaPlayerStatus.error) {
      _startCooldownCountdown();
    } else {
      _stopCooldownCountdown();
    }

    state = state.copyWith(
      song: handlerSong,
      clearPending: isNowActive,
      status: st,
      queue: _handler.songQueue,
      queueIndex: _handler.songQueueIndex,
      clearError: st != NebulaPlayerStatus.error,
    );
  }

  // ── Countdown timer ───────────────────────────────────────────────────────
  void _startCooldownCountdown() {
    _stopCooldownCountdown();
    _tickCountdown();
    _countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
  }

  void _tickCountdown() {
    if (!mounted) return;
    final secs = _handler.globalCooldownSeconds;
    state = state.copyWith(cooldownSeconds: secs);

    if (secs == 0 && state.status == NebulaPlayerStatus.error) {
      _stopCooldownCountdown();
      retryCurrentSong();
    }
  }

  void _stopCooldownCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) state = state.copyWith(cooldownSeconds: 0);
  }

  // ── Public actions ────────────────────────────────────────────────────────

  Future<void> playSong(Song song, {List<Song>? queue}) async {
    final q   = queue ?? [song];
    final idx = q.indexOf(song);

    _stopCooldownCountdown();

    state = state.copyWith(
      pendingSong: song,
      status: NebulaPlayerStatus.loading,
      queue: q,
      queueIndex: idx < 0 ? 0 : idx,
      clearError: true,
      position: Duration.zero,
      duration: Duration.zero,
      cooldownSeconds: 0,
    );

    try {
      await _handler.playSong(song, queue: q, index: idx < 0 ? 0 : idx);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          clearPending: true,
          status: NebulaPlayerStatus.error,
          error: 'Could not play. Retrying automatically…',
        );
        _startCooldownCountdown();
      }
    }
  }

  Future<void> retryCurrentSong() async {
    final song = state.displaySong;
    if (song == null) return;
    await playSong(song,
        queue: state.queue.isNotEmpty ? state.queue : null);
  }

  Future<void> togglePlay() async {
    if (state.status == NebulaPlayerStatus.playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final newQueue = [...state.queue];
    final item = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, item);
    
    state = state.copyWith(queue: newQueue);
    
    final mediaItems = newQueue.map((song) => MediaItem(
      id: song.videoId,
      title: song.title,
      artist: song.artist,
      artUri: Uri.parse(song.thumbnailUrl),
    )).toList();

    await _handler.updateQueue(mediaItems);
  }

  // --- NEW METHOD ADDED HERE ---
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= state.queue.length) return;

    final newQueue = List<Song>.from(state.queue);
    newQueue.removeAt(index);

    state = state.copyWith(queue: newQueue);

    final mediaItems = newQueue.map((song) => MediaItem(
      id: song.videoId,
      title: song.title,
      artist: song.artist,
      artUri: Uri.parse(song.thumbnailUrl),
    )).toList();

    await _handler.updateQueue(mediaItems);
  }

  Future<void> setVolume(double volume) async {
    await _handler.player.setVolume(volume);
  }

  Future<void> skipNext()       async => _handler.skipToNext();
  Future<void> skipPrevious()   async => _handler.skipToPrevious();
  Future<void> seek(Duration d) async => _handler.seek(d);

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}

final playerProvider =
    StateNotifierProvider<PlayerNotifier, NebulaPlayerState>((ref) {
  return PlayerNotifier(ref.read(audioHandlerProvider));
});