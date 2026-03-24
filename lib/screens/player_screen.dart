import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'upnext_screen.dart';

class _SlideUpRoute extends PageRouteBuilder {
  _SlideUpRoute()
      : super(
          opaque: false,
          barrierDismissible: false,
          pageBuilder: (_, __, ___) => const UpNextScreen(),
          transitionDuration: const Duration(milliseconds: 380),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          transitionsBuilder: (_, anim, __, child) {
            final curved = CurvedAnimation(
                parent: anim, curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic);
            return SlideTransition(
              position: Tween<Offset>(
                  begin: const Offset(0, 1), end: Offset.zero)
                  .animate(curved),
              child: child,
            );
          },
        );
}

void _openUpNext(BuildContext context) => Navigator.of(context).push(_SlideUpRoute());

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with TickerProviderStateMixin {
  late AnimationController _rotationCtrl;
  late AnimationController _heartCtrl;
  late AnimationController _playPauseCtrl;
  
  late Animation<double>   _heartScale;
  late Animation<double>   _heartOpacity;
  late Animation<double>   _playPauseScale;
  late Animation<double>   _playPauseOpacity;

  bool _isBrokenHeart   = false;
  bool _showingPlayIcon = false;

  @override
  void initState() {
    super.initState();
    _rotationCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 15));
    _heartCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _heartScale = Tween<double>(begin: 0.5, end: 1.3).animate(CurvedAnimation(parent: _heartCtrl, curve: Curves.elasticOut));
    _heartOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _heartCtrl, curve: Curves.easeOut));
    _playPauseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _playPauseScale = Tween<double>(begin: 0.5, end: 1.3).animate(CurvedAnimation(parent: _playPauseCtrl, curve: Curves.easeOutBack));
    _playPauseOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _playPauseCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _rotationCtrl.dispose();
    _heartCtrl.dispose();
    _playPauseCtrl.dispose();
    super.dispose();
  }

  void _handleTap(Song song, bool isPlaying) {
    setState(() => _showingPlayIcon = !isPlaying);
    ref.read(playerProvider.notifier).togglePlay();
    _playPauseCtrl.forward(from: 0.0).then((_) {
      if (mounted) Future.delayed(const Duration(milliseconds: 400), () => _playPauseCtrl.reverse());
    });
  }

  void _handleDoubleTap(Song song, bool isCurrentlyLiked) {
    setState(() => _isBrokenHeart = isCurrentlyLiked);
    ref.read(likedProvider.notifier).toggle(song);
    _heartCtrl.forward(from: 0.0).then((_) {
      if (mounted) Future.delayed(const Duration(milliseconds: 600), () => _heartCtrl.reverse());
    });
  }

  @override
  Widget build(BuildContext context) {
    final ps      = ref.watch(playerProvider);
    final song    = ps.song;
    final liked   = song != null ? ref.watch(isLikedProvider(song.videoId)) : false;
    final playing = ps.status == NebulaPlayerStatus.playing;
    final loading = ps.status == NebulaPlayerStatus.loading;
    final durMs   = ps.duration.inMilliseconds;
    final posMs   = ps.position.inMilliseconds;
    final prog    = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    final isDark  = ref.watch(themeProvider) == ThemeMode.dark;
    final bg      = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);
    final cardBg  = isDark ? const Color(0xFF161B22) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol= isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    final h       = MediaQuery.of(context).size.height;
    final topPad  = MediaQuery.of(context).padding.top;

    if (playing && !loading) {
      if (!_rotationCtrl.isAnimating) _rotationCtrl.repeat();
    } else {
      if (_rotationCtrl.isAnimating) _rotationCtrl.stop();
    }

    final bool isNeedleOnRecord = playing && !loading;
    final double diskSize = h * 0.42; 
    final double needleWidth = 110.0;
    final double needleHeight = h * 0.26;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -400) _openUpNext(context);
          else if (v > 400) Navigator.pop(context);
        },
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 1. Gramophone Area
                Flexible(
                  flex: 10,
                  child: Container(
                    padding: const EdgeInsets.only(top: 110),
                    child: Center(
                      child: GestureDetector(
                        onTap: song != null ? () => _handleTap(song, playing) : null,
                        onDoubleTap: song != null ? () => _handleDoubleTap(song, liked) : null,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            RotationTransition(
                              turns: _rotationCtrl,
                              child: _buildVinylRecord(diskSize, bg, song, isDark),
                            ),
                            _buildOverlayAnimations(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. Info & Unified Control Block
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSongLabels(song, textCol, mutedCol),
                      const SizedBox(height: 25),
                      _Waveform(progress: prog, isDark: isDark, onSeek: (pct) {
                        final total = ps.duration.inSeconds;
                        if (total > 0) ref.read(playerProvider.notifier).seek(Duration(seconds: (pct * total).round()));
                      }),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(_fmt(ps.position), style: TextStyle(fontSize: 11, color: mutedCol, fontWeight: FontWeight.w700)),
                          Text(_fmt(ps.duration), style: TextStyle(fontSize: 11, color: mutedCol, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                      if (loading) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(color: Color(0xFF4993FC), minHeight: 2)),
                      const SizedBox(height: 20),
                      _buildTransportRow(textCol, bg, isDark, song, mutedCol),
                      const SizedBox(height: 16),
                      _buildUpNextDragHandle(mutedCol),
                    ],
                  ),
                ),
              ],
            ),
            
            // 3. Top Symmetrical Icons
            Positioned(
              top: topPad + 10, left: 20,
              child: _IconPill(
                icon: Icons.search_rounded, 
                color: mutedCol, bg: cardBg, isDark: isDark, 
                onTap: () {
                  Navigator.pop(context); // Close Player
                  // Logic to trigger Search Navigation should be handled via callback if needed,
                  // or handled by the parent home screen when this pops.
                }
              )
            ),
            Positioned(
              top: topPad + 10, right: 20,
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

  // --- SUBCOMPONENTS ---

  Widget _buildOverlayAnimations() => Stack(alignment: Alignment.center, children: [
    AnimatedBuilder(animation: _heartCtrl, builder: (context, child) => Opacity(opacity: _heartOpacity.value, child: Transform.scale(scale: _heartScale.value, child: Icon(_isBrokenHeart ? Icons.heart_broken_rounded : Icons.favorite_rounded, color: Colors.white, size: 80, shadows: const [Shadow(color: Colors.black45, blurRadius: 20)])))),
    AnimatedBuilder(animation: _playPauseCtrl, builder: (context, child) => Opacity(opacity: _playPauseOpacity.value, child: Transform.scale(scale: _playPauseScale.value, child: Icon(_showingPlayIcon ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.white, size: 80, shadows: const [Shadow(color: Colors.black45, blurRadius: 20)])))),
  ]);

  Widget _buildSongLabels(Song? song, Color textCol, Color mutedCol) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Column(children: [
      Text(song?.title ?? 'No song selected', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: textCol, letterSpacing: -0.2)),
      const SizedBox(height: 4),
      Text(song?.artist ?? '', style: TextStyle(fontSize: 13, color: mutedCol)),
    ]),
  );

  Widget _buildTransportRow(Color textCol, Color bg, bool isDark, Song? song, Color mutedCol) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _NeuBtn(icon: Icons.skip_previous_rounded, color: textCol, bg: bg, isDark: isDark, size: 52, onTap: () => ref.read(playerProvider.notifier).skipPrevious()),
      GestureDetector(onTap: () { if (song != null) _showPlaylistSheet(context, ref, song, isDark, bg, textCol, mutedCol); }, child: Container(width: 72, height: 72, decoration: BoxDecoration(color: const Color(0xFF4993FC), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF4993FC).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))]), child: const Icon(Icons.playlist_add_rounded, color: Colors.white, size: 34))),
      _NeuBtn(icon: Icons.skip_next_rounded, color: textCol, bg: bg, isDark: isDark, size: 52, onTap: () => ref.read(playerProvider.notifier).skipNext()),
    ]),
  );

  Widget _buildUpNextDragHandle(Color mutedCol) => GestureDetector(onTap: () => _openUpNext(context), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.keyboard_arrow_up_rounded, color: mutedCol.withOpacity(0.5), size: 20), const SizedBox(height: 2), Container(width: 36, height: 4, decoration: BoxDecoration(color: mutedCol.withOpacity(0.35), borderRadius: BorderRadius.circular(2)))]));

  Widget _buildVinylRecord(double size, Color bg, Song? song, bool isDark) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: const Color(0xFF111111), shape: BoxShape.circle, boxShadow: [BoxShadow(color: isDark ? Colors.black54 : Colors.grey.withOpacity(0.4), blurRadius: 30, offset: const Offset(10, 10))]),
    child: Stack(alignment: Alignment.center, children: [
      Container(width: size * 0.9, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.05), width: 2))),
      Container(width: size * 0.7, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.05), width: 1.5))),
      Container(width: size * 0.35, height: size * 0.35, decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: Border.all(color: const Color(0xFF111111), width: 4)), child: ClipOval(child: song?.thumbnailUrl.isNotEmpty == true ? CachedNetworkImage(imageUrl: song!.thumbnailUrl, fit: BoxFit.cover) : Container(color: Colors.grey[800]))),
      Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF111111), shape: BoxShape.circle), child: Center(child: Container(width: 2, height: 2, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle)))),
    ]),
  );

  Widget _buildNeedleRight(bool isDark, double width, double height) {
    final armColor = isDark ? const Color(0xFF2A2D3A) : Colors.white;
    return SizedBox(
      width: width, height: height,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _ArmPainterRight(armColor))),
          Positioned(
            bottom: 0, left: 12, 
            child: Transform.rotate(
              angle: -0.25, 
              child: Container(
                width: 16, height: 42,
                decoration: BoxDecoration(color: armColor, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(-2, 2))]),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Container(height: 10, width: 4, margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)))]),
              ),
            ),
          ),
          Positioned(top: 0, right: 0, child: Container(width: 52, height: 52, decoration: BoxDecoration(color: armColor, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4))]), child: Center(child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: Colors.pinkAccent, shape: BoxShape.circle))))),
        ],
      ),
    );
  }

  void _showPlaylistSheet(BuildContext context, WidgetRef ref, Song song, bool isDark, Color bg, Color textCol, Color mutedCol) {
    final sheetBg = isDark ? const Color(0xFF161B22) : Colors.white;
    showModalBottomSheet(
      context: context, 
      backgroundColor: Colors.transparent, 
      isScrollControlled: true, 
      builder: (ctx) => _PlaylistSheet(song: song, isDark: isDark, bg: bg, sheetBg: sheetBg, textCol: textCol, mutedCol: mutedCol)
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// --- WAVEFORM ---
class _Waveform extends StatelessWidget {
  final double progress;
  final bool isDark;
  final ValueChanged<double> onSeek;
  const _Waveform({required this.progress, required this.isDark, required this.onSeek});

  @override
  Widget build(BuildContext context) {
    const barCount = 34;
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox;
        onSeek((box.globalToLocal(d.globalPosition).dx / box.size.width).clamp(0.0, 1.0));
      },
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox;
        onSeek((box.globalToLocal(d.globalPosition).dx / box.size.width).clamp(0.0, 1.0));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(barCount, (i) {
              final pct = i / barCount;
              final active = pct <= progress;
              final weighting = (1.0 - (pct - 0.5).abs() * 1.6).clamp(0.2, 1.0);
              final barHeight = 12 + (weighting * 48 * (0.5 + Random(i + 100).nextDouble() * 0.5));
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 6,
                height: barHeight,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF0066CC) : (isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(width: 52, height: 52, decoration: BoxDecoration(color: bg, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.07), blurRadius: 12, offset: const Offset(0, 3))]), child: Icon(icon, color: color, size: 24)));
}

class _NeuBtn extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final bool isDark;
  final VoidCallback onTap;
  final double size;
  const _NeuBtn({required this.icon, required this.color, required this.bg, required this.isDark, required this.onTap, required this.size});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: size, height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle, boxShadow: [
        BoxShadow(color: isDark ? Colors.black54 : Colors.grey[300]!, blurRadius: 10, offset: const Offset(5, 5)),
        BoxShadow(color: isDark ? Colors.white.withOpacity(0.05) : Colors.white, blurRadius: 10, offset: const Offset(-5, -5)),
      ]),
      child: Icon(icon, color: color, size: size * 0.5),
    ),
  );
}

class _PlaylistSheet extends ConsumerStatefulWidget {
  final Song song;
  final bool isDark;
  final Color bg, sheetBg, textCol, mutedCol;
  const _PlaylistSheet({required this.song, required this.isDark, required this.bg, required this.sheetBg, required this.textCol, required this.mutedCol});
  @override
  ConsumerState<_PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends ConsumerState<_PlaylistSheet> {
  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      decoration: BoxDecoration(color: widget.sheetBg, borderRadius: BorderRadius.circular(24)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 14), decoration: BoxDecoration(color: widget.mutedCol.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(children: [
            Text('Add to Playlist', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: widget.textCol)),
            const Spacer(),
            Material(
              color: Colors.transparent, 
              child: InkWell(
                borderRadius: BorderRadius.circular(20), 
                onTap: () => _createNew(context), 
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), 
                  decoration: BoxDecoration(color: const Color(0xFF4993FC), borderRadius: BorderRadius.circular(20)), 
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, color: Colors.white, size: 15), SizedBox(width: 4), Text('New', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))])
                )
              )
            ),
          ]),
        ),
        if (playlists.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.queue_music_rounded, size: 44, color: widget.mutedCol.withOpacity(0.4)), const SizedBox(height: 12), Text('No playlists yet. Tap + to create one.', style: TextStyle(color: widget.mutedCol, fontSize: 13))]))
        else 
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45), 
            child: ListView.builder(
              shrinkWrap: true, 
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 16), 
              itemCount: playlists.length, 
              itemBuilder: (_, i) {
                final pl = playlists[i];
                final hasIt = ref.read(playlistProvider.notifier).contains(pl.id, widget.song.videoId);
                return ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: Text(pl.name, style: TextStyle(color: widget.textCol, fontWeight: FontWeight.w600)),
                  subtitle: Text('${pl.songs.length} songs', style: TextStyle(color: widget.mutedCol)),
                  trailing: hasIt ? const Icon(Icons.check_circle_rounded, color: Color(0xFF4993FC)) : null,
                  onTap: hasIt ? null : () async {
                    await ref.read(playlistProvider.notifier).addSong(pl.id, widget.song);
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to ${pl.name} ✓'), behavior: SnackBarBehavior.floating));
                    }
                  },
                );
              }
            )
          ),
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
      ]),
    );
  }

  void _createNew(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context, 
      builder: (d) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Playlist Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                final pl = await ref.read(playlistProvider.notifier).create(ctrl.text.trim());
                await ref.read(playlistProvider.notifier).addSong(pl.id, widget.song);
                if (mounted) {
                  Navigator.pop(d);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created and added to ${pl.name} ✓'), behavior: SnackBarBehavior.floating));
                }
              }
            }, 
            child: const Text('Create')
          ),
        ],
      )
    );
  }
}