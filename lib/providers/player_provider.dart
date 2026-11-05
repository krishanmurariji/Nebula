import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';

enum NebulaPlayerStatus { idle, loading, playing, paused, error }

class NebulaPlayerState {
  final Song? song;
  final Song? pendingSong;   // Set instantly on tap — drives UI before audio confirms
  final NebulaPlayerStatus status;
  final String? error;
  final List<Song> queue;
  final int queueIndex;
  final int cooldownSeconds; // Seconds until auto-retry fires (0 = not counting down)
  final String? notice;      // Transient message, e.g. "Skipped unavailable song"

  const NebulaPlayerState({
    this.song,
    this.pendingSong,
    this.status = NebulaPlayerStatus.idle,
    this.error,
    this.queue = const [],
    this.queueIndex = 0,
    this.cooldownSeconds = 0,
    this.notice,
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
    List<Song>? queue,
    int? queueIndex,
    int? cooldownSeconds,
    String? notice,
    bool clearNotice = false,
  }) =>
      NebulaPlayerState(
        song: song ?? this.song,
        pendingSong: clearPending ? null : (pendingSong ?? this.pendingSong),
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        queue: queue ?? this.queue,
        queueIndex: queueIndex ?? this.queueIndex,
        cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

class PlayerNotifier extends StateNotifier<NebulaPlayerState> {
  final NebulaAudioHandler _handler;
  Timer? _countdownTimer;
  Timer? _noticeTimer;
  final List<StreamSubscription<dynamic>> _subs = [];

  // True once a rate-limit countdown has actually been shown. Auto-retry fires
  // only after such a countdown, and only once per failure, so a song that
  // keeps failing can never turn into a tight retry loop (the handler already
  // does its own bounded retries and skipping).
  bool _sawCooldown = false;

  PlayerNotifier(this._handler) : super(const NebulaPlayerState()) {
    _subs.add(_handler.playbackState.listen(_onPlayback));
    _subs.add(_handler.queueChanges.listen((_) => _syncQueue()));
    _subs.add(_handler.notices.listen(_showNotice));
  }

  void _syncQueue() {
    if (!mounted) return;
    state = state.copyWith(
      song: _handler.currentSong,
      clearPending: true, // the handler now owns what is current
      queue: _handler.songQueue,
      queueIndex: _handler.songQueueIndex,
    );
  }

  void _showNotice(String msg) {
    if (!mounted) return;
    state = state.copyWith(notice: msg);
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) state = state.copyWith(clearNotice: true);
    });
  }

  void _onPlayback(PlaybackState ps) {
    if (!mounted) return;
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

    if (secs > 0) {
      _sawCooldown = true;
    } else if (_sawCooldown && state.status == NebulaPlayerStatus.error) {
      // Rate limit has expired: retry exactly once.
      _sawCooldown = false;
      _stopCooldownCountdown();
      retryCurrentSong();
    } else if (state.status != NebulaPlayerStatus.error) {
      _stopCooldownCountdown();
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
      cooldownSeconds: 0,
    );

    _sawCooldown = false;
    try {
      await _handler.playSong(song, queue: q, index: idx < 0 ? 0 : idx);
    } catch (e) {
      // The handler reports failures through playbackState; this is only a
      // last-resort guard against an unexpected exception.
      if (mounted) {
        state = state.copyWith(
          clearPending: true,
          status: NebulaPlayerStatus.error,
          error: 'Could not play this song.',
        );
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

  /// [newIndex] is the position after removal (the UI already adjusts it).
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    _handler.reorderQueue(oldIndex, newIndex);
    _syncQueue();
  }

  Future<void> removeFromQueue(int index) async {
    _handler.removeFromQueue(index);
    _syncQueue();
  }

  Future<void> setVolume(double volume) async {
    await _handler.player.setVolume(volume);
  }

  Future<void> skipNext()       async => _handler.skipToNext();
  Future<void> skipPrevious()   async => _handler.skipToPrevious();
  Future<void> seek(Duration d) async => _handler.seek(d);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _noticeTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}

/// Playback position and total length. Kept OUT of [NebulaPlayerState] on
/// purpose: it changes several times a second, and putting it in the main
/// state made every widget that watches the player rebuild constantly.
class PlaybackProgress {
  final Duration position;
  final Duration duration;
  const PlaybackProgress(this.position, this.duration);
  static const zero = PlaybackProgress(Duration.zero, Duration.zero);

  /// 0.0 – 1.0
  double get fraction => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;
}

final playbackProgressProvider =
    StreamProvider.autoDispose<PlaybackProgress>((ref) {
  final player = ref.watch(audioHandlerProvider).player;
  final controller = StreamController<PlaybackProgress>();
  var position = player.position;
  Duration duration = player.duration ?? Duration.zero;

  void emit() {
    if (!controller.isClosed) {
      controller.add(PlaybackProgress(position, duration));
    }
  }

  final subs = <StreamSubscription<dynamic>>[
    player.positionStream.listen((p) {
      position = p;
      emit();
    }),
    // null means "new song, length unknown yet" → reset to zero.
    player.durationStream.listen((d) {
      duration = d ?? Duration.zero;
      emit();
    }),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    controller.close();
  });
  emit();
  return controller.stream;
});

final playerProvider =
    StateNotifierProvider<PlayerNotifier, NebulaPlayerState>((ref) {
  return PlayerNotifier(ref.read(audioHandlerProvider));
});