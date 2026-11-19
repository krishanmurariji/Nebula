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
import '../theme/noor_watermark.dart';
import '../widgets/search_filter_bar.dart';
import '../widgets/song_row.dart';
import '../widgets/offline_pill.dart';
import 'settings_screen.dart';
import 'mini_player.dart';
import '../theme/noor_search_button.dart';

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
      SearchStatus.offline => 'On this phone',
      SearchStatus.loaded => switch (filter) {
          SearchFilter.officialOnly => 'Official uploads',
          SearchFilter.bestMatch => 'Top Results',
          SearchFilter.all => 'All results',
        },
    };

    final offline = search.status == SearchStatus.offline;
    return Column(
      children: [
        if (offline)
          const Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 2, 14, 6),
                child: _SettingsButton(),
              ))
        else
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
            trailing: const _SettingsButton(),
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
      case SearchStatus.offline:
        return _OfflineResults(query: search.query);
      case SearchStatus.idle:
        return const NoorGirlWatermark();
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
      padding: EdgeInsets.only(
          bottom: 120 + MediaQuery.viewInsetsOf(context).bottom),
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final s = songs[i];
        final targetId = ps.pendingSong?.videoId ?? ps.song?.videoId;
        final isCurrent = s.videoId == targetId;
        return NoorSongRow(
          key: ValueKey('search_${s.videoId}'),
          song: s,
          // Tap the card for its details; the play button plays.
          expandable: true,
          artist: s.artist
              .replaceAll(RegExp(r' - topic', caseSensitive: false), '')
              .trim(),
          badge: s.isOfficial ? 'Official' : null,
          current: isCurrent,
          playing: isCurrent && ps.status == NebulaPlayerStatus.playing,
          loading: isCurrent &&
              (ps.status == NebulaPlayerStatus.loading ||
                  (ps.pendingSong != null &&
                      ps.status != NebulaPlayerStatus.playing &&
                      ps.status != NebulaPlayerStatus.paused)),
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

/// A small gear in an empty ring, beside the search filters: opens Settings.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton();

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Semantics(
      container: true,
      button: true,
      label: 'Settings',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          FocusScope.of(context).unfocus();
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.ac, width: 0.8),
          ),
          child: Icon(Icons.settings_outlined, size: 19, color: t.ac),
        ),
      ),
    );
  }
}

/// Search as a page of its own, opened from the player's Search button, so
/// back (or Cancel) returns to the player rather than to Home.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _run() {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    ref.read(searchProvider.notifier).search(q);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = NoorTheme.of(context);
    return Scaffold(
      backgroundColor: t.bg,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top + 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
            child: SizedBox(
              height: 44,
              child: Row(children: [
                const NoorWordmark(height: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 40,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: t.ac, width: 0.8),
                    ),
                    child: TextField(
                      controller: _query,
                      focusNode: _focus,
                      onSubmitted: (_) => _run(),
                      textInputAction: TextInputAction.search,
                      textAlignVertical: TextAlignVertical.center,
                      cursorColor: t.ac,
                      style: TextStyle(
                          color: t.ac,
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        hintText: 'Songs, artists…',
                        hintStyle:
                            TextStyle(color: t.mute, fontSize: 14, height: 1.2),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                NoorSearchButton(
                    open: true, onTap: () => Navigator.of(context).maybePop()),
              ]),
            ),
          ),
          const NoorOfflinePill(),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: SearchPanel(onRetry: _run)),
              // The bottom card shows "Loading…" and the song that plays.
              // Tapping it goes back to the player (already open below).
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MiniPlayer(
                      onOpen: () => Navigator.of(context).maybePop())),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Searching without internet: say so, then show the songs on the phone (its
/// own music and the songs Noor saved) that match the words typed.
class _OfflineResults extends ConsumerWidget {
  const _OfflineResults({required this.query});
  final String query;

  /// Every song that can play right now without internet.
  static List<Song> playableOffline(WidgetRef ref) {
    final onDevice = ref.watch(isOnDeviceProvider);
    final seen = <String>{};
    final out = <Song>[];
    void take(Iterable<Song> l) {
      for (final s in l) {
        if ((s.isLocal || onDevice(s.videoId)) && seen.add(s.videoId))
          out.add(s);
      }
    }

    take(ref.watch(myMusicProvider));
    take(ref.watch(likedSongsProvider));
    take(ref.watch(historyProvider));
    for (final p in ref.watch(playlistProvider)) {
      take(p.songs);
    }
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final ps = ref.watch(playerProvider);
    final words =
        query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final matches = playableOffline(ref).where((s) {
      final hay = '${s.title} ${s.artist}'.toLowerCase();
      return words.every(hay.contains);
    }).toList();

    final banner = Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(children: [
        Icon(Icons.wifi_off_rounded, size: 20, color: t.ac),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              "You're offline. Showing songs on this phone that match "
              '"$query".',
              style: TextStyle(color: t.ac, fontSize: 13, height: 1.3)),
        ),
      ]),
    );

    if (matches.isEmpty) {
      return Column(children: [
        banner,
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 110),
              child: Text(
                  'No saved song matches. Search YouTube again when you are back online.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.mute, fontSize: 13)),
            ),
          ),
        ),
      ]);
    }
    return ListView.builder(
      padding: EdgeInsets.only(
          bottom: 120 + MediaQuery.viewInsetsOf(context).bottom),
      physics: const BouncingScrollPhysics(),
      itemCount: matches.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return banner;
        final s = matches[i - 1];
        final isCurrent =
            (ps.pendingSong?.videoId ?? ps.song?.videoId) == s.videoId;
        void play() {
          HapticFeedback.lightImpact();
          if (ps.song?.videoId == s.videoId) {
            ref.read(playerProvider.notifier).togglePlay();
          } else {
            ref.read(playerProvider.notifier).playSong(s, queue: matches);
          }
        }

        return NoorSongRow(
          key: ValueKey('offline_${s.videoId}'),
          song: s,
          current: isCurrent,
          playing: isCurrent && ps.status == NebulaPlayerStatus.playing,
          loading: isCurrent && ps.status == NebulaPlayerStatus.loading,
          onTap: play,
          onPlayPause: play,
        );
      },
    );
  }
}
