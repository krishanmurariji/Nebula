import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/player_screen.dart';
import '../theme/noor_palette.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with TickerProviderStateMixin {
  late AnimationController _rotationCtrl;

  @override
  void initState() {
    super.initState();
    _rotationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ps = ref.watch(playerProvider);

    // Use displaySong — reflects pendingSong immediately so thumbnail
    // never shows the previous track after tapping a new one
    final song = ps.displaySong;
    if (song == null) return const SizedBox.shrink();

    final playing = ps.status == NebulaPlayerStatus.playing;
    final loading = ps.status == NebulaPlayerStatus.loading ||
        (ps.pendingSong != null &&
            ps.status != NebulaPlayerStatus.playing &&
            ps.status != NebulaPlayerStatus.paused);
    final isError = ps.status == NebulaPlayerStatus.error;
    final isDark  = ref.watch(themeProvider) == ThemeMode.dark;

    final t = NoorTheme.byMode(isDark);
    final cardBg  = t.ac;                       // solid accent bar
    final textCol = t.bg;                       // text sits on the accent
    final mutedCol= t.bg.withOpacity(0.78);

    if (playing && !loading) {
      if (!_rotationCtrl.isAnimating) _rotationCtrl.repeat();
    } else {
      if (_rotationCtrl.isAnimating) _rotationCtrl.stop();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PlayerScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: t.soft, width: 1),
          ),
          child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(width: 4),

                    // ── Mini Gramophone ─────────────────────────────────────
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Spinning record
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOutCubic,
                            left: playing ? 6 : -22,
                            top: 7,
                            child: RotationTransition(
                              turns: _rotationCtrl,
                              child: _buildMiniRecord(
                                  50, isDark, song.thumbnailUrl),
                            ),
                          ),

                          // Needle
                          Positioned(
                            top: 10,
                            right: 10,
                            child: AnimatedRotation(
                              turns: playing ? 0.0 : -0.15,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutBack,
                              alignment: Alignment.topRight,
                              child: _buildMiniNeedle(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 4),

                    // ── Song info ───────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              song.title,
                              key: ValueKey(song.videoId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: textCol),
                            ),
                          ),
                          const SizedBox(height: 2),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              // Show cooldown countdown, loading, error, or artist
                              loading
                                  ? 'Loading…'
                                  : isError
                                      ? (ps.cooldownSeconds > 0
                                          ? 'Retry in ${ps.cooldownSeconds}s…'
                                          : 'Tap ↺ to retry')
                                      : song.artist,
                              key: ValueKey(song.videoId +
                                  (loading
                                      ? '_l'
                                      : isError
                                          ? '_e${ps.cooldownSeconds}'
                                          : '_p')),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: mutedCol,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Controls ────────────────────────────────────────────
                    _controlIcon(Icons.skip_previous_rounded, mutedCol,
                        () => ref.read(playerProvider.notifier).skipPrevious()),

                    // Play/pause button — shows loader spinner when loading
                    GestureDetector(
                      onTap: () {
                        if (loading) return;
                        if (isError) {
                          ref.read(playerProvider.notifier).retryCurrentSong();
                        } else {
                          ref.read(playerProvider.notifier).togglePlay();
                        }
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: t.bg,
                          shape: BoxShape.circle,
                        ),
                        child: loading
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                    color: t.ac, strokeWidth: 2.5),
                              )
                            : Icon(
                                isError
                                    ? Icons.refresh_rounded
                                    : (playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded),
                                color: t.ac,
                                size: 24,
                              ),
                      ),
                    ),

                    _controlIcon(Icons.skip_next_rounded, mutedCol,
                        () => ref.read(playerProvider.notifier).skipNext()),

                    const SizedBox(width: 10),
                  ],
                ),
              ),


            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _controlIcon(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  // ── UPDATED TO COMPLETELY FILL THE CIRCLE ──
  Widget _buildMiniRecord(double size, bool isDark, String thumbUrl) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: Color.lerp(NoorTheme.byMode(isDark).ac, Colors.black, 0.6),
          shape: BoxShape.circle),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withOpacity(0.05), width: 1),
            ),
          ),
          Container(
            width: size * 0.5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withOpacity(0.05), width: 1),
            ),
          ),
          Container(
            width: size * 0.38,
            height: size * 0.38,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Colors.black),
            child: ClipOval(
              child: thumbUrl.isNotEmpty
                  ? Transform.scale(
                      scale: 1.35, // Ensures image fills completely
                      child: CachedNetworkImage(
                          imageUrl: thumbUrl, 
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity),
                    )
                  : const Icon(Icons.music_note,
                      color: Colors.white24, size: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniNeedle(bool isDark) {
    final armColor = NoorTheme.byMode(isDark).bg;
    return SizedBox(
      width: 24,
      height: 34,
      child: CustomPaint(painter: _MiniArmPainter(armColor)),
    );
  }
}

class _MiniArmPainter extends CustomPainter {
  final Color color;
  _MiniArmPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(size.width, 0);
    path.quadraticBezierTo(size.width * 0.2, size.height * 0.1,
        size.width * 0.4, size.height * 0.9);
    canvas.drawPath(path, paint);

    final headPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(size.width * 0.4, size.height * 0.9), 3, headPaint);
    canvas.drawCircle(Offset(size.width, 0), 4, headPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}