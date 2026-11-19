import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/last_played_provider.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/queue_rules.dart';
import '../screens/player_screen.dart';
import '../theme/noor_disc.dart';
import '../theme/noor_gap_border.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_play_pause.dart';
import '../theme/noor_song_card.dart';

/// The bottom card: the song that is playing (or, after a restart, the last
/// one played, paused). Same look as a song card. The record slides half out
/// of the card when paused and slides in and spins while playing, with a
/// small tone arm resting on it.
///
/// * tap: opens the player;
/// * swipe left / right: next / previous song (playlist > favorites >
///   history; the same song again when there is no other). The next card
///   slides in beside the one being dragged; let go early, or drag back,
///   and both return;
/// * double tap: like / unlike.
class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key, this.onOpen});

  /// What a tap / swipe up does; opens the player by default.
  final VoidCallback? onOpen;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 12));

  /// Horizontal position of the card while it is swiped, in pixels.
  late final AnimationController _dx =
      AnimationController.unbounded(vsync: this);
  double _width = 360;
  bool _changing = false;

  @override
  void dispose() {
    _spin.dispose();
    _dx.dispose();
    super.dispose();
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_changing) return;
    // The card stays under the finger.
    _dx.value += d.primaryDelta!;
  }

  /// Space between the card and the one sliding in beside it.
  static const double _gap = 36; // room for its half-out record

  Future<void> _dragEnd(DragEndDetails d, Song song) async {
    if (_changing) return;
    final v = d.primaryVelocity ?? 0;
    final x = _dx.value;
    final far = x.abs() > _width * 0.33;
    final fling = v.abs() > 700 && v.sign == x.sign;
    if (!(far || fling) || x == 0) {
      // Let go too early, or dragged back: both cards return.
      await _dx.animateTo(0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutBack);
      return;
    }
    _changing = true;
    final dir = x.sign; // swiped right (+1): previous; left (-1): next
    // The incoming card slides into place...
    final left = 1 - x.abs() / (_width + _gap);
    await _dx.animateTo(dir * (_width + _gap),
        duration: Duration(milliseconds: (140 + 300 * left).round()),
        curve: Curves.easeOutCubic);
    if (!mounted) return;
    // ...and becomes the card: same place, now the song that plays.
    _step(song, dir > 0 ? -1 : 1);
    _dx.value = 0;
    _changing = false;
  }

  Song _neighbour(Song current, int step) => neighbourOf(current, step,
      playlists: ref.read(playlistProvider),
      liked: ref.read(likedSongsProvider),
      history: ref.read(historyProvider));

  void _openPlayer() => widget.onOpen != null
      ? widget.onOpen!()
      : Navigator.push(
          context, MaterialPageRoute(builder: (_) => const PlayerScreen()));

  List<Song> _context(Song s) => contextListFor(s,
      playlists: ref.read(playlistProvider),
      liked: ref.read(likedSongsProvider),
      history: ref.read(historyProvider));

  void _start(Song s) =>
      ref.read(playerProvider.notifier).playSong(s, queue: _context(s));

  void _step(Song current, int step) {
    HapticFeedback.selectionClick();
    _start(_neighbour(current, step));
  }

  @override
  Widget build(BuildContext context) {
    final ps = ref.watch(playerProvider);
    final restored = ref.watch(lastPlayedProvider);
    final liveSong = ps.displaySong;
    final song = liveSong ?? restored;
    if (song == null) return const SizedBox.shrink();

    final live = liveSong != null;
    final playing = live && ps.status == NebulaPlayerStatus.playing;
    final loading = live &&
        (ps.status == NebulaPlayerStatus.loading ||
            (ps.pendingSong != null &&
                ps.status != NebulaPlayerStatus.playing &&
                ps.status != NebulaPlayerStatus.paused));
    final isError = live && ps.status == NebulaPlayerStatus.error;
    final t = NoorTheme.of(context);

    if (playing && !loading) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
    }

    void playPause() {
      HapticFeedback.lightImpact();
      if (loading) return;
      if (!live) return _start(song);
      if (isError) {
        ref.read(playerProvider.notifier).retryCurrentSong();
      } else {
        ref.read(playerProvider.notifier).togglePlay();
      }
    }

    final subtitle = loading
        ? (ps.cooldownSeconds > 0
            ? 'YouTube busy · plays in ${ps.cooldownSeconds}s'
            : 'Loading…')
        : isError
            ? (ps.cooldownSeconds > 0
                ? 'Retry in ${ps.cooldownSeconds}s…'
                : 'Tap play to retry')
            : song.artist;

    const height = 64.0;
    const disc = 52.0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 16, 14),
        child: LayoutBuilder(builder: (context, box) {
          _width = box.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openPlayer,
            onDoubleTap: () {
              HapticFeedback.mediumImpact();
              ref.read(likedProvider.notifier).toggle(song);
            },
            onHorizontalDragUpdate: _dragUpdate,
            onHorizontalDragEnd: (d) => _dragEnd(d, song),
            // Swipe up: the full player.
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -300) _openPlayer();
            },
            child: AnimatedBuilder(
              animation: _dx,
              builder: (context, card) {
                final x = _dx.value;
                final p = (x.abs() / _width).clamp(0.0, 1.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Beside the card: the song a swipe this way plays,
                    // sliding in with it.
                    if (x != 0)
                      Positioned.fill(
                        child: Transform.translate(
                          offset: Offset(x - x.sign * (_width + _gap), 0),
                          child: _PeekCard(
                              song: _neighbour(song, x > 0 ? -1 : 1),
                              height: height,
                              disc: disc),
                        ),
                      ),
                    Transform.translate(
                      offset: Offset(x, 0),
                      child: Opacity(opacity: 1 - p * 0.3, child: card),
                    ),
                  ],
                );
              },
              child: CustomPaint(
                  foregroundPainter: NoorGapBorderPainter(
                      color: t.ac, radius: kNoorCardRadius),
                  child: Container(
                    height: height,
                    decoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: BorderRadius.circular(kNoorCardRadius),
                      boxShadow: [
                        BoxShadow(
                            color: t.ac.withOpacity(0.10),
                            blurRadius: 18,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Record + tone arm. Paused: the record sits half outside
                        // the card's left end.
                        SizedBox(
                          width: 78,
                          height: height,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 550),
                                curve: Curves.easeInOutCubic,
                                left: playing ? 5 : -disc / 2,
                                top: (height - 2 - disc) / 2,
                                child: RotationTransition(
                                  turns: _spin,
                                  child: NoorDisc(
                                      url: song.thumbnailUrl, size: disc),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                left: 40,
                                child: AnimatedRotation(
                                  turns: playing
                                      ? 0.0
                                      : 0.12, // lifts up, off the record
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeOutBack,
                                  alignment: Alignment.topRight,
                                  child: SizedBox(
                                    width: 26,
                                    height: 36,
                                    child:
                                        CustomPaint(painter: _ArmPainter(t.ac)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(song.title,
                                    key: ValueKey(song.videoId),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: noorSongTitleStyle(t.ac, size: 19)),
                              ),
                              const SizedBox(height: 2),
                              Text(subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: noorArtistStyle(t.mute)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        NoorPlayPauseButton(
                            playing: playing,
                            loading: loading,
                            onTap: playPause),
                        const SizedBox(width: 12),
                      ],
                    ),
                  )),
            ),
          );
        }),
      ),
    );
  }
}

/// The card of the song a swipe would play: the bottom card's look with
/// the record resting half outside, as it shows while that song loads.
class _PeekCard extends StatelessWidget {
  const _PeekCard(
      {required this.song, required this.height, required this.disc});
  final Song song;
  final double height;
  final double disc;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return IgnorePointer(
      child: CustomPaint(
          foregroundPainter:
              NoorGapBorderPainter(color: t.ac, radius: kNoorCardRadius),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(kNoorCardRadius),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  height: height,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                      left: -disc / 2,
                      top: (height - 2 - disc) / 2,
                      child: NoorDisc(url: song.thumbnailUrl, size: disc),
                    ),
                  ]),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: noorSongTitleStyle(t.ac, size: 19)),
                      const SizedBox(height: 2),
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: noorArtistStyle(t.mute)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                NoorPlayPauseButton(
                    playing: false, loading: false, onTap: () {}),
                const SizedBox(width: 12),
              ],
            ),
          )),
    );
  }
}

/// A slim tone arm: pivot top-right, curving down to a small head.
class _ArmPainter extends CustomPainter {
  _ArmPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final head = Offset(size.width * 0.25, size.height * 0.88);
    canvas.drawPath(
        Path()
          ..moveTo(size.width - 4, 4)
          ..quadraticBezierTo(
              size.width * 0.3, size.height * 0.2, head.dx, head.dy),
        p);
    final fill = Paint()..color = color;
    canvas.drawCircle(Offset(size.width - 4, 4), 3.4, fill);
    canvas.drawCircle(
        Offset(size.width - 4, 4), 1.4, Paint()..color = Colors.white);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: head, width: 5, height: 7),
            const Radius.circular(1.5)),
        fill);
  }

  @override
  bool shouldRepaint(_ArmPainter old) => old.color != color;
}
