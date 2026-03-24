import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';

enum NebulaPlayerStatus { idle, loading, playing, paused, error }

class NebulaPlayerState {
  final Song? song;
  final NebulaPlayerStatus status;
  final String? error;
  final Duration position;
  final Duration duration;
  final List<Song> queue;
  final int queueIndex;

  const NebulaPlayerState({
    this.song, this.status = NebulaPlayerStatus.idle, this.error,
    this.position = Duration.zero, this.duration = Duration.zero,
    this.queue = const [], this.queueIndex = 0,
  });

  NebulaPlayerState copyWith({
    Song? song, NebulaPlayerStatus? status, String? error,
    Duration? position, Duration? duration, List<Song>? queue, int? queueIndex,
  }) => NebulaPlayerState(
    song:       song       ?? this.song,
    status:     status     ?? this.status,
    error:      error,
    position:   position   ?? this.position,
    duration:   duration   ?? this.duration,
    queue:      queue      ?? this.queue,
    queueIndex: queueIndex ?? this.queueIndex,
  );
}

class PlayerNotifier extends StateNotifier<NebulaPlayerState> {
  final NebulaAudioHandler _handler;

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
        st = NebulaPlayerStatus.loading; break;
      case AudioProcessingState.ready:
        st = ps.playing ? NebulaPlayerStatus.playing : NebulaPlayerStatus.paused;
        break;
      case AudioProcessingState.error:
        st = NebulaPlayerStatus.error; break;
      default:
        st = NebulaPlayerStatus.idle;
    }
    state = state.copyWith(
      song:       _handler.currentSong ?? state.song,
      status:     st,
      queue:      _handler.songQueue,
      queueIndex: _handler.songQueueIndex,
    );
  }

  Future<void> playSong(Song song, {List<Song>? queue}) async {
    final q   = queue ?? [song];
    final idx = q.indexOf(song);
    state = state.copyWith(
      song: song, status: NebulaPlayerStatus.loading,
      queue: q, queueIndex: idx < 0 ? 0 : idx,
      error: null, position: Duration.zero, duration: Duration.zero,
    );
    try {
      await _handler.playSong(song, queue: q, index: idx < 0 ? 0 : idx);
    } catch (e) {
      state = state.copyWith(
        status: NebulaPlayerStatus.error, error: 'Could not play. Try another.');
    }
  }

  Future<void> togglePlay() async {
    if (state.status == NebulaPlayerStatus.playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> skipNext()       async => _handler.skipToNext();
  Future<void> skipPrevious()   async => _handler.skipToPrevious();
  Future<void> seek(Duration d) async => _handler.seek(d);
}

final playerProvider =
    StateNotifierProvider<PlayerNotifier, NebulaPlayerState>((ref) {
  return PlayerNotifier(ref.read(audioHandlerProvider));
});
