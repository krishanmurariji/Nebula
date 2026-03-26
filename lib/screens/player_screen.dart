import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart'; 
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'upnext_screen.dart';

// ── Panel visibility state ────────────────────────────────────────────────────
enum _PanelState { none, list, naming }

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
                parent: anim,
                curve: Curves.easeOutCubic,
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

void _openUpNext(BuildContext context) =>
    Navigator.of(context).push(_SlideUpRoute());

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotationCtrl;
  late AnimationController _heartCtrl;
  late AnimationController _playPauseCtrl;

  late Animation<double> _heartScale;
  late Animation<double> _heartOpacity;
  late Animation<double> _playPauseScale;
  late Animation<double> _playPauseOpacity;

  bool _isBrokenHeart = false;
  bool _showingPlayIcon = false;

  int _playModeIndex = 0;
  double _volume = 0.5;

  // ── Playlist Panel Animations ───────────────────────────────────────────────
  _PanelState _panelState = _PanelState.none;
  late AnimationController _listPanelCtrl;
  late AnimationController _namePanelCtrl;
  late Animation<Offset> _listSlide;
  late Animation<Offset> _nameSlide;
  late Animation<double> _listFade;
  late Animation<double> _nameFade;
  late Animation<double> _scrimOpacity;

  final TextEditingController _nameCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _rotationCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 15));
    _heartCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _heartScale = Tween<double>(begin: 0.5, end: 1.3).animate(
        CurvedAnimation(parent: _heartCtrl, curve: Curves.elasticOut));
    _heartOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _heartCtrl, curve: Curves.easeOut));
    _playPauseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _playPauseScale = Tween<double>(begin: 0.5, end: 1.3).animate(
        CurvedAnimation(parent: _playPauseCtrl, curve: Curves.easeOutBack));
    _playPauseOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _playPauseCtrl, curve: Curves.easeOut));

    // Panel Controllers
    _listPanelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _namePanelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));

    _listSlide = Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _listPanelCtrl,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic));

    _nameSlide = Tween<Offset>(begin: const Offset(-1.0, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _namePanelCtrl,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic));

    _listFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _listPanelCtrl, curve: Curves.easeOut));
    _nameFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _namePanelCtrl, curve: Curves.easeOut));

    _scrimOpacity = Tween<double>(begin: 0.0, end: 0.55).animate(
        CurvedAnimation(parent: _listPanelCtrl, curve: Curves.easeOut));

    FlutterVolumeController.updateShowSystemUI(false); 

    FlutterVolumeController.addListener((volume) {
      if (mounted) {
        setState(() {
          _volume = volume;
        });
        ref.read(playerProvider.notifier).setVolume(_volume);
      }
    });

    FlutterVolumeController.getVolume().then((volume) {
      if (mounted && volume != null) {
        setState(() => _volume = volume);
      }
    });
  }

  @override
  void dispose() {
    FlutterVolumeController.removeListener();
    _rotationCtrl.dispose();
    _heartCtrl.dispose();
    _playPauseCtrl.dispose();
    _listPanelCtrl.dispose();
    _namePanelCtrl.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Panel Control Methods ──────────────────────────────────────────────────
  void _openList() {
    HapticFeedback.mediumImpact();
    setState(() => _panelState = _PanelState.list);
    _listPanelCtrl.forward();
  }

  Future<void> _closeList() async {
    HapticFeedback.lightImpact();
    await _listPanelCtrl.reverse();
    if (mounted) setState(() => _panelState = _PanelState.none);
  }

  void _openNaming() async {
    HapticFeedback.selectionClick();
    _nameCtrl.clear();
    await _listPanelCtrl.reverse();
    if (!mounted) return;
    setState(() => _panelState = _PanelState.naming);
    _namePanelCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 200),
        () => _nameFocus.requestFocus());
  }

  Future<void> _cancelNaming() async {
    HapticFeedback.lightImpact();
    _nameFocus.unfocus();
    await _namePanelCtrl.reverse();
    if (!mounted) return;
    setState(() => _panelState = _PanelState.list);
    _listPanelCtrl.forward(from: 0);
  }

  Future<void> _confirmNaming(Song song) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.mediumImpact();
    _nameFocus.unfocus();

    final pl = await ref.read(playlistProvider.notifier).create(name);
    await ref.read(playlistProvider.notifier).addSong(pl.id, song);

    await _namePanelCtrl.reverse();
    if (!mounted) return;
    setState(() => _panelState = _PanelState.none);
    _nameCtrl.clear();

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Created and added to ${pl.name} ✓'),
        behavior: SnackBarBehavior.floating));
  }

  Future<void> _closeAll() async {
    _nameFocus.unfocus();
    if (_panelState == _PanelState.naming) {
      await _namePanelCtrl.reverse();
    } else if (_panelState == _PanelState.list) {
      await _listPanelCtrl.reverse();
    }
    if (mounted) setState(() => _panelState = _PanelState.none);
  }

  // ── Standard Player Methods ────────────────────────────────────────────────

  void _handleTap(Song song, bool isPlaying) {
    setState(() => _showingPlayIcon = !isPlaying);
    ref.read(playerProvider.notifier).togglePlay();
    _playPauseCtrl.forward(from: 0.0).then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 400),
            () => _playPauseCtrl.reverse());
      }
    });
  }

  void _handleDoubleTap(Song song, bool isCurrentlyLiked) {
    setState(() => _isBrokenHeart = isCurrentlyLiked);
    ref.read(likedProvider.notifier).toggle(song);
    _heartCtrl.forward(from: 0.0).then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600),
            () => _heartCtrl.reverse());
      }
    });
  }

  void _cyclePlayMode() {
    setState(() {
      _playModeIndex = (_playModeIndex + 1) % 4;
    });
  }

  void _updateVolume(Offset localPosition, double size) {
    final center = Offset(size / 2, size / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    double angle = atan2(dy, dx);

    if (angle < 0) angle += 2 * pi;
    if (angle >= 0 && angle < pi * 0.75) angle += 2 * pi;

    double pct = (angle - pi * 0.75) / (pi * 1.5);
    setState(() {
      _volume = pct.clamp(0.0, 1.0);
      FlutterVolumeController.setVolume(_volume); // Fixed showSystemUI error here
      ref.read(playerProvider.notifier).setVolume(_volume);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ps = ref.watch(playerProvider);
    final song = ps.song;
    final liked =
        song != null ? ref.watch(isLikedProvider(song.videoId)) : false;
    final playlists = ref.watch(playlistProvider);

    final playing = ps.status == NebulaPlayerStatus.playing;
    final loading = ps.status == NebulaPlayerStatus.loading;
    final durMs = ps.duration.inMilliseconds;
    final posMs = ps.position.inMilliseconds;
    final prog = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    const accentCol = Color(0xFF4993FC);

    final h = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;

    if (playing && !loading) {
      if (!_rotationCtrl.isAnimating) _rotationCtrl.repeat();
    } else {
      if (_rotationCtrl.isAnimating) _rotationCtrl.stop();
    }

    final bool isNeedleOnRecord = playing && !loading;
    final double diskSize = h * 0.315; 
    final double volumeRingSize = diskSize + 56.0;
    final double needleWidth = 110.0;
    final double needleHeight = h * 0.26;

    return PopScope(
      canPop: _panelState == _PanelState.none,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _closeAll();
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ── Main Player UI ──────────────────────────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -400) {
                  _openUpNext(context);
                } else if (v > 400 && _panelState == _PanelState.none) {
                  Navigator.pop(context);
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    flex: 10,
                    child: Container(
                      padding: const EdgeInsets.only(top: 110),
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            GestureDetector(
                              onPanUpdate: (details) => _updateVolume(
                                  details.localPosition, volumeRingSize),
                              onTapDown: (details) => _updateVolume(
                                  details.localPosition, volumeRingSize),
                              child: SizedBox(
                                width: volumeRingSize,
                                height: volumeRingSize,
                                child: CustomPaint(
                                  painter: _VolumeArcPainter(
                                    volume: _volume,
                                    isDark: isDark,
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: song != null
                                  ? () => _handleTap(song, playing)
                                  : null,
                              onDoubleTap: song != null
                                  ? () => _handleDoubleTap(song, liked)
                                  : null,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  RotationTransition(
                                    turns: _rotationCtrl,
                                    child: _buildVinylRecord(
                                        diskSize, bg, song, isDark),
                                  ),
                                  _buildOverlayAnimations(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSongLabels(song, textCol, mutedCol),
                        const SizedBox(height: 25),
                        _Waveform(
                          progress: prog,
                          isDark: isDark,
                          onSeek: (pct) {
                            final total = ps.duration.inSeconds;
                            if (total > 0) {
                              ref.read(playerProvider.notifier).seek(Duration(
                                  seconds: (pct * total).round()));
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 28),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_fmt(ps.position),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: mutedCol,
                                      fontWeight: FontWeight.w700)),
                              Text(_fmt(ps.duration),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: mutedCol,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildTransportRow(
                            textCol, bg, isDark, song, mutedCol),
                        const SizedBox(height: 16),
                        _buildUpNextDragHandle(mutedCol),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              top: topPad + 10,
              left: 20,
              child: _NeuBtn(
                icon: Icons.expand_more_rounded,
                color: const Color(0xFF4993FC),
                bg: bg,
                isDark: isDark,
                size: 52,
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ),
            Positioned(
              top: topPad + 10,
              right: 20,
              child: AnimatedRotation(
                turns: isNeedleOnRecord ? 0.0 : 0.18,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                alignment: FractionalOffset(
                    (needleWidth - 26.0) / needleWidth,
                    26.0 / needleHeight),
                child:
                    _buildNeedleRight(isDark, needleWidth, needleHeight),
              ),
            ),

            // ── Scrim ────────────────────────────────────────────────────────
            if (_panelState != _PanelState.none)
              AnimatedBuilder(
                animation: _panelState == _PanelState.naming
                    ? _namePanelCtrl
                    : _listPanelCtrl,
                builder: (_, __) => GestureDetector(
                  onTap: _closeAll,
                  child: Container(
                    color: Colors.black.withOpacity(
                        _panelState == _PanelState.naming
                            ? (_nameFade.value * 0.55)
                            : _scrimOpacity.value),
                  ),
                ),
              ),

            // ── List Panel (slides from right) ───────────────────────────────
            if (_panelState == _PanelState.list || _listPanelCtrl.isAnimating)
              SlideTransition(
                position: _listSlide,
                child: FadeTransition(
                  opacity: _listFade,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _AddToPlaylistPanel(
                      isDark: isDark,
                      bg: bg,
                      cardBg: cardBg,
                      textCol: textCol,
                      mutedCol: mutedCol,
                      accentCol: accentCol,
                      playlists: playlists,
                      song: song,
                      onClose: _closeList,
                      onAdd: _openNaming,
                      onTapPlaylist: (pl) async {
                        if (song != null) {
                          HapticFeedback.selectionClick();
                          await ref.read(playlistProvider.notifier).addSong(pl.id, song);
                          _closeList();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Added to ${pl.name} ✓'),
                                behavior: SnackBarBehavior.floating));
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),

            // ── Name Panel (slides from left) ────────────────────────────────
            if (_panelState == _PanelState.naming || _namePanelCtrl.isAnimating)
              SlideTransition(
                position: _nameSlide,
                child: FadeTransition(
                  opacity: _nameFade,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _NamingPanel(
                      isDark: isDark,
                      bg: bg,
                      cardBg: cardBg,
                      textCol: textCol,
                      mutedCol: mutedCol,
                      accentCol: accentCol,
                      controller: _nameCtrl,
                      focusNode: _nameFocus,
                      onCancel: _cancelNaming,
                      onConfirm: () {
                        if (song != null) _confirmNaming(song);
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayAnimations() => Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
              animation: _heartCtrl,
              builder: (context, child) => Opacity(
                  opacity: _heartOpacity.value,
                  child: Transform.scale(
                      scale: _heartScale.value,
                      child: Icon(
                          _isBrokenHeart
                              ? Icons.heart_broken_rounded
                              : Icons.favorite_rounded,
                          color: Colors.white,
                          size: 80,
                          shadows: const [
                            Shadow(
                                color: Colors.black45, blurRadius: 20)
                          ])))),
          AnimatedBuilder(
              animation: _playPauseCtrl,
              builder: (context, child) => Opacity(
                  opacity: _playPauseOpacity.value,
                  child: Transform.scale(
                      scale: _playPauseScale.value,
                      child: Icon(
                          _showingPlayIcon
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          color: Colors.white,
                          size: 80,
                          shadows: const [
                            Shadow(
                                color: Colors.black45, blurRadius: 20)
                          ])))),
        ],
      );

  Widget _buildSongLabels(Song? song, Color textCol, Color mutedCol) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(children: [
          Text(song?.title ?? 'No song selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: textCol,
                  letterSpacing: -0.2)),
          const SizedBox(height: 4),
          Text(song?.artist ?? '',
              style: TextStyle(fontSize: 13, color: mutedCol)),
        ]),
      );

  Widget _buildTransportRow(Color textCol, Color bg, bool isDark,
      Song? song, Color mutedCol) {
    IconData modeIcon;
    Color modeColor = const Color(0xFF4993FC);

    if (_playModeIndex == 0) {
      modeIcon = Icons.repeat_rounded;
      modeColor = textCol;
    } else if (_playModeIndex == 1) {
      modeIcon = Icons.repeat_rounded;
    } else if (_playModeIndex == 2) {
      modeIcon = Icons.repeat_one_rounded;
    } else {
      modeIcon = Icons.shuffle_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _NeuBtn(
            icon: modeIcon,
            color: modeColor,
            bg: bg,
            isDark: isDark,
            size: 52,
            onTap: _cyclePlayMode,
          ),
          _NeuBtn(
            icon: Icons.skip_previous_rounded,
            color: const Color(0xFF4993FC),
            bg: bg,
            isDark: isDark,
            size: 52,
            onTap: () =>
                ref.read(playerProvider.notifier).skipPrevious(),
          ),
          _NeuBtn(
            icon: Icons.skip_next_rounded,
            color: const Color(0xFF4993FC),
            bg: bg,
            isDark: isDark,
            size: 52,
            onTap: () => ref.read(playerProvider.notifier).skipNext(),
          ),
          _NeuBtn(
            icon: Icons.playlist_add_rounded,
            color: const Color(0xFF4993FC),
            bg: bg,
            isDark: isDark,
            size: 52,
            onTap: () {
              if (song != null) _openList();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUpNextDragHandle(Color mutedCol) => GestureDetector(
      onTap: () => _openUpNext(context),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.keyboard_arrow_up_rounded,
            color: mutedCol.withOpacity(0.5), size: 20),
        const SizedBox(height: 2),
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: mutedCol.withOpacity(0.35),
                borderRadius: BorderRadius.circular(2)))
      ]));

  Widget _buildVinylRecord(
      double size, Color bg, Song? song, bool isDark) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Color(0xFF222222),
            Color(0xFF0F0F0F),
            Color(0xFF050505)
          ],
          stops: [0.0, 0.6, 1.0],
        ),
        boxShadow: [
          BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.8)
                  : Colors.black.withOpacity(0.4),
              blurRadius: 30,
              spreadRadius: 4,
              offset: const Offset(8, 16)),
          BoxShadow(
              color: Colors.white.withOpacity(isDark ? 0.05 : 0.15),
              blurRadius: 1,
              spreadRadius: 0,
              offset: const Offset(-1, -1)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Colors.white.withOpacity(0.0),
                  Colors.white.withOpacity(0.12),
                  Colors.white.withOpacity(0.3),
                  Colors.white.withOpacity(0.12),
                  Colors.white.withOpacity(0.0),
                  Colors.white.withOpacity(0.0),
                  Colors.white.withOpacity(0.12),
                  Colors.white.withOpacity(0.3),
                  Colors.white.withOpacity(0.12),
                  Colors.white.withOpacity(0.0),
                ],
                stops: const [
                  0.0, 0.1, 0.15, 0.2, 0.35, 0.5, 0.6, 0.65, 0.7, 0.85
                ],
                transform: const GradientRotation(pi / 3),
              ),
            ),
          ),
          ...List.generate(16, (i) {
            final factor = 0.96 - (i * 0.035);
            return Container(
              width: size * factor,
              height: size * factor,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white
                      .withOpacity(i % 2 == 0 ? 0.04 : 0.01),
                  width: 0.8,
                ),
              ),
            );
          }),
          Container(
            width: size * 0.36,
            height: size * 0.36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.7),
                    blurRadius: 8,
                    spreadRadius: 2),
              ],
              border:
                  Border.all(color: const Color(0xFF111111), width: 3),
            ),
            child: ClipOval(
              child: song?.thumbnailUrl.isNotEmpty == true
                  ? Transform.scale(
                      scale: 1.35, 
                      child: CachedNetworkImage(
                        imageUrl: song!.thumbnailUrl, 
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    )
                  : Container(color: Colors.grey[800]),
            ),
          ),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFFD6D6D6),
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Colors.white,
                  Color(0xFF888888),
                  Color(0xFF222222)
                ],
                stops: [0.1, 0.6, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.8),
                    blurRadius: 4,
                    offset: const Offset(1, 2))
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeedleRight(bool isDark, double width, double height) {
    final armColor =
        isDark ? const Color(0xFF2A2D3A) : Colors.white;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
              child:
                  CustomPaint(painter: _ArmPainterRight(armColor))),
          Positioned(
            bottom: 0,
            left: 12,
            child: Transform.rotate(
              angle: -0.25,
              child: Container(
                width: 16,
                height: 42,
                decoration: BoxDecoration(
                    color: armColor,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(-2, 2))
                    ]),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                          height: 10,
                          width: 4,
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius:
                                  BorderRadius.circular(2)))
                    ]),
              ),
            ),
          ),
          Positioned(
              top: 0,
              right: 0,
              child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                      color: armColor,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black38,
                            blurRadius: 8,
                            offset: Offset(0, 4))
                      ]),
                  child: Center(
                      child: Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                              color: Colors.pinkAccent,
                              shape: BoxShape.circle))))),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ADD TO PLAYLIST PANEL — slides in from right
// ═══════════════════════════════════════════════════════════════════════════════
class _AddToPlaylistPanel extends ConsumerWidget {
  final bool isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final List<Playlist> playlists;
  final Song? song;
  final VoidCallback onClose, onAdd;
  final void Function(Playlist) onTapPlaylist;

  const _AddToPlaylistPanel({
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.playlists,
    required this.song,
    required this.onClose,
    required this.onAdd,
    required this.onTapPlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = MediaQuery.of(context).size.width * 0.82;
    final h = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      width: w,
      height: h,
      padding: EdgeInsets.only(top: topPad + 16, bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          bottomLeft: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.55 : 0.18),
            blurRadius: 32,
            offset: const Offset(-8, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
            child: Row(
              children: [
                _NeuBtn(
                  icon: Icons.close_rounded,
                  color: mutedCol,
                  bg: isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7),
                  isDark: isDark,
                  size: 44,
                  onTap: onClose,
                ),
                const SizedBox(width: 14),
                Text(
                  'Add to Playlist',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: textCol,
                    letterSpacing: -0.4,
                  ),
                ),
                const Spacer(),
                _NeuBtn(
                  icon: Icons.add_rounded,
                  color: accentCol,
                  bg: isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7),
                  isDark: isDark,
                  size: 44,
                  onTap: onAdd,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _NeuDivider(isDark: isDark),
          ),
          const SizedBox(height: 8),
          if (playlists.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NeuIconBox(
                      icon: Icons.queue_music_rounded,
                      isDark: isDark,
                      bg: isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7),
                      color: accentCol,
                      size: 72,
                    ),
                    const SizedBox(height: 16),
                    Text('No playlists yet',
                        style: TextStyle(
                            color: mutedCol,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Tap + to create one',
                        style: TextStyle(
                            color: mutedCol.withOpacity(0.6), fontSize: 12)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                physics: const BouncingScrollPhysics(),
                itemCount: playlists.length,
                itemBuilder: (_, i) {
                  final pl = playlists[i];
                  final hasIt = song != null && ref.read(playlistProvider.notifier).contains(pl.id, song!.videoId);
                  return GestureDetector(
                    onTap: hasIt ? null : () => onTapPlaylist(pl),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                              color: isDark ? Colors.black54 : Colors.grey.shade300,
                              blurRadius: 8,
                              offset: const Offset(3, 3)),
                          BoxShadow(
                              color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
                              blurRadius: 8,
                              offset: const Offset(-3, -3)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentCol.withOpacity(0.12),
                              boxShadow: [
                                BoxShadow(
                                    color: isDark ? Colors.black38 : Colors.grey.shade200,
                                    blurRadius: 6,
                                    offset: const Offset(2, 2)),
                              ],
                            ),
                            child: Icon(Icons.queue_music_rounded, color: accentCol, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pl.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: textCol,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                Text('${pl.songs.length} songs',
                                    style: TextStyle(color: mutedCol, fontSize: 12)),
                              ],
                            ),
                          ),
                          if (hasIt)
                            Icon(Icons.check_circle_rounded, color: accentCol, size: 28),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// NAMING PANEL — slides in from left
// ═══════════════════════════════════════════════════════════════════════════════
class _NamingPanel extends StatelessWidget {
  final bool isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCancel, onConfirm;

  const _NamingPanel({
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.controller,
    required this.focusNode,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width * 0.82;
    final h = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      width: w,
      height: h,
      padding: EdgeInsets.only(top: topPad + 16, bottom: 32, left: 20, right: 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.55 : 0.18),
            blurRadius: 32,
            offset: const Offset(8, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NeuBtn(
                icon: Icons.arrow_back_rounded,
                color: mutedCol,
                bg: isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7),
                isDark: isDark,
                size: 44,
                onTap: onCancel,
              ),
              const SizedBox(width: 14),
              Text(
                'New Playlist',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: textCol,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: _NeuIconBox(
              icon: Icons.album_rounded,
              isDark: isDark,
              bg: isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7),
              color: accentCol,
              size: 88,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Give it a name',
            style: TextStyle(
              color: mutedCol,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: isDark ? Colors.black54 : Colors.grey.shade300,
                    blurRadius: 10,
                    offset: const Offset(4, 4)),
                BoxShadow(
                    color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
                    blurRadius: 10,
                    offset: const Offset(-4, -4)),
              ],
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(color: textCol, fontWeight: FontWeight.w700, fontSize: 16),
              cursorColor: accentCol,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onConfirm(),
              decoration: InputDecoration(
                hintText: 'Playlist name…',
                hintStyle: TextStyle(color: mutedCol.withOpacity(0.5), fontSize: 15),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                suffixIcon: Icon(Icons.edit_rounded, color: accentCol.withOpacity(0.5), size: 18),
              ),
            ),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onConfirm,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: accentCol,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: accentCol.withOpacity(0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 6)),
                  BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: const Center(
                child: Text(
                  'Create & Add Song',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onCancel,
            child: Center(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: mutedCol,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Neumorphic Components ─────────────────────────────────────────────

class _VolumeArcPainter extends CustomPainter {
  final double volume;
  final bool isDark;

  _VolumeArcPainter({required this.volume, required this.isDark});

  void _drawMaterialIcon(Canvas canvas, Offset offset, IconData icon,
      Color color, double size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      offset.translate(
          -textPainter.width / 2, -textPainter.height / 2),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    const startAngle = pi * 0.75;
    const sweepFull = pi * 1.5;
    const endAngle = startAngle + sweepFull;

    final trackPaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.10)
          : Colors.black.withOpacity(0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepFull,
      false,
      trackPaint,
    );

    if (volume > 0.0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final gradientShader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepFull * volume,
        colors: const [
          Color(0xFF0A4FD6),
          Color(0xFF1A7EFF),
          Color(0xFF5BB8FF),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(rect);

      final volumePaint = Paint()
        ..shader = gradientShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        startAngle,
        sweepFull * volume,
        false,
        volumePaint,
      );

      final thumbAngle = startAngle + sweepFull * volume;
      final thumbX = center.dx + radius * cos(thumbAngle);
      final thumbY = center.dy + radius * sin(thumbAngle);

      canvas.drawCircle(
          Offset(thumbX, thumbY), 8, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(thumbX, thumbY), 5,
          Paint()..color = const Color(0xFF4993FC));
    }

    const iconBlue = Color(0xFF4993FC);
    final iconRadius = radius + 24;

    final startIconX = center.dx + iconRadius * cos(startAngle);
    final startIconY = center.dy + iconRadius * sin(startAngle);

    final IconData volumeIcon;
    if (volume <= 0.0) {
      volumeIcon = Icons.volume_off_rounded;
    } else if (volume >= 1.0) {
      volumeIcon = Icons.volume_up_rounded;
    } else {
      volumeIcon = Icons.volume_down_rounded;
    }

    _drawMaterialIcon(
        canvas, Offset(startIconX, startIconY), Icons.volume_mute_rounded, iconBlue, 22.0);

    final endIconX = center.dx + iconRadius * cos(endAngle);
    final endIconY = center.dy + iconRadius * sin(endAngle);
    _drawMaterialIcon(
        canvas, Offset(endIconX, endIconY), Icons.volume_up_rounded, iconBlue, 22.0);
  }

  @override
  bool shouldRepaint(covariant _VolumeArcPainter old) {
    return old.volume != volume || old.isDark != isDark;
  }
}

class _Waveform extends StatelessWidget {
  final double progress;
  final bool isDark;
  final ValueChanged<double> onSeek;
  const _Waveform(
      {required this.progress,
      required this.isDark,
      required this.onSeek});

  @override
  Widget build(BuildContext context) {
    const barCount = 34;
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox;
        onSeek(
            (box.globalToLocal(d.globalPosition).dx / box.size.width)
                .clamp(0.0, 1.0));
      },
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox;
        onSeek(
            (box.globalToLocal(d.globalPosition).dx / box.size.width)
                .clamp(0.0, 1.0));
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
              final weighting =
                  (1.0 - (pct - 0.5).abs() * 1.6).clamp(0.2, 1.0);
              final barHeight = 12 +
                  (weighting *
                      48 *
                      (0.5 + Random(i + 100).nextDouble() * 0.5));
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 6,
                height: barHeight,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF0066CC)
                      : (isDark
                          ? Colors.white10
                          : const Color(0xFFE2E8F0)),
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
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    path.moveTo(size.width - 26, 26);
    path.quadraticBezierTo(
        0, size.height * 0.5, 20, size.height - 20);
    canvas.drawPath(path.shift(const Offset(-2, 4)), shadowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NeuBtn extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final bool isDark;
  final VoidCallback onTap;
  final double size;
  const _NeuBtn({
    required this.icon,
    required this.color,
    required this.bg,
    required this.isDark,
    required this.onTap,
    required this.size,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: isDark ? Colors.black54 : Colors.grey[300]!,
                    blurRadius: 10,
                    offset: const Offset(5, 5)),
                BoxShadow(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.white,
                    blurRadius: 10,
                    offset: const Offset(-5, -5)),
              ]),
          child: Icon(icon, color: color, size: size * 0.5),
        ),
      );
}

class _NeuIconBox extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final Color bg, color;
  final double size;

  const _NeuIconBox({
    required this.icon,
    required this.isDark,
    required this.bg,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: isDark ? Colors.black54 : Colors.grey[300]!,
                blurRadius: 14,
                offset: const Offset(6, 6)),
            BoxShadow(
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                blurRadius: 14,
                offset: const Offset(-6, -6)),
          ],
        ),
        child: Icon(icon, color: color, size: size * 0.46),
      );
}

class _NeuDivider extends StatelessWidget {
  final bool isDark;
  const _NeuDivider({required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            Colors.transparent,
            isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
            Colors.transparent,
          ]),
        ),
      );
}