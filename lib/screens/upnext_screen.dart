import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/queue_rules.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_song_card.dart';
import '../widgets/song_row.dart';

/// Up next, rising from the bottom of the player. It lists the list the
/// playing song belongs to: its playlist (with the playlist's name), else My
/// Favorites, else My History (just the song itself when nothing has been
/// played before). Hold a song and drag it to change the order.
class UpNextScreen extends ConsumerWidget {
  const UpNextScreen({super.key});

  /// A song was dragged from [from] to [to] (ReorderableListView's indexes):
  /// rearranges the list it belongs to (the playlist, My Favorites or My
  /// History) and tells the player the new order.
  Future<void> _move(
      WidgetRef ref, Song current, List<Song> list, int from, int to) async {
    if (to > from) to -= 1;
    if (from == to || from < 0 || from >= list.length) return;
    HapticFeedback.selectionClick();
    final id = list[from].videoId;
    final source = contextSourceFor(current,
        playlists: ref.read(playlistProvider),
        liked: ref.read(likedSongsProvider));
    switch (source.kind) {
      case 'playlist':
        await ref
            .read(playlistProvider.notifier)
            .moveSong(source.playlistId!, id, to);
      case 'liked':
        await ref.read(likedProvider.notifier).move(id, to);
      default:
        await ref.read(historyProvider.notifier).move(id, to);
    }
    await ref
        .read(playerProvider.notifier)
        .setQueueOrder(moveSongInList(list, id, to));
  }

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
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Tap above the sheet to close it.
          Positioned.fill(
            child: GestureDetector(onTap: () => Navigator.pop(context)),
          ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            // Rides up with the keyboard (when a new playlist is named).
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
                },
                child: Container(
                  // Never taller than the space left above the keyboard.
                  height: min(
                      h * 0.65,
                      MediaQuery.sizeOf(context).height -
                          MediaQuery.viewInsetsOf(context).bottom -
                          MediaQuery.paddingOf(context).top -
                          24),
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
                              // Hold a song and drag it: the list it
                              // comes from is rearranged, and what plays
                              // next follows.
                              : ReorderableListView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(0, 4, 0, 30),
                                  physics: const BouncingScrollPhysics(),
                                  itemCount: list.length,
                                  proxyDecorator: (child, _, anim) =>
                                      AnimatedBuilder(
                                    animation: anim,
                                    builder: (_, c) => Transform.scale(
                                      scale: 1 +
                                          0.04 *
                                              Curves.easeOut
                                                  .transform(anim.value),
                                      child: Material(
                                        color: Colors.transparent,
                                        elevation: 6 * anim.value,
                                        shadowColor: t.ac.withOpacity(0.35),
                                        borderRadius: BorderRadius.circular(
                                            kNoorCardRadius),
                                        child: c,
                                      ),
                                    ),
                                    child: child,
                                  ),
                                  onReorder: (from, to) =>
                                      _move(ref, song!, list.cast(), from, to),
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

                                    return NoorSongRow(
                                      key: ValueKey('upnext_${s.videoId}'),
                                      song: s,
                                      actions: false,
                                      current: isCurrent,
                                      playing: isCurrent &&
                                          ps.status ==
                                              NebulaPlayerStatus.playing,
                                      loading: isCurrent &&
                                          ps.status ==
                                              NebulaPlayerStatus.loading,
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
          ),
        ],
      ),
    );
  }
}
