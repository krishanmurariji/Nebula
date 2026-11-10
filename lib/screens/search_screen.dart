import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/search_provider.dart';
import '../providers/player_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/noor_album_tile.dart';
import '../theme/noor_palette.dart';
import '../theme/noor_widgets.dart';
import '../widgets/search_filter_bar.dart';
import 'mini_player.dart';
import 'player_screen.dart';

/// The search page. It is a normal route (opened from Home with the ring
/// wipe), so the phone's back button or gesture returns to Home.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    if (q.trim().isEmpty) return;
    ref.read(searchProvider.notifier).search(q);
    FocusScope.of(context).unfocus();
  }

  void _openFilters() {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close filters',
      barrierColor: NoorTheme.of(context).ac.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => const _FilterSheet(),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchProvider);
    final filter = ref.watch(searchFilterProvider);
    final player = ref.watch(playerProvider);
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;
    final likedSongs = ref.watch(likedSongsProvider);
    ref.watch(historyProvider); // keep it loaded: it becomes the queue when you play a result
    final t = NoorTheme.byMode(isDark);

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: NoorBackdrop()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // ── Search bar + filter button ───────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: NoorFrame(
                          radius: 24,
                          ring: false,
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _ctrl,
                              onSubmitted: _search,
                              onChanged: (_) => setState(() {}),
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              cursorColor: t.ac,
                              style: TextStyle(
                                  color: t.ac,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                hintText: 'Artists, songs...',
                                hintStyle:
                                    TextStyle(color: t.mute, fontSize: 14),
                                prefixIcon: Icon(Icons.search,
                                    color: t.ac, size: 20),
                                suffixIcon: _ctrl.text.isNotEmpty
                                    ? IconButton(
                                        tooltip: 'Clear',
                                        icon: Icon(Icons.close,
                                            color: t.mute, size: 18),
                                        onPressed: () {
                                          _ctrl.clear();
                                          ref
                                              .read(searchProvider.notifier)
                                              .clear();
                                          setState(() {});
                                        })
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      NoorRoundButton(
                        size: 48,
                        semanticLabel: 'Filters',
                        filled: filter == SearchFilter.bestMatch,
                        onTap: _openFilters,
                        child: const Icon(Icons.tune_rounded),
                      ),
                    ],
                  ),
                ),

                // ── Results & mini player ────────────────────────────────
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ShaderMask(
                          shaderCallback: (Rect bounds) => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Colors.white.withOpacity(0.0)
                            ],
                            stops: const [0.0, 0.88, 1.0],
                          ).createShader(bounds),
                          blendMode: BlendMode.dstIn,
                          child: _buildBody(
                              search, player, isDark, likedSongs, filter),
                        ),
                      ),
                      const Positioned(
                          left: 0, right: 0, bottom: 0, child: MiniPlayer()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillButton(NoorTheme t, String text, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          decoration: BoxDecoration(
              color: t.ac, borderRadius: BorderRadius.circular(30)),
          child: Text(text,
              style: TextStyle(color: t.bg, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _buildBody(SearchState search, NebulaPlayerState player, bool isDark,
      List<Song> likedSongs, SearchFilter filter) {
    final t = NoorTheme.byMode(isDark);
    switch (search.status) {
      case SearchStatus.loading:
        return Center(
            child: CircularProgressIndicator(color: t.ac, strokeWidth: 2));
      case SearchStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wifi_off_outlined, size: 52, color: t.soft),
              const SizedBox(height: 16),
              Text(search.error ?? 'Error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.mute)),
              const SizedBox(height: 20),
              _pillButton(t, 'Retry', () => _search(_ctrl.text)),
            ]),
          ),
        );
      case SearchStatus.loaded:
        if (search.results.isEmpty) {
          return const NoorEmptyState(message: 'No results found');
        }
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
                    style: TextStyle(
                        color: t.ac.withOpacity(0.8),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text('${search.results.length} other results are available.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.mute, fontSize: 13)),
                const SizedBox(height: 20),
                _pillButton(
                    t,
                    'Show all results',
                    () => ref
                        .read(searchFilterProvider.notifier)
                        .set(SearchFilter.bestMatch)),
              ]),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 150),
          physics: const BouncingScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        filter == SearchFilter.officialOnly
                            ? 'Official uploads'
                            : 'Top Results',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: noorSerif(t.ac, size: 28, height: 1.0)),
                  ),
                  Text('${visible.length} songs',
                      style: TextStyle(
                          color: t.mute,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            ...visible.map((s) {
              final isCurrent = player.song?.videoId == s.videoId;
              final playing = isCurrent &&
                  player.status == NebulaPlayerStatus.playing;
              final loading = isCurrent &&
                  player.status == NebulaPlayerStatus.loading;
              final liked =
                  likedSongs.any((l) => l.videoId == s.videoId);
              return NoorAlbumTile(
                thumbnailUrl: s.thumbnailUrl,
                title: s.title,
                channel: s.artist
                    .replaceAll(RegExp(r' - topic', caseSensitive: false), '')
                    .trim(),
                isOfficial: s.isOfficial,
                liked: liked,
                selected: isCurrent,
                loading: loading,
                playing: playing,
                onToggleLike: () {
                  HapticFeedback.mediumImpact();
                  ref.read(likedProvider.notifier).toggle(s);
                },
                onPlay: () {
                  // "Up next" is what you played recently, not the search results.
                  final recent = ref
                      .read(historyProvider)
                      .where((h) => h.videoId != s.videoId)
                      .toList();
                  ref
                      .read(playerProvider.notifier)
                      .playSong(s, queue: [s, ...recent]);
                  ref.read(historyProvider.notifier).add(s);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PlayerScreen()));
                },
              );
            }),
          ],
        );
      default:
        return const NoorEmptyState(
          message: 'Search for any song or artist',
          hint: 'Type above and press search.',
        );
    }
  }
}

/// The filter pop-up: drops from the top and covers about 30% of the screen.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = NoorTheme.of(context);
    final filter = ref.watch(searchFilterProvider);
    final h = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;

    Widget option(SearchFilter f, IconData icon, String title, String sub) {
      final on = filter == f;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(searchFilterProvider.notifier).set(f);
        },
        child: Semantics(
          button: true,
          selected: on,
          label: title,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: on ? t.wash : null,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: on ? t.ac : t.soft, width: 1),
            ),
            child: Row(
              children: [
                Icon(icon, color: t.ac, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: t.ac,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      Text(sub,
                          style: TextStyle(color: t.mute, fontSize: 11.5)),
                    ],
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? t.ac : null,
                    border: Border.all(color: t.ac, width: 1),
                  ),
                  child: on
                      ? Icon(Icons.check_rounded, size: 14, color: t.onAc)
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          height: h * 0.30,
          padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 12),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(28)),
            border: Border.all(color: t.soft, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text('Show results',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: noorSerif(t.ac, size: 26, height: 1.0)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: t.ac,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text('Apply',
                          style: TextStyle(
                              color: t.onAc,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              option(SearchFilter.officialOnly, Icons.verified_outlined,
                  'Official only', 'Topic, VEVO, labels and the artist'),
              option(SearchFilter.bestMatch, Icons.auto_awesome_outlined,
                  'Best match', 'Everything, best first'),
              const Spacer(),
              Center(
                child: Text('Your choice is remembered.',
                    style: TextStyle(color: t.mute, fontSize: 11.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
