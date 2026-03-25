import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for Haptics
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'mini_player.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  const HomeScreen({super.key, required this.onNavigate});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  int _dotIndex = 0;
  late PageController _ribbonController;

  late AnimationController _rotationCtrl;
  late AnimationController _glowCtrl; 
  late AnimationController _heartCtrl;
  late AnimationController _playPauseCtrl;
  
  late Animation<double> _heartScale;
  late Animation<double> _heartOpacity;
  late Animation<double> _playPauseScale;
  late Animation<double> _playPauseOpacity;
  late Animation<double> _glowScale;

  bool _isBrokenHeart = false;
  bool _showingPlayIcon = false;
  bool _isChangingTrack = false;

  @override
  void initState() {
    super.initState();
    _ribbonController = PageController(viewportFraction: 0.25, initialPage: _dotIndex);
    
    _rotationCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 15));
    
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _glowScale = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOutSine)
    );

    _heartCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _heartScale = Tween<double>(begin: 0.5, end: 1.3).animate(CurvedAnimation(parent: _heartCtrl, curve: Curves.elasticOut));
    _heartOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _heartCtrl, curve: Curves.easeOut));

    _playPauseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _playPauseScale = Tween<double>(begin: 0.5, end: 1.3).animate(CurvedAnimation(parent: _playPauseCtrl, curve: Curves.easeOutBack));
    _playPauseOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _playPauseCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ribbonController.dispose();
    _rotationCtrl.dispose();
    _glowCtrl.dispose();
    _heartCtrl.dispose();
    _playPauseCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRibbonSelection(int index, List<Song> queue) async {
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
  }

  void _handleMainTap(Song? currentSong, Song songToPlay, bool isPlaying, List<Song> queue) {
    // Light tap when clicking the record
    HapticFeedback.lightImpact();

    setState(() => _showingPlayIcon = !isPlaying);
    if (currentSong == null || currentSong.videoId != songToPlay.videoId || ref.read(playerProvider).status == NebulaPlayerStatus.idle) {
      ref.read(playerProvider.notifier).playSong(songToPlay, queue: queue);
    } else {
      ref.read(playerProvider.notifier).togglePlay();
    }
    _playPauseCtrl.forward(from: 0.0).then((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _playPauseCtrl.reverse();
      });
    });
  }

  void _handleDoubleTap(Song song, bool isCurrentlyLiked) {
    HapticFeedback.heavyImpact(); // Strong feel for liking a song
    setState(() => _isBrokenHeart = isCurrentlyLiked);
    ref.read(likedProvider.notifier).toggle(song);
    _heartCtrl.forward(from: 0.0).then((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _heartCtrl.reverse();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final seen = <String>{};
    final distinct = history.where((s) => seen.add(s.videoId)).toList();
    
    final player = ref.watch(playerProvider);
    final currentSong = player.song;
    final playing = player.status == NebulaPlayerStatus.playing;
    final loading = player.status == NebulaPlayerStatus.loading;
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final shadowD = isDark ? Colors.black54 : const Color(0xFFC8D3DF);
    final shadowL = isDark ? const Color(0xFF1E2530) : Colors.white;
    final h = MediaQuery.of(context).size.height;
    final isLiked = currentSong != null ? ref.watch(isLikedProvider(currentSong.videoId)) : false;

    if (playing && !_isChangingTrack && !loading) {
      if (!_rotationCtrl.isAnimating) _rotationCtrl.repeat();
      if (!_glowCtrl.isAnimating) _glowCtrl.repeat(reverse: true);
    } else {
      if (_rotationCtrl.isAnimating) _rotationCtrl.stop();
      if (_glowCtrl.isAnimating) _glowCtrl.stop();
    }

    final bool isNeedleOnRecord = playing && !_isChangingTrack && !loading;
    final double mainDiskSize = h * 0.38;
    final double needleWidth = 110.0;
    final double needleHeight = h * 0.26;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 60),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        if (distinct.isNotEmpty) {
                          _handleMainTap(currentSong, distinct[_dotIndex], playing, distinct);
                        }
                      },
                      onDoubleTap: currentSong != null ? () => _handleDoubleTap(currentSong, isLiked) : null,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          RotationTransition(
                            turns: _rotationCtrl,
                            child: _buildMainVinyl(mainDiskSize, bg, currentSong, distinct, _dotIndex, shadowL, shadowD, isDark, playing),
                          ),
                          _buildOverlayAnimations(),
                        ],
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
                  child: Column(
                    children: [
                      Text(
                        _display(currentSong, distinct, _dotIndex)?.title ?? 'Select a Song',
                        maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textCol),
                      ),
                      Text(
                        _display(currentSong, distinct, _dotIndex)?.artist ?? '',
                        style: const TextStyle(fontSize: 13, color: const Color(0xFF4993FC), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

                Container(
                  height: 120,
                  margin: const EdgeInsets.only(top: 5, bottom: 15),
                  child: PageView.builder(
                    controller: _ribbonController,
                    onPageChanged: (idx) => _handleRibbonSelection(idx, distinct),
                    itemCount: distinct.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final isCenter = index == _dotIndex;
                      return AnimatedScale(
                        scale: isCenter ? 1.15 : 0.75,
                        duration: const Duration(milliseconds: 300),
                        child: Center(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _ribbonController.animateToPage(index, 
                                duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
                            },
                            child: _buildSmallRibbonRecord(distinct[index]),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const MiniPlayer(), 
              ],
            ),

            Positioned(
              top: 16, left: 20,
              child: _IconPill(icon: Icons.search_rounded, color: mutedCol, bg: cardBg, isDark: isDark, onTap: () => widget.onNavigate(1)),
            ),
            Positioned(
              top: 16, right: 20,
              child: AnimatedRotation(
                turns: isNeedleOnRecord ? 0.0 : 0.18,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                alignment: FractionalOffset((needleWidth - 26.0) / needleWidth, 26.0 / needleHeight),
                child: _buildNeedleRight(isDark, needleWidth, needleHeight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainVinyl(double size, Color bg, Song? current, List<Song> distinct, int idx, Color shadowL, Color shadowD, bool isDark, bool isPlaying) {
    final songToShow = current ?? (distinct.isNotEmpty ? distinct[idx] : null);
    final imgSize = size * 0.35;

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF111111), 
        shape: BoxShape.circle, 
        boxShadow: [
          BoxShadow(color: shadowL.withOpacity(0.9), blurRadius: 28, offset: const Offset(-10, -10)),
          BoxShadow(color: shadowD, blurRadius: 28, offset: const Offset(10, 10)),
        ]
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: size * 0.88, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white10, width: 1.5))),
          Container(width: size * 0.72, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white10, width: 1))),
          Container(width: size * 0.55, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white10, width: 1.5))),
          
          // --- FIXED CENTER IMAGE: ZERO GAPS ---
          AnimatedBuilder(
            animation: _glowCtrl,
            builder: (context, child) {
              return Container(
                width: imgSize, height: imgSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, 
                  boxShadow: [
                    if (isPlaying)
                      BoxShadow(
                        color: const Color(0xFF4993FC).withOpacity(0.4),
                        blurRadius: _glowScale.value + 12,
                        spreadRadius: _glowScale.value / 2,
                      )
                  ],
                ),
                child: ClipOval(
                  child: SizedBox.expand( // This forces the thumbnail to occupy 100% of the circle
                    child: songToShow != null 
                      ? CachedNetworkImage(
                          imageUrl: songToShow.thumbnailUrl, 
                          fit: BoxFit.cover, // Combined with SizedBox.expand, this removes all gaps
                          placeholder: (context, url) => Container(color: Colors.black),
                          errorWidget: (_, __, ___) => Container(color: const Color(0xFFE0EAF4), child: const Icon(Icons.music_note)),
                        )
                      : Container(color: Colors.grey[800], child: const Icon(Icons.music_note, color: Colors.white24, size: 36)),
                  ),
                ),
              );
            }
          ),
          
          Container(
            width: 10, height: 10, 
            decoration: const BoxDecoration(color: Color(0xFF111111), shape: BoxShape.circle), 
            child: Center(child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white54, shape: BoxShape.circle)))
          ),
        ],
      ),
    );
  }

  Widget _buildSmallRibbonRecord(Song song) {
    const double miniImgSize = 34.0; 
    return Container(
      width: 75, height: 75,
      decoration: const BoxDecoration(
        color: Color(0xFF111111), shape: BoxShape.circle, 
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))]
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 65, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white10))),
          Container(width: 50, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white10))),
          
          SizedBox(
            width: miniImgSize, height: miniImgSize,
            child: ClipOval(
              child: SizedBox.expand( // Fixed mini gaps
                child: CachedNetworkImage(
                  imageUrl: song.thumbnailUrl, 
                  fit: BoxFit.cover, 
                  errorWidget: (_, __, ___) => const Icon(Icons.music_note, color: Colors.white24, size: 14),
                ),
              ),
            ),
          ),
          Container(width: 5, height: 5, decoration: const BoxDecoration(color: Colors.white38, shape: BoxShape.circle)),
        ],
      ),
    );
  }

  Widget _buildNeedleRight(bool isDark, double width, double height) {
    final armColor = isDark ? const Color(0xFF2A2D3A) : Colors.white;
    return SizedBox(width: width, height: height, child: Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _ArmPainterRight(armColor))),
      Positioned(bottom: 0, left: 12, child: Transform.rotate(angle: -0.25, child: Container(width: 16, height: 42, decoration: BoxDecoration(color: armColor, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(-2, 2))]), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Container(height: 10, width: 4, margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)))])))),
      Positioned(top: 0, right: 0, child: Container(width: 52, height: 52, decoration: BoxDecoration(color: armColor, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4))]), child: Center(child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: Colors.pinkAccent, shape: BoxShape.circle))))),
    ]));
  }

  Widget _buildOverlayAnimations() => Stack(alignment: Alignment.center, children: [
    AnimatedBuilder(animation: _heartCtrl, builder: (context, child) => Opacity(opacity: _heartOpacity.value, child: Transform.scale(scale: _heartScale.value, child: Icon(_isBrokenHeart ? Icons.heart_broken_rounded : Icons.favorite_rounded, color: Colors.white, size: 80, shadows: const [Shadow(color: Colors.black45, blurRadius: 20)])))),
    AnimatedBuilder(animation: _playPauseCtrl, builder: (context, child) => Opacity(opacity: _playPauseOpacity.value, child: Transform.scale(scale: _playPauseScale.value, child: Icon(_showingPlayIcon ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.white, size: 80, shadows: const [Shadow(color: Colors.black45, blurRadius: 20)])))),
  ]);

  Song? _display(Song? current, List<Song> history, int idx) => current ?? (history.isNotEmpty ? history[idx] : null);
}

class _ArmPainterRight extends CustomPainter {
  final Color color;
  _ArmPainterRight(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.2)..strokeWidth = 6..strokeCap = StrokeCap.round..style = PaintingStyle.stroke..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final paint = Paint()..color = color..strokeWidth = 6..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final path = Path();
    path.moveTo(size.width - 26, 26);
    path.quadraticBezierTo(0, size.height * 0.5, 20, size.height - 20);
    canvas.drawPath(path.shift(const Offset(-2, 4)), shadowPaint);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IconPill extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final bool isDark;
  final VoidCallback onTap;
  const _IconPill({required this.icon, required this.color, required this.bg, required this.isDark, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(width: 52, height: 52, decoration: BoxDecoration(color: bg, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.07), blurRadius: 12, offset: const Offset(0, 3))]), child: Icon(icon, color: color, size: 22)));
}