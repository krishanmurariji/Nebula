import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/song_tile.dart';
import 'player_screen.dart';
import 'mini_player.dart';

class LibraryScreen extends ConsumerWidget {
  final void Function(int) onNavigate;
  const LibraryScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked     = ref.watch(likedProvider);
    final playlists = ref.watch(playlistProvider);
    final isDark    = ref.watch(themeProvider) == ThemeMode.dark;
    final bg        = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);
    final cardBg    = isDark ? const Color(0xFF161B22) : Colors.white;
    final textCol   = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final mutedCol  = isDark ? Colors.white54 : const Color(0xFF8A9BB0);
    final shadowD   = isDark ? Colors.black54 : const Color(0xFFC8D3DF);
    final shadowL   = isDark ? const Color(0xFF1E2530) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(bottom: false, child: Stack(children: [

        // ── Scrollable content with ShaderMask to fade the bottom ───
        ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.white.withOpacity(0.0)],
              stops: const [0.0, 0.85, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Library', style: TextStyle(fontSize: 30,
                        fontWeight: FontWeight.w900, color: textCol)),
                    GestureDetector(
                      onTap: () => _createPlaylist(context, ref),
                      child: Container(width: 42, height: 42,
                        decoration: BoxDecoration(color: bg, shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: shadowD, blurRadius: 8, offset: const Offset(4,4)),
                            BoxShadow(color: shadowL.withOpacity(0.8),
                                blurRadius: 8, offset: const Offset(-4,-4))]),
                        child: const Icon(Icons.add_rounded,
                            color: Color(0xFF4993FC), size: 22))),
                  ],
                ),
              )),

              if (liked.isNotEmpty) ...[
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
                  child: Text('LIKED SONGS', style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w800, color: mutedCol, letterSpacing: 2)))),
                
                // ── Liked Songs (Pill Shaped matching MiniPlayer) ─────
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => SongListScreen(id: '__liked__',
                        name: 'Liked Songs', songs: liked, isDark: isDark))),
                    child: Container(
                      height: 64, // Exact MiniPlayer height
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(32), // Exact MiniPlayer roundness
                        boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                          blurRadius: 20, offset: const Offset(0, 4))]
                      ),
                      child: Row(children: [
                        Container(width: 46, height: 46, // Matches SongTile thumbnail
                          decoration: const BoxDecoration(
                            color: Color(0xFFFCE4EC),
                            shape: BoxShape.circle),
                          child: const Icon(Icons.favorite_rounded,
                              color: Colors.pinkAccent, size: 24)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Liked Songs', style: TextStyle(fontSize: 14,
                                fontWeight: FontWeight.w700, color: textCol)),
                            const SizedBox(height: 2),
                            Text('${liked.length} songs',
                                style: TextStyle(fontSize: 11, color: mutedCol)),
                          ])),
                        Icon(Icons.chevron_right_rounded, color: mutedCol),
                        const SizedBox(width: 14),
                      ]),
                    ),
                  ),
                )),
              ],

              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
                child: Text('PLAYLISTS', style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w800, color: mutedCol, letterSpacing: 2)))),

              if (playlists.isEmpty)
                SliverToBoxAdapter(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(children: [
                    Container(width: 64, height: 64,
                      decoration: BoxDecoration(color: bg, shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: shadowD, blurRadius: 8, offset: const Offset(4,4)),
                          BoxShadow(color: shadowL.withOpacity(0.8),
                              blurRadius: 8, offset: const Offset(-4,-4))]),
                      child: Icon(Icons.queue_music_rounded, color: mutedCol, size: 28)),
                    const SizedBox(height: 16),
                    Text('No playlists yet', style: TextStyle(color: mutedCol)),
                  ]))),
              
              if (playlists.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 24,
                      mainAxisSpacing: 24, childAspectRatio: 0.8), // Taller ratio for text below
                    delegate: SliverChildBuilderDelegate((_, i) {
                      final pl = playlists[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => SongListScreen(id: pl.id, name: pl.name,
                            songs: pl.songs, isDark: isDark))),
                        // Long press to delete a playlist!
                        onLongPress: () => _confirmDeletePlaylist(context, ref, pl, isDark),
                        child: Column(
                          children: [
                            // ── Circular Disk Layout ────────────────────────
                            Expanded(
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(
                                      color: Colors.black.withOpacity(isDark ? 0.4 : 0.15),
                                      blurRadius: 20, offset: const Offset(0, 10))]),
                                  child: ClipOval(
                                    child: pl.songs.isNotEmpty
                                        ? CachedNetworkImage(imageUrl: pl.songs.first.thumbnailUrl,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) => Container(color: const Color(0xFF4993FC).withOpacity(0.2)))
                                        : Container(color: const Color(0xFF4993FC).withOpacity(0.2),
                                            child: const Icon(Icons.queue_music_rounded,
                                                color: Color(0xFF4993FC), size: 36)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // ── Playlist Titles ─────────────────────────────
                            Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: textCol,
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('${pl.songs.length} songs',
                              style: TextStyle(color: mutedCol, fontSize: 12)),
                          ],
                        ),
                      );
                    }, childCount: playlists.length),
                  )),

              const SliverToBoxAdapter(child: SizedBox(height: 130)),
            ],
          ),
        ),

        // ── Fixed bottom: MiniPlayer ────────────────────────────────
        const Positioned(
          left: 0, right: 0, bottom: 0,
          child: MiniPlayer(),
        ),

      ])),
    );
  }

  void _createPlaylist(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    final isDark = ref.read(themeProvider) == ThemeMode.dark;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
      title: Text('New Playlist', style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          fontWeight: FontWeight.w700)),
      content: TextField(controller: ctrl, autofocus: true,
        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
        decoration: const InputDecoration(hintText: 'Playlist name',
          hintStyle: TextStyle(color: Color(0xFF8A9BB0)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF8A9BB0)))),
        TextButton(onPressed: () async {
          if (ctrl.text.trim().isNotEmpty) {
            await ref.read(playlistProvider.notifier).create(ctrl.text);
            if (context.mounted) Navigator.pop(context);
          }
        }, child: const Text('Create',
          style: TextStyle(color: Color(0xFF4993FC), fontWeight: FontWeight.w700))),
      ]));
  }

  // Confirmation dialog for deleting a playlist
  void _confirmDeletePlaylist(BuildContext context, WidgetRef ref, dynamic pl, bool isDark) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
      title: Text('Delete Playlist', style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          fontWeight: FontWeight.w700)),
      content: Text('Are you sure you want to delete "${pl.name}"?',
        style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF8A9BB0))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF8A9BB0)))),
        TextButton(onPressed: () {
          // Deletes the playlist from the provider
          ref.read(playlistProvider.notifier).delete(pl.id);
          Navigator.pop(context);
        }, child: const Text('Delete',
          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700))),
      ]));
  }
}

class SongListScreen extends ConsumerWidget {
  final String id, name;
  final List<Song> songs;
  final bool isDark;
  const SongListScreen({super.key, required this.id, required this.name,
    required this.songs, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player    = ref.watch(playerProvider);
    final liveSongs = id == '__liked__'
        ? ref.watch(likedProvider)
        : (ref.watch(playlistProvider).where((p) => p.id == id)
              .map((p) => p.songs).firstOrNull ?? songs);
    final bg      = isDark ? const Color(0xFF0D1117) : const Color(0xFFEDF2F7);
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(child: Stack(children: [

        Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: textCol, size: 18),
                onPressed: () => Navigator.pop(context)),
              Expanded(child: Text(name, style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: textCol))),
              if (liveSongs.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    ref.read(playerProvider.notifier)
                        .playSong(liveSongs.first, queue: liveSongs);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PlayerScreen()));
                  },
                  child: Container(width: 40, height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4993FC), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 20))),
            ])),
          Expanded(child: liveSongs.isEmpty
              ? Center(child: Text('No songs yet',
                  style: TextStyle(color: textCol.withOpacity(0.4))))
              : ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Colors.white.withOpacity(0.0)],
                      stops: const [0.0, 0.85, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 130),
                    physics: const BouncingScrollPhysics(),
                    itemCount: liveSongs.length,
                    itemBuilder: (_, i) {
                      final s = liveSongs[i];
                      
                      // ── Wrap SongTile in Dismissible for Swipe-to-Delete ──
                      return Dismissible(
                        key: ValueKey('${id}_${s.videoId}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(32), // Matches SongTile
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
                        ),
                        onDismissed: (_) {
                          if (id == '__liked__') {
                            // Un-like if in liked playlist
                            ref.read(likedProvider.notifier).toggle(s);
                          } else {
                            // Remove from custom playlist using videoId instead of the Song object
                            ref.read(playlistProvider.notifier).removeSong(id, s.videoId);
                          }
                        },
                        child: SongTile(
                          song: s,
                          isPlaying: player.song?.videoId == s.videoId &&
                              player.status == NebulaPlayerStatus.playing,
                          onTap: () {
                            ref.read(playerProvider.notifier).playSong(s, queue: liveSongs);
                            Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const PlayerScreen()));
                          }),
                      );
                    }),
                )),
        ]),

        // ── Fixed bottom: MiniPlayer ────────────────────────────────
        const Positioned(
          left: 0, right: 0, bottom: 0,
          child: MiniPlayer(),
        ),

      ])),
    );
  }
}