import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'mini_player.dart';

// ── Panel visibility state ────────────────────────────────────────────────────
enum _PanelState { none, list, naming }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with TickerProviderStateMixin {
  // Which tab: 0=Liked, 1=Playlists, 2=History
  int _tabIndex = 0;

  // Panel animation
  _PanelState _panelState = _PanelState.none;
  late AnimationController _listPanelCtrl;
  late AnimationController _namePanelCtrl;
  late Animation<Offset> _listSlide;
  late Animation<Offset> _nameSlide;
  late Animation<double> _listFade;
  late Animation<double> _nameFade;
  late Animation<double> _scrimOpacity;

  // Naming
  final TextEditingController _nameCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String? _editingPlaylistId;

  @override
  void initState() {
    super.initState();
    _listPanelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _namePanelCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));

    _listSlide = Tween<Offset>(
            begin: const Offset(1.0, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _listPanelCtrl,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic));

    _nameSlide = Tween<Offset>(
            begin: const Offset(-1.0, 0), end: Offset.zero)
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
  }

  @override
  void dispose() {
    _listPanelCtrl.dispose();
    _namePanelCtrl.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  // ── Panel control ──────────────────────────────────────────────────────────

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

  void _openNaming({String? editId, String existingName = ''}) async {
    HapticFeedback.selectionClick();
    _editingPlaylistId = editId;
    _nameCtrl.text = existingName;
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

  Future<void> _confirmNaming() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.mediumImpact();
    _nameFocus.unfocus();

    if (_editingPlaylistId == null) {
      await ref.read(playlistProvider.notifier).create(name);
    }

    await _namePanelCtrl.reverse();
    if (!mounted) return;
    setState(() => _panelState = _PanelState.list);
    _listPanelCtrl.forward(from: 0);
    _nameCtrl.clear();
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    const accentCol = Color(0xFF4993FC);
    final topPad = MediaQuery.of(context).padding.top;
    final screenSize = MediaQuery.of(context).size;

    final liked = ref.watch(likedProvider);
    final playlists = ref.watch(playlistProvider);
    final history = ref.watch(historyProvider);
    final seen = <String>{};
    final distinctHistory =
        history.where((s) => seen.add(s.videoId)).toList();

    final ps = ref.watch(playerProvider);

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Big Background App Logo Watermark ─────────────────────────────
          Positioned.fill(
            child: Center(
              child: Opacity(
                opacity: isDark ? 0.03 : 0.05, 
                child: Image.asset(
                  'assets/images/app_logo_final.png',
                  width: screenSize.width * 0.85, 
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ),
          ),

          // ── Main content ─────────────────────────────────────────────────
          Column(
            children: [
              _buildHeader(topPad, isDark, bg, cardBg, textCol, mutedCol,
                  accentCol),
              _buildTabBar(isDark, bg, cardBg, textCol, mutedCol, accentCol),
              Expanded(
                child: _buildTabContent(
                    isDark, bg, cardBg, textCol, mutedCol, accentCol,
                    liked: liked,
                    playlists: playlists,
                    history: distinctHistory,
                    ps: ps),
              ),
              const SizedBox(height: 80),
            ],
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
          if (_panelState == _PanelState.list ||
              _listPanelCtrl.isAnimating)
            SlideTransition(
              position: _listSlide,
              child: FadeTransition(
                opacity: _listFade,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _PlaylistListPanel(
                    isDark: isDark,
                    bg: bg,
                    cardBg: cardBg,
                    textCol: textCol,
                    mutedCol: mutedCol,
                    accentCol: accentCol,
                    playlists: playlists,
                    onClose: _closeList,
                    onAdd: () => _openNaming(),
                    onRename: (pl) =>
                        _openNaming(editId: pl.id, existingName: pl.name),
                    onDelete: (id) async {
                      HapticFeedback.heavyImpact();
                      await ref
                          .read(playlistProvider.notifier)
                          .delete(id);
                    },
                    onTapPlaylist: (pl) {
                      _closeList();
                    },
                  ),
                ),
              ),
            ),

          // ── Name Panel (slides from left) ────────────────────────────────
          if (_panelState == _PanelState.naming ||
              _namePanelCtrl.isAnimating)
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
                    isEditing: _editingPlaylistId != null,
                    onCancel: _cancelNaming,
                    onConfirm: _confirmNaming,
                  ),
                ),
              ),
            ),

          // ── Mini player ──────────────────────────────────────────────────
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(double topPad, bool isDark, Color bg, Color cardBg,
      Color textCol, Color mutedCol, Color accentCol) {
    return Container(
      color: Colors.transparent,
      padding:
          EdgeInsets.only(top: topPad + 12, left: 20, right: 20, bottom: 12),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Text(
            'Library',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: textCol,
              letterSpacing: -0.6,
            ),
          ),
          const Spacer(),
          _NeuBtn(
            icon: Icons.queue_music_rounded,
            color: accentCol,
            bg: bg,
            isDark: isDark,
            size: 48,
            onTap: _openList,
          ),
        ],
      ),
    );
  }

  // ── Tab Bar ────────────────────────────────────────────────────────────────
  Widget _buildTabBar(bool isDark, Color bg, Color cardBg, Color textCol,
      Color mutedCol, Color accentCol) {
    final tabs = [
      (Icons.favorite_rounded, 'Liked'),
      (Icons.album_rounded, 'Playlists'),
      (Icons.history_rounded, 'History'),
    ];
    return Container(
      color: Colors.transparent, 
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = _tabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _tabIndex = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                margin: EdgeInsets.only(
                    left: i == 0 ? 0 : 6, right: i == 2 ? 0 : 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: active ? accentCol : cardBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: active
                      ? [
                          BoxShadow(
                              color: accentCol.withOpacity(0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4))
                        ]
                      : [
                          BoxShadow(
                              color: isDark
                                  ? Colors.black54
                                  : Colors.grey.shade300,
                              blurRadius: 8,
                              offset: const Offset(3, 3)),
                          BoxShadow(
                              color: isDark
                                  ? Colors.white.withOpacity(0.04)
                                  : Colors.white,
                              blurRadius: 8,
                              offset: const Offset(-3, -3)),
                        ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tabs[i].$1,
                        size: 16,
                        color: active ? Colors.white : accentCol),
                    const SizedBox(width: 6),
                    Text(
                      tabs[i].$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : textCol,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Tab Content ────────────────────────────────────────────────────────────
  Widget _buildTabContent(
    bool isDark,
    Color bg,
    Color cardBg,
    Color textCol,
    Color mutedCol,
    Color accentCol, {
    required List<Song> liked,
    required List<Playlist> playlists,
    required List<Song> history,
    required dynamic ps,
  }) {
    switch (_tabIndex) {
      case 0:
        return _LikedTab(
          songs: liked,
          isDark: isDark,
          bg: bg,
          cardBg: cardBg,
          textCol: textCol,
          mutedCol: mutedCol,
          accentCol: accentCol,
          currentId: ps.song?.videoId,
          onTap: (song) {
            HapticFeedback.lightImpact();
            ref.read(playerProvider.notifier).playSong(song, queue: liked);
          },
          onUnlike: (song) {
            HapticFeedback.selectionClick();
            ref.read(likedProvider.notifier).toggle(song);
          },
          onReorder: (o, n) =>
              ref.read(likedProvider.notifier).reorder(o, n),
        );
      case 1:
        return _PlaylistsTab(
          playlists: playlists,
          isDark: isDark,
          bg: bg,
          cardBg: cardBg,
          textCol: textCol,
          mutedCol: mutedCol,
          accentCol: accentCol,
          currentId: ps.song?.videoId,
          onAddPlaylist: _openList,
          onTapSong: (song, queue) {
            HapticFeedback.lightImpact();
            ref.read(playerProvider.notifier).playSong(song, queue: queue);
          },
          onRemoveSong: (plId, videoId) {
            HapticFeedback.selectionClick();
            ref.read(playlistProvider.notifier).removeSong(plId, videoId);
          },
          onReorderSong: (plId, o, n) =>
              ref.read(playlistProvider.notifier).reorderSong(plId, o, n),
        );
      case 2:
      default:
        return _HistoryTab(
          songs: history,
          isDark: isDark,
          bg: bg,
          cardBg: cardBg,
          textCol: textCol,
          mutedCol: mutedCol,
          accentCol: accentCol,
          currentId: ps.song?.videoId,
          onTap: (song) {
            HapticFeedback.lightImpact();
            ref.read(playerProvider.notifier).playSong(song, queue: history);
          },
          onClear: () {
            HapticFeedback.heavyImpact();
            ref.read(historyProvider.notifier).clear();
          },
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLAYLIST LIST PANEL — slides in from right
// ═══════════════════════════════════════════════════════════════════════════════
class _PlaylistListPanel extends StatelessWidget {
  final bool isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final List<Playlist> playlists;
  final VoidCallback onClose, onAdd;
  final void Function(Playlist) onRename;
  final void Function(String) onDelete;
  final void Function(Playlist) onTapPlaylist;

  const _PlaylistListPanel({
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.playlists,
    required this.onClose,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onTapPlaylist,
  });

  @override
  Widget build(BuildContext context) {
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
                  'My Playlists',
                  style: TextStyle(
                    fontSize: 22,
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
                itemCount: playlists.length,
                itemBuilder: (_, i) {
                  final pl = playlists[i];
                  return _PlaylistRow(
                    pl: pl,
                    isDark: isDark,
                    bg: isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7),
                    cardBg: cardBg,
                    textCol: textCol,
                    mutedCol: mutedCol,
                    accentCol: accentCol,
                    onTap: () => onTapPlaylist(pl),
                    onRename: () => onRename(pl),
                    onDelete: () => onDelete(pl.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final Playlist pl;
  final bool isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final VoidCallback onTap, onRename, onDelete;

  const _PlaylistRow({
    required this.pl,
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                color: isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.white,
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
                      color: isDark
                          ? Colors.black38
                          : Colors.grey.shade200,
                      blurRadius: 6,
                      offset: const Offset(2, 2)),
                ],
              ),
              child: Icon(Icons.queue_music_rounded,
                  color: accentCol, size: 22),
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
            _SmallNeuBtn(
              icon: Icons.edit_rounded,
              color: mutedCol,
              bg: bg,
              isDark: isDark,
              onTap: onRename,
            ),
            const SizedBox(width: 8),
            _SmallNeuBtn(
              icon: Icons.delete_outline_rounded,
              color: Colors.redAccent.withOpacity(0.8),
              bg: bg,
              isDark: isDark,
              onTap: onDelete,
            ),
          ],
        ),
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
  final bool isEditing;
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
    required this.isEditing,
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
      padding: EdgeInsets.only(
          top: topPad + 16, bottom: 32, left: 20, right: 20),
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
                bg: isDark
                    ? const Color(0xFF0D1117)
                    : const Color(0xFFEDF2F7),
                isDark: isDark,
                size: 44,
                onTap: onCancel,
              ),
              const SizedBox(width: 14),
              Text(
                isEditing ? 'Rename' : 'New Playlist',
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
              bg: isDark
                  ? const Color(0xFF0D1117)
                  : const Color(0xFFEDF2F7),
              color: accentCol,
              size: 88,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            isEditing ? 'Enter new name' : 'Give it a name',
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
              color: isDark
                  ? const Color(0xFF0D1117)
                  : const Color(0xFFEDF2F7),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: isDark
                        ? Colors.black54
                        : Colors.grey.shade300,
                    blurRadius: 10,
                    offset: const Offset(4, 4)),
                BoxShadow(
                    color: isDark
                        ? Colors.white.withOpacity(0.04)
                        : Colors.white,
                    blurRadius: 10,
                    offset: const Offset(-4, -4)),
              ],
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(
                  color: textCol,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
              cursorColor: accentCol,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onConfirm(),
              decoration: InputDecoration(
                hintText: 'Playlist name…',
                hintStyle: TextStyle(
                    color: mutedCol.withOpacity(0.5), fontSize: 15),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 16),
                suffixIcon: Icon(Icons.edit_rounded,
                    color: accentCol.withOpacity(0.5), size: 18),
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
              child: Center(
                child: Text(
                  isEditing ? 'Save Changes' : 'Create Playlist',
                  style: const TextStyle(
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

// ═══════════════════════════════════════════════════════════════════════════════
// LIKED TAB
// ═══════════════════════════════════════════════════════════════════════════════
class _LikedTab extends StatelessWidget {
  final List<Song> songs;
  final bool isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final String? currentId;
  final void Function(Song) onTap;
  final void Function(Song) onUnlike;
  final void Function(int, int) onReorder;

  const _LikedTab({
    required this.songs,
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.currentId,
    required this.onTap,
    required this.onUnlike,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return _EmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'No liked songs yet',
        subtitle: 'Double-tap any song to like it',
        isDark: isDark,
        bg: bg,
        accentCol: accentCol,
        mutedCol: mutedCol,
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      physics: const BouncingScrollPhysics(),
      onReorder: onReorder,
      itemCount: songs.length,
      buildDefaultDragHandles: false, // Disables default right-side drag icon
      proxyDecorator: (child, index, anim) => Material(
        color: Colors.transparent,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 1.04)
              .animate(CurvedAnimation(
                  parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      itemBuilder: (_, i) {
        final s = songs[i];
        final isPlaying = s.videoId == currentId;
        
        // Wrap with delayed listener for seamless hold-to-reorder, and dismissible to swipe-right to delete
        return ReorderableDelayedDragStartListener(
          key: ValueKey(s.videoId),
          index: i,
          child: Dismissible(
            key: ValueKey('dismiss_${s.videoId}'),
            direction: DismissDirection.startToEnd,
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              margin: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.shade400,
                borderRadius: BorderRadius.circular(36) // MATCHES NEW CAPSULE
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            ),
            onDismissed: (_) => onUnlike(s),
            child: _SongRow(
              song: s,
              isDark: isDark,
              bg: bg,
              cardBg: cardBg,
              textCol: textCol,
              mutedCol: mutedCol,
              accentCol: accentCol,
              isPlaying: isPlaying,
              onTap: () => onTap(s),
              trailing: const SizedBox.shrink(), 
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLAYLISTS TAB
// ═══════════════════════════════════════════════════════════════════════════════
class _PlaylistsTab extends StatefulWidget {
  final List<Playlist> playlists;
  final bool isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final String? currentId;
  final VoidCallback onAddPlaylist;
  final void Function(Song, List<Song>) onTapSong;
  final void Function(String, String) onRemoveSong;
  final void Function(String, int, int) onReorderSong;

  const _PlaylistsTab({
    required this.playlists,
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.currentId,
    required this.onAddPlaylist,
    required this.onTapSong,
    required this.onRemoveSong,
    required this.onReorderSong,
  });

  @override
  State<_PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<_PlaylistsTab> {
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    if (widget.playlists.isEmpty) {
      return _EmptyState(
        icon: Icons.queue_music_rounded,
        title: 'No playlists yet',
        subtitle: 'Tap the menu icon to create one',
        isDark: widget.isDark,
        bg: widget.bg,
        accentCol: widget.accentCol,
        mutedCol: widget.mutedCol,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      physics: const BouncingScrollPhysics(),
      itemCount: widget.playlists.length,
      itemBuilder: (_, i) {
        final pl = widget.playlists[i];
        final expanded = _expandedId == pl.id;
        return _PlaylistAccordion(
          pl: pl,
          expanded: expanded,
          isDark: widget.isDark,
          bg: widget.bg,
          cardBg: widget.cardBg,
          textCol: widget.textCol,
          mutedCol: widget.mutedCol,
          accentCol: widget.accentCol,
          currentId: widget.currentId,
          onToggle: () {
            HapticFeedback.selectionClick();
            setState(() => _expandedId = expanded ? null : pl.id);
          },
          onTapSong: widget.onTapSong,
          onRemoveSong: widget.onRemoveSong,
          onReorderSong: widget.onReorderSong,
        );
      },
    );
  }
}

class _PlaylistAccordion extends StatelessWidget {
  final Playlist pl;
  final bool expanded, isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final String? currentId;
  final VoidCallback onToggle;
  final void Function(Song, List<Song>) onTapSong;
  final void Function(String, String) onRemoveSong;
  final void Function(String, int, int) onReorderSong;

  const _PlaylistAccordion({
    required this.pl,
    required this.expanded,
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.currentId,
    required this.onToggle,
    required this.onTapSong,
    required this.onRemoveSong,
    required this.onReorderSong,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: isDark ? Colors.black54 : Colors.grey.shade300,
              blurRadius: 10,
              offset: const Offset(4, 4)),
          BoxShadow(
              color: isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.white,
              blurRadius: 10,
              offset: const Offset(-4, -4)),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentCol.withOpacity(0.12),
                      boxShadow: [
                        BoxShadow(
                            color: isDark
                                ? Colors.black38
                                : Colors.grey.shade200,
                            blurRadius: 6,
                            offset: const Offset(2, 2)),
                      ],
                    ),
                    child: Icon(Icons.queue_music_rounded,
                        color: accentCol, size: 22),
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
                                fontWeight: FontWeight.w800,
                                fontSize: 15)),
                        Text('${pl.songs.length} songs',
                            style: TextStyle(
                                color: mutedCol, fontSize: 12)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutBack,
                    child: Icon(Icons.chevron_right_rounded,
                        color: mutedCol, size: 22),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: pl.songs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text('No songs in this playlist',
                        style:
                            TextStyle(color: mutedCol, fontSize: 13)),
                  )
                : Column(
                    children: [
                      _NeuDivider(isDark: isDark),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                        buildDefaultDragHandles: false, // Disabled default drag icons
                        onReorder: (o, n) =>
                            onReorderSong(pl.id, o, n),
                        itemCount: pl.songs.length,
                        proxyDecorator: (child, index, anim) =>
                            Material(
                          color: Colors.transparent,
                          child: child,
                        ),
                        itemBuilder: (_, i) {
                          final s = pl.songs[i];
                          
                          // Seamless hold-to-reorder and swipe right to delete
                          return ReorderableDelayedDragStartListener(
                            key: ValueKey(s.videoId),
                            index: i,
                            child: Dismissible(
                              key: ValueKey('dismiss_${pl.id}_${s.videoId}'),
                              direction: DismissDirection.startToEnd,
                              background: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                margin: const EdgeInsets.symmetric(vertical: 6), // UPDATED MARGIN
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.shade400,
                                  borderRadius: BorderRadius.circular(36) // MATCHES NEW CAPSULE
                                ),
                                child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                              ),
                              onDismissed: (_) => onRemoveSong(pl.id, s.videoId),
                              child: _SongRow(
                                song: s,
                                isDark: isDark,
                                bg: isDark
                                    ? const Color(0xFF0D1117)
                                    : const Color(0xFFEDF2F7),
                                cardBg: cardBg,
                                textCol: textCol,
                                mutedCol: mutedCol,
                                accentCol: accentCol,
                                isPlaying: s.videoId == currentId,
                                onTap: () => onTapSong(s, pl.songs),
                                trailing: const SizedBox.shrink(), 
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HISTORY TAB
// ═══════════════════════════════════════════════════════════════════════════════
class _HistoryTab extends StatelessWidget {
  final List<Song> songs;
  final bool isDark;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final String? currentId;
  final void Function(Song) onTap;
  final VoidCallback onClear;

  const _HistoryTab({
    required this.songs,
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.currentId,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return _EmptyState(
        icon: Icons.history_rounded,
        title: 'No history yet',
        subtitle: 'Play a song to see it here',
        isDark: isDark,
        bg: bg,
        accentCol: accentCol,
        mutedCol: mutedCol,
      );
    }
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text('${songs.length} songs',
                  style: TextStyle(
                      color: mutedCol,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D1117)
                        : const Color(0xFFEDF2F7),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: isDark
                              ? Colors.black54
                              : Colors.grey.shade300,
                          blurRadius: 6,
                          offset: const Offset(2, 2)),
                      BoxShadow(
                          color: isDark
                              ? Colors.white.withOpacity(0.04)
                              : Colors.white,
                          blurRadius: 6,
                          offset: const Offset(-2, -2)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.clear_all_rounded,
                          color: Colors.redAccent.withOpacity(0.8),
                          size: 15),
                      const SizedBox(width: 5),
                      Text('Clear',
                          style: TextStyle(
                              color: Colors.redAccent.withOpacity(0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            physics: const BouncingScrollPhysics(),
            itemCount: songs.length,
            itemBuilder: (_, i) {
              final s = songs[i];
              return _SongRow(
                key: ValueKey(s.videoId + i.toString()),
                song: s,
                isDark: isDark,
                bg: bg,
                cardBg: cardBg,
                textCol: textCol,
                mutedCol: mutedCol,
                accentCol: accentCol,
                isPlaying: s.videoId == currentId,
                trailing: Icon(Icons.access_time_rounded,
                    color: mutedCol.withOpacity(0.4), size: 18),
                onTap: () => onTap(s),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════════

// ── FULLY UPDATED CAPSULE DESIGN FOR LIBRARY LIST ITEMS ──
class _SongRow extends StatelessWidget {
  final Song song;
  final bool isDark, isPlaying;
  final Color bg, cardBg, textCol, mutedCol, accentCol;
  final Widget trailing;
  final VoidCallback onTap;

  const _SongRow({
    super.key,
    required this.song,
    required this.isDark,
    required this.bg,
    required this.cardBg,
    required this.textCol,
    required this.mutedCol,
    required this.accentCol,
    required this.isPlaying,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isPlaying ? accentCol.withOpacity(0.08) : cardBg, // Use cardBg so it looks like a floating pill
          borderRadius: BorderRadius.circular(36), // Fully rounded like the capsule
          border: isPlaying ? Border.all(color: accentCol.withOpacity(0.3), width: 1.5) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 6),
            
            // ── Circular Album Art ──
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3)
                  )
                ],
              ),
              child: ClipOval(
                child: Transform.scale(
                  scale: 1.35, // Eliminates black bars on YouTube thumbnails
                  child: CachedNetworkImage(
                    imageUrl: song.thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.white54, size: 18)
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 14),
            
            // ── Song Info ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isPlaying ? accentCol : textCol,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: mutedCol,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            
            // ── Indicators & Trailing Icons ──
            if (isPlaying)
              Padding(
                padding: const EdgeInsets.only(right: 18.0),
                child: Icon(Icons.equalizer_rounded, color: accentCol, size: 22),
              )
            else if (trailing is! SizedBox) // If there is a trailing icon like the history clock
              Padding(
                padding: const EdgeInsets.only(right: 20.0),
                child: trailing,
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool isDark;
  final Color bg, accentCol, mutedCol;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.bg,
    required this.accentCol,
    required this.mutedCol,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NeuIconBox(
            icon: icon,
            isDark: isDark,
            bg: bg,
            color: accentCol,
            size: 80,
          ),
          const SizedBox(height: 20),
          Text(title,
              style: TextStyle(
                  color: mutedCol,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(
                  color: mutedCol.withOpacity(0.6), fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Neumorphic primitives ─────────────────────────────────────────────────────

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
          child: Icon(icon, color: color, size: size * 0.46),
        ),
      );
}

class _SmallNeuBtn extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final bool isDark;
  final VoidCallback onTap;

  const _SmallNeuBtn({
    required this.icon,
    required this.color,
    required this.bg,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: isDark ? Colors.black45 : Colors.grey[300]!,
                    blurRadius: 7,
                    offset: const Offset(3, 3)),
                BoxShadow(
                    color: isDark
                        ? Colors.white.withOpacity(0.04)
                        : Colors.white,
                    blurRadius: 7,
                    offset: const Offset(-3, -3)),
              ]),
          child: Icon(icon, color: color, size: 17),
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
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.white,
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
            isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.06),
            Colors.transparent,
          ]),
        ),
      );
}