import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/search_provider.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/song_tile.dart'; 
import 'player_screen.dart';
import 'mini_player.dart'; // <--- Restored exact original import path

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
                          child: _buildBody(search, player, textCol),
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

  Widget _buildBody(SearchState search, NebulaPlayerState player, Color textCol) {
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
                  player.status == NebulaPlayerStatus.playing;
              
              return SongTile(
                song: s,
                isPlaying: isPlaying,
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