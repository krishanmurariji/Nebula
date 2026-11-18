import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_song_card.dart';
import '../theme/noor_widgets.dart';
import '../widgets/search_filter_bar.dart';

/// What sits under the search bar on Home: the Best match / Official only
/// chips, a centred label between two thin lines, then the results as song
/// cards. Before any search, a large faded Noor mark.
class SearchPanel extends ConsumerWidget {
  const SearchPanel({super.key, required this.onRetry});

  /// Runs the last search again (after an error).
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final search = ref.watch(searchProvider);
    final filter = ref.watch(searchFilterProvider);
    ref.watch(historyProvider); // keep it loaded: it becomes the queue

    final official = search.results.where((s) => s.isOfficial).length;
    final label = switch (search.status) {
      SearchStatus.idle => 'Search',
      SearchStatus.loading => 'Searching…',
      SearchStatus.error => 'Search',
      SearchStatus.loaded => switch (filter) {
          SearchFilter.officialOnly => 'Official uploads',
          SearchFilter.bestMatch => 'Top Results',
          SearchFilter.all => 'All results',
        },
    };

    return Column(
      children: [
        SearchFilterBar(
          filter: filter,
          onChanged: (f) {
            HapticFeedback.selectionClick();
            ref.read(searchFilterProvider.notifier).set(f);
          },
          totalCount: search.results.length,
          allCount: search.all.isEmpty ? null : search.all.length,
          officialCount: official,
          isDark: t.isDark,
        ),
        const SizedBox(height: 6),
        NoorLinedLabel(label),
        const SizedBox(height: 6),
        Expanded(child: _body(context, ref, t, search, filter)),
      ],
    );
  }

  Widget _pill(NoorTheme t, String text, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kNoorCardRadius),
              border: Border.all(color: t.ac, width: 0.8)),
          child: Text(text,
              style: TextStyle(color: t.ac, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _body(BuildContext context, WidgetRef ref, NoorTheme t,
      SearchState search, SearchFilter filter) {
    switch (search.status) {
      case SearchStatus.idle:
        return const _Watermark();
      case SearchStatus.loading:
        return Center(
            child: CircularProgressIndicator(color: t.ac, strokeWidth: 1.6));
      case SearchStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wifi_off_outlined, size: 44, color: t.ac),
              const SizedBox(height: 14),
              Text(search.error ?? 'Error',
                  textAlign: TextAlign.center, style: TextStyle(color: t.mute)),
              const SizedBox(height: 18),
              _pill(t, 'Retry', onRetry),
            ]),
          ),
        );
      case SearchStatus.loaded:
        if (search.results.isEmpty) {
          return const NoorEmptyState(message: 'No results found');
        }
        final visible = searchResultsFor(search, filter);
        if (visible.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.verified_outlined, size: 44, color: t.ac),
                const SizedBox(height: 14),
                Text('No official upload found for this search',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.ac, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('${search.results.length} other results are available.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.mute, fontSize: 13)),
                const SizedBox(height: 18),
                _pill(
                    t,
                    'Show all results',
                    () => ref
                        .read(searchFilterProvider.notifier)
                        .set(SearchFilter.bestMatch)),
              ]),
            ),
          );
        }
        return _Results(songs: visible);
    }
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.songs});
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = ref.watch(playerProvider);
    final liked = ref.watch(likedSongsProvider);

    void play(Song s) {
      HapticFeedback.lightImpact();
      // "Up next" is what you played recently, not the search results.
      final recent = ref
          .read(historyProvider)
          .where((h) => h.videoId != s.videoId)
          .toList();
      ref.read(playerProvider.notifier).playSong(s, queue: [s, ...recent]);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final s = songs[i];
        final targetId = ps.pendingSong?.videoId ?? ps.song?.videoId;
        final isCurrent = s.videoId == targetId;
        return NoorSongCard(
          thumbnailUrl: s.thumbnailUrl,
          title: s.title,
          artist: s.artist
              .replaceAll(RegExp(r' - topic', caseSensitive: false), '')
              .trim(),
          badge: s.isOfficial ? 'Official' : null,
          liked: liked.any((l) => l.videoId == s.videoId),
          current: isCurrent,
          playing: isCurrent && ps.status == NebulaPlayerStatus.playing,
          loading: isCurrent && ps.status == NebulaPlayerStatus.loading,
          onToggleLike: () {
            HapticFeedback.mediumImpact();
            ref.read(likedProvider.notifier).toggle(s);
          },
          onPlayPause: () => ps.song?.videoId == s.videoId
              ? ref.read(playerProvider.notifier).togglePlay()
              : play(s),
          onTap: () => ps.song?.videoId == s.videoId
              ? ref.read(playerProvider.notifier).togglePlay()
              : play(s),
        );
      },
    );
  }
}

/// The Noor mark, large and faded, shown before the first search.
class _Watermark extends StatelessWidget {
  const _Watermark();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 110),
      child: Center(
        child: Opacity(
          opacity: 0.16,
          child: Image.asset('assets/images/noor_girl.png',
              fit: BoxFit.contain, semanticLabel: 'Noor'),
        ),
      ),
    );
  }
}
