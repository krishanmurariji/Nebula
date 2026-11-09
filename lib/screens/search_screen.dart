import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/search_provider.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'player_screen.dart';
import 'mini_player.dart';
import '../widgets/search_filter_bar.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_song_tile.dart';
import '../theme/noor_widgets.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final void Function(int) onNavigate;
  const SearchScreen({super.key, required this.onNavigate});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _search(String q) {
    if (q.trim().isEmpty) return;
    ref.read(searchProvider.notifier).search(q);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final search  = ref.watch(searchProvider);
    final filter  = ref.watch(searchFilterProvider);
    final player  = ref.watch(playerProvider);
    final isDark  = ref.watch(themeProvider) == ThemeMode.dark;
    
    // Watch liked songs to show the heart badge on search results
    final likedSongs = ref.watch(likedSongsProvider); 
    
    final t       = NoorTheme.byMode(isDark);
    final bg      = t.bg;
    final textCol = t.ac;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: NoorBackdrop()),

          // ── Main Foreground Content ───────────────────────────────────────
          SafeArea(
            bottom: false, 
            child: Column(
              children: [
                // ── Search bar ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: NoorFrame(
                    radius: 26,
                    child: SizedBox(
                    height: 46,
                    child: TextField(
                      controller: _ctrl,
                      onSubmitted: _search,
                      onChanged: (_) => setState(() {}),
                      autofocus: false, 
                      textInputAction: TextInputAction.search,
                      cursorColor: t.ac,
                      style: TextStyle(color: textCol, fontSize: 14, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Artists, songs...',
                        hintStyle: TextStyle(color: t.mute, fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: t.ac, size: 20),
                        suffixIcon: _ctrl.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close, color: t.mute, size: 18),
                                onPressed: () {
                                  _ctrl.clear();
                                  ref.read(searchProvider.notifier).clear();
                                  setState(() {});
                                })
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13)
                      ),
                    ),
                    ),
                  ),
                ),

                // ── Filter chips (only once there are results) ───────────────
                if (search.status == SearchStatus.loaded && search.results.isNotEmpty)
                  SearchFilterBar(
                    filter: filter,
                    isDark: isDark,
                    totalCount: search.results.length,
                    officialCount: search.results.where((s) => s.isOfficial).length,
                    onChanged: (f) => ref.read(searchFilterProvider.notifier).set(f),
                  ),

                // ── Results & MiniPlayer Stack ────────────────────────────────
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.white, Colors.white, Colors.white.withOpacity(0.0)],
                              stops: const [0.0, 0.85, 1.0],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.dstIn,
                          child: _buildBody(search, player, textCol, isDark, likedSongs, filter),
                        ),
                      ),

                      const Positioned(
                        left: 0, right: 0, bottom: 0,
                        child: MiniPlayer(),
                      ),
                    ],
                  ),
                ),
              ]
            )
          ),
        ],
      ),
    );
  }

  Widget _buildBody(SearchState search, NebulaPlayerState player, Color textCol, bool isDark, List<Song> likedSongs, SearchFilter filter) {
    final t = NoorTheme.byMode(isDark);
    switch (search.status) {
      case SearchStatus.loading:
        return Center(child: CircularProgressIndicator(
            color: t.ac, strokeWidth: 2));
      case SearchStatus.error:
        return Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off_outlined, size: 52, color: t.soft),
            const SizedBox(height: 16),
            Text(search.error ?? 'Error', textAlign: TextAlign.center,
              style: TextStyle(color: t.mute)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => _search(_ctrl.text),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(color: t.ac,
                    borderRadius: BorderRadius.circular(30)),
                child: Text('Retry', style: TextStyle(color: t.bg,
                    fontWeight: FontWeight.w600)))),
          ])));
      case SearchStatus.loaded:
        if (search.results.isEmpty) return Center(
          child: Text('No results found',
              style: TextStyle(color: t.mute)));
        final visible = applySearchFilter(search.results, filter);
        if (visible.isEmpty) {
          // The filter hid everything: say so and offer the way out.
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_outlined, size: 52, color: t.soft),
                const SizedBox(height: 16),
                Text('No official upload found for this search',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textCol.withOpacity(0.7), fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('${search.results.length} other results are available.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.mute, fontSize: 13)),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => ref.read(searchFilterProvider.notifier).set(SearchFilter.bestMatch),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    decoration: BoxDecoration(color: t.ac,
                        borderRadius: BorderRadius.circular(30)),
                    child: Text('Show all results', style: TextStyle(
                        color: t.bg, fontWeight: FontWeight.w600)))),
              ]),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 130), 
          physics: const BouncingScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
              child: Text(
                  filter == SearchFilter.officialOnly ? 'Official uploads' : 'Top Results',
                  style: noorSerif(textCol, size: 28, height: 1.0))),
            ...visible.map((s) {
              final isPlaying = player.song?.videoId == s.videoId &&
                  (player.status == NebulaPlayerStatus.playing || player.status == NebulaPlayerStatus.loading);
              
              final isLiked = likedSongs.any((liked) => liked.videoId == s.videoId);
              
              return _CapsuleSongTile(
                song: s,
                isPlaying: isPlaying,
                isLiked: isLiked,
                isDark: isDark,
                onTap: () {
                  // Next/Previous stay within what is on screen.
                  ref.read(playerProvider.notifier)
                      .playSong(s, queue: visible);
                  ref.read(historyProvider.notifier).add(s);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PlayerScreen()));
                },
              );
            }),
          ],
        );
      default:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NoorRoundButton(size: 72, child: Icon(Icons.search_rounded)),
              const SizedBox(height: 20),
              Text('Search for any song or artist',
                  style: TextStyle(color: t.mute)),
            ]
          )
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PREMIUM CAPSULE TILE (With Smart Badges & Verified Icon)
// ═══════════════════════════════════════════════════════════════════════════════
class _CapsuleSongTile extends StatelessWidget {
  final Song song;
  final bool isPlaying;
  final bool isLiked;
  final bool isDark;
  final VoidCallback onTap;

  const _CapsuleSongTile({
    required this.song,
    required this.isPlaying,
    required this.isLiked,
    required this.isDark,
    required this.onTap,
  });

  Widget _tag(NoorTheme t, String text) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: t.soft, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: t.ac,
                letterSpacing: 0.6)),
      );

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.byMode(isDark);

    // Smart badge: official upload, live recording or cover.
    final titleLower = song.title.toLowerCase();
    final isLive = titleLower.contains('live');
    final isCover = titleLower.contains('cover');
    final isOfficial = song.isOfficial;
    final cleanArtist =
        song.artist.replaceAll(RegExp(r' - topic', caseSensitive: false), '').trim();

    return NoorSongTile(
      height: 76,
      thumbnailUrl: song.thumbnailUrl,
      title: song.title,
      selected: isPlaying,
      onTap: onTap,
      subtitle: Row(
        children: [
          if (isOfficial)
            _tag(t, 'OFFICIAL')
          else if (isLive)
            _tag(t, 'LIVE')
          else if (isCover)
            _tag(t, 'COVER'),
          Flexible(
            child: Text(cleanArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: noorSubtitleStyle(context)),
          ),
          if (isOfficial) ...[
            const SizedBox(width: 4),
            Icon(Icons.check_circle_outline_rounded, size: 12, color: t.ac),
          ],
        ],
      ),
      extras: [
        if (isLiked)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Icon(Icons.favorite_rounded, color: t.ac, size: 17),
          ),
      ],
      trailing: NoorRoundButton(
        size: 38,
        filled: isPlaying,
        muted: !isPlaying,
        child: Icon(isPlaying ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
            size: 20),
      ),
    );
  }
}
