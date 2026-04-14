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
    final player  = ref.watch(playerProvider);
    final isDark  = ref.watch(themeProvider) == ThemeMode.dark;
    
    // Watch liked songs to show the heart badge on search results
    final likedSongs = ref.watch(likedSongsProvider); 
    
    final bg      = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);
    final cardBg  = isDark ? const Color(0xFF161B22) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: bg,
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

          // ── Main Foreground Content ───────────────────────────────────────
          SafeArea(
            bottom: false, 
            child: Column(
              children: [
                // ── Search bar ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.07),
                          blurRadius: 12, offset: const Offset(0, 3)
                        )
                      ]
                    ),
                    child: TextField(
                      controller: _ctrl,
                      onSubmitted: _search,
                      onChanged: (_) => setState(() {}),
                      autofocus: false, 
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: textCol, fontSize: 14, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Artists, songs...',
                        hintStyle: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF4993FC), size: 20),
                        suffixIcon: _ctrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, color: Color(0xFFB0BEC5), size: 18),
                                onPressed: () {
                                  _ctrl.clear();
                                  ref.read(searchProvider.notifier).clear();
                                  setState(() {});
                                })
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
                      ),
                    ),
                  ),
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
                          child: _buildBody(search, player, textCol, isDark, likedSongs),
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

  Widget _buildBody(SearchState search, NebulaPlayerState player, Color textCol, bool isDark, List<Song> likedSongs) {
    switch (search.status) {
      case SearchStatus.loading:
        return const Center(child: CircularProgressIndicator(
            color: Color(0xFF4993FC), strokeWidth: 2));
      case SearchStatus.error:
        return Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_outlined, size: 52, color: Color(0xFFD0DBE8)),
            const SizedBox(height: 16),
            Text(search.error ?? 'Error', textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8A9BB0))),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => _search(_ctrl.text),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFF4993FC),
                    borderRadius: BorderRadius.circular(30)),
                child: const Text('Retry', style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w600)))),
          ])));
      case SearchStatus.loaded:
        if (search.results.isEmpty) return const Center(
          child: Text('No results found',
              style: TextStyle(color: Color(0xFF8A9BB0))));
        return ListView(
          padding: const EdgeInsets.only(bottom: 130), 
          physics: const BouncingScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
              child: Text('Top Results', style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w800, color: textCol))),
            ...search.results.map((s) {
              final isPlaying = player.song?.videoId == s.videoId &&
                  (player.status == NebulaPlayerStatus.playing || player.status == NebulaPlayerStatus.loading);
              
              final isLiked = likedSongs.any((liked) => liked.videoId == s.videoId);
              
              return _CapsuleSongTile(
                song: s,
                isPlaying: isPlaying,
                isLiked: isLiked,
                isDark: isDark,
                onTap: () {
                  ref.read(playerProvider.notifier)
                      .playSong(s, queue: search.results);
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
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                  ]
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/app_logo_final.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.search_outlined, size: 56, color: Color(0xFFD0DBE8)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Search for any song or artist',
                  style: TextStyle(color: textCol.withOpacity(0.5))),
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

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    const accentCol = Color(0xFF4993FC);

    // ── DYNAMIC SMART BADGE LOGIC ──
    final titleLower = song.title.toLowerCase();
    
    // Check if it's live or a cover
    final isLive = titleLower.contains('live');
    final isCover = titleLower.contains('cover');
    
    // We can use the isOfficial property directly from your Song model!
    final isOfficial = song.isOfficial;
    
    // FIX: Using Dart's native caseSensitive parameter instead of the inline (?i) flag
    final cleanArtist = song.artist.replaceAll(RegExp(r' - topic', caseSensitive: false), '').trim();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 76, 
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: isPlaying ? accentCol.withOpacity(0.08) : cardBg,
          borderRadius: BorderRadius.circular(38),
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
              width: 64,
              height: 64,
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
                  scale: 1.35, 
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
            
            // ── Song Info & Badges ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // TITLE
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isPlaying ? accentCol : textCol,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  
                  // BADGES AND ARTIST ROW
                  Row(
                    children: [
                      // ── Smart Badges ──
                      if (isOfficial) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('OFFICIAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: textCol, letterSpacing: 0.5)),
                        ),
                        const SizedBox(width: 6),
                      ] else if (isLive) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('LIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.redAccent, letterSpacing: 0.5)),
                        ),
                        const SizedBox(width: 6),
                      ] else if (isCover) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('COVER', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.orange, letterSpacing: 0.5)),
                        ),
                        const SizedBox(width: 6),
                      ],

                      // ── Artist Name ──
                      Flexible(
                        child: Text(
                          cleanArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: mutedCol,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      
                      // ── Verified Tick ──
                      if (isOfficial) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check_circle, size: 12, color: Color(0xFF4993FC)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            
            // ── Interactive Indicators ──
            if (isLiked)
              const Padding(
                padding: EdgeInsets.only(right: 12.0),
                child: Icon(Icons.favorite_rounded, color: Colors.pinkAccent, size: 18),
              ),
              
            if (isPlaying)
              const Padding(
                padding: EdgeInsets.only(right: 18.0),
                child: Icon(Icons.equalizer_rounded, color: accentCol, size: 22),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 20.0),
                child: Icon(Icons.play_arrow_rounded, color: mutedCol.withOpacity(0.3), size: 24),
              ),
          ],
        ),
      ),
    );
  }
}