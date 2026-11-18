import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'main_shell.dart';
import 'mini_player.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_record.dart';
import '../theme/noor_song_card.dart';
import '../theme/ripple_ring_clipper.dart';
import '../theme/noor_widgets.dart';

/// One card of the Home slider.
class HomeCategory {
  const HomeCategory(this.id, this.title, this.songs);
  final String id;
  final String title;
  final List<Song> songs;
}

/// The Home slider: My Favorites, My History and My Music are always there
/// (even when empty); playlists with songs follow.
List<HomeCategory> homeCategories({
  required List<Song> liked,
  required List<Song> history,
  required List<Song> onDevice,
  required List<Playlist> playlists,
}) {
  final seen = <String>{};
  final distinctHistory = history.where((s) => seen.add(s.videoId)).toList();
  return [
    HomeCategory('fav', 'My Favorites', liked),
    HomeCategory('hist', 'My History', distinctHistory),
    HomeCategory('music', 'My Music', onDevice),
    for (final p in playlists)
      if (p.songs.isNotEmpty) HomeCategory(p.id, p.name, p.songs),
  ];
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedId;

  void _select(String id) {
    if (_selectedId == id) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedId = id);
  }

  void _toggleLike(Song song) {
    HapticFeedback.mediumImpact();
    ref.read(likedProvider.notifier).toggle(song);
  }

  void _play(Song song, List<Song> queue) {
    HapticFeedback.lightImpact();
    final ps = ref.read(playerProvider);
    if (ps.song?.videoId == song.videoId) {
      ref.read(playerProvider.notifier).togglePlay();
    } else {
      ref.read(playerProvider.notifier).playSong(song, queue: queue);
    }
  }

  void _goToPage(int page) => ref.read(shellTabProvider.notifier).state = page;

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistProvider);
    final history = ref.watch(historyProvider);
    final liked = ref.watch(likedSongsProvider);
    final onDevice = ref.watch(myMusicProvider);
    final ps = ref.watch(playerProvider);
    final libraryReady = ref.watch(libraryReadyProvider).valueOrNull ?? false;
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final t = NoorTheme.byMode(isDark);
    final topPad = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;

    final cats = homeCategories(
        liked: liked,
        history: history,
        onDevice: onDevice,
        playlists: playlists);

    // Start on the first card that has songs; keep the user's own choice.
    var index = cats.indexWhere((c) => c.id == _selectedId);
    if (index < 0) {
      index = max(0, cats.indexWhere((c) => c.songs.isNotEmpty));
      if (libraryReady) _selectedId = cats[index].id;
    }
    final current = cats[index];
    final everythingEmpty = cats.every((c) => c.songs.isEmpty) && libraryReady;

    final visible = 1 + (index > 0 ? 1 : 0) + (index < cats.length - 1 ? 1 : 0);
    final activeWidth =
        screenWidth - 24 - visible * 12.0 - (visible - 1) * 48.0 - 1;

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: topPad + 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: NoorWordmark(height: 30),
              ),
              const SizedBox(height: 6),

              // ── Slider ────────────────────────────────────────────────
              SizedBox(
                height: 176,
                child: GestureDetector(
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -200) {
                      if (index < cats.length - 1) {
                        _select(cats[index + 1].id);
                      } else {
                        _goToPage(2); // past the last card: Library
                      }
                    } else if (v > 200) {
                      if (index > 0) {
                        _select(cats[index - 1].id);
                      } else {
                        _goToPage(0); // before the first card: Search
                      }
                    }
                  },
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: cats.length,
                    itemBuilder: (context, i) {
                      final active = i == index;
                      final adjacent = (i - index).abs() == 1;
                      return GestureDetector(
                        onTap: () => _select(cats[i].id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          width: active ? activeWidth : (adjacent ? 48 : 0),
                          margin: EdgeInsets.symmetric(
                              horizontal: (active || adjacent) ? 6 : 0,
                              vertical: 12),
                          child: (active || adjacent)
                              ? _CategoryCard(
                                  title: cats[i].title, active: active)
                              : const SizedBox.shrink(),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // ── Songs (ring-wipe reveal when the card changes) ─────────
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1100),
                  layoutBuilder: (cur, prev) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...prev, if (cur != null) cur],
                  ),
                  transitionBuilder: (child, animation) {
                    if (child.key != ValueKey(current.id)) return child;
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) => ClipPath(
                        clipper: RippleRingClipper(animation.value),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    key: ValueKey(current.id),
                    color: t.bg,
                    child: !libraryReady
                        ? const SizedBox.expand()
                        : current.songs.isEmpty
                            ? _EmptyList(
                                category: current.id, firstRun: everythingEmpty)
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(0, 4, 0, 120),
                                physics: const BouncingScrollPhysics(),
                                itemCount: current.songs.length,
                                itemBuilder: (context, i) {
                                  final song = current.songs[i];
                                  final targetId = ps.pendingSong?.videoId ??
                                      ps.song?.videoId;
                                  final isCurrent = song.videoId == targetId;
                                  final loading = isCurrent &&
                                      (ps.status ==
                                              NebulaPlayerStatus.loading ||
                                          (ps.pendingSong != null &&
                                              ps.status !=
                                                  NebulaPlayerStatus.playing &&
                                              ps.status !=
                                                  NebulaPlayerStatus.paused));
                                  return NoorSongCard(
                                    thumbnailUrl: song.thumbnailUrl,
                                    title: song.title,
                                    artist: song.artist,
                                    liked: liked
                                        .any((l) => l.videoId == song.videoId),
                                    current: isCurrent,
                                    playing: isCurrent &&
                                        ps.status == NebulaPlayerStatus.playing,
                                    loading: loading,
                                    onTap: () => _play(song, current.songs),
                                    onPlayPause: () =>
                                        _play(song, current.songs),
                                    onToggleLike: () => _toggleLike(song),
                                  );
                                },
                              ),
                  ),
                ),
              ),
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
        ],
      ),
    );
  }
}

/// A slider card: white with a thin accent border, a record in the middle
/// and the name on a small pill. On a collapsed card the name stands upright
/// in the middle; as the card opens it turns flat and slides to the bottom.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.title, required this.active});
  final String title;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      final record = h * 0.64;
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(kNoorCardRadius),
          border: Border.all(color: t.ac, width: 1),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: active ? 1 : 0),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Stack(
            children: [
              Positioned(
                left: (box.maxWidth - record) / 2,
                top: h * 0.07,
                child: Opacity(
                  opacity: 0.55 + 0.45 * v,
                  child: NoorRecord(size: record),
                ),
              ),
              Align(
                alignment: Alignment.lerp(
                    Alignment.center, const Alignment(0, 0.80), v)!,
                child: Transform.rotate(
                  angle: -pi / 2 * (1 - v),
                  // A zero-size anchor lets Align place the label's centre;
                  // the label itself may be wider than a collapsed card.
                  child: SizedBox.shrink(
                    child: OverflowBox(
                      minWidth: 0,
                      minHeight: 0,
                      maxWidth: 400,
                      maxHeight: 60,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: t.bg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: t.ac, width: 0.8),
                        ),
                        child: Text(title,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                                color: t.ac,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// Shown in the list area when the open card has no songs.
class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.category, required this.firstRun});
  final String category;
  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    final (IconData icon, String title, String hint) = firstRun
        ? (
            Icons.queue_music_rounded,
            "Let's play your first song",
            'Slide right to search for one'
          )
        : switch (category) {
            'fav' => (
                Icons.favorite_border_rounded,
                'No favorites yet',
                'Double-tap any song to add it here'
              ),
            'hist' => (
                Icons.history_rounded,
                'Nothing played yet',
                'Slide right to search for a song'
              ),
            _ => (
                Icons.download_done_rounded,
                'No songs on this device yet',
                'Songs you play are saved here to play offline'
              ),
          };
    return Padding(
      padding: const EdgeInsets.only(bottom: 90),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: t.ac),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: t.ac, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.mute, fontSize: 13)),
                if (hint.startsWith('Slide right')) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.east_rounded, size: 16, color: t.mute),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
