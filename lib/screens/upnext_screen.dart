import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/queue_rules.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_song_card.dart';

/// Up next, rising from the bottom of the player. It lists the list the
/// playing song belongs to: its playlist (with the playlist's name), else My
/// Favorites, else My History (just the song itself when nothing has been
/// played before).
class UpNextScreen extends ConsumerWidget {
  const UpNextScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final ps = ref.watch(playerProvider);
    final playlists = ref.watch(playlistProvider);
    final liked = ref.watch(likedSongsProvider);
    final history = ref.watch(historyProvider);
    final song = ps.displaySong;
    final h = MediaQuery.of(context).size.height;

    final title = song == null
        ? 'Up next'
        : contextTitleFor(song,
            playlists: playlists, liked: liked, history: history);
    final list = song == null
        ? const []
        : contextListFor(song,
            playlists: playlists, liked: liked, history: history);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tap above the sheet to close it.
          Positioned.fill(
            child: GestureDetector(onTap: () => Navigator.pop(context)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
              },
              child: Container(
                height: h * 0.65,
                decoration: BoxDecoration(
                  color: t.bg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(32)),
                  border: Border.all(color: t.ac, width: 0.8),
                  boxShadow: [
                    BoxShadow(
                        color: t.ac.withOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(0, -6)),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          height: 4,
                          width: 40,
                          margin: const EdgeInsets.only(top: 12, bottom: 14),
                          decoration: BoxDecoration(
                              color: t.soft,
                              borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      NoorLinedLabel(title),
                      const SizedBox(height: 8),
                      Expanded(
                        child: list.isEmpty
                            ? Center(
                                child: Text('No song available',
                                    style: TextStyle(
                                        color: t.ac,
                                        fontWeight: FontWeight.w600)))
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(0, 4, 0, 30),
                                physics: const BouncingScrollPhysics(),
                                itemCount: list.length,
                                itemBuilder: (_, i) {
                                  final s = list[i];
                                  final isCurrent =
                                      song?.videoId == s.videoId;
                                  void play() {
                                    HapticFeedback.lightImpact();
                                    if (isCurrent) {
                                      ref
                                          .read(playerProvider.notifier)
                                          .togglePlay();
                                    } else {
                                      ref
                                          .read(playerProvider.notifier)
                                          .playSong(s, queue: list.cast());
                                    }
                                  }

                                  return NoorSongCard(
                                    thumbnailUrl: s.thumbnailUrl,
                                    title: s.title,
                                    artist: s.artist,
                                    liked: liked
                                        .any((l) => l.videoId == s.videoId),
                                    current: isCurrent,
                                    playing: isCurrent &&
                                        ps.status ==
                                            NebulaPlayerStatus.playing,
                                    loading: isCurrent &&
                                        ps.status ==
                                            NebulaPlayerStatus.loading,
                                    onToggleLike: () {
                                      HapticFeedback.mediumImpact();
                                      ref
                                          .read(likedProvider.notifier)
                                          .toggle(s);
                                    },
                                    onPlayPause: play,
                                    onTap: play,
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
