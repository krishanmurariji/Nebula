import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/youtube_search_service.dart';
import '../widgets/search_filter_bar.dart';

enum SearchStatus { idle, loading, loaded, error }

class SearchState {
  /// Best match first (Noor's ranking).
  final List<Song> results;

  /// Every result in YouTube's own order (the "All" filter). Empty means
  /// "same as [results]".
  final List<Song> all;
  final SearchStatus status;
  final String? error;
  final String query;
  const SearchState({
    this.results = const [], this.all = const [], this.status = SearchStatus.idle,
    this.error, this.query = '',
  });
  SearchState copyWith({
    List<Song>? results, List<Song>? all, SearchStatus? status, String? error, String? query,
  }) => SearchState(
    results: results ?? this.results,
    all:     all     ?? this.all,
    status:  status  ?? this.status,
    error:   error,
    query:   query   ?? this.query,
  );
}

final searchServiceProvider =
    Provider<YoutubeSearchService>((ref) => YoutubeSearchService());

/// Strips control characters and caps the length of what the user typed.
String sanitizeQuery(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').trim();
  final collapsed = cleaned.replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.length > 150 ? collapsed.substring(0, 150) : collapsed;
}

class SearchNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  SearchNotifier(this._ref) : super(const SearchState());

  // Each search gets a number; only the newest one may update the screen, so a
  // slow earlier search can never overwrite the results of a later one.
  int _seq = 0;

  Future<void> search(String rawQuery) async {
    final query = sanitizeQuery(rawQuery);
    final mine = ++_seq;
    if (query.isEmpty) { state = const SearchState(); return; }
    state = state.copyWith(status: SearchStatus.loading, query: query, error: null);
    try {
      final r = await _ref.read(searchServiceProvider).searchAll(query);
      if (!mounted || mine != _seq) return;
      state = state.copyWith(
          status: SearchStatus.loaded, results: r.ranked, all: r.all);
    } catch (e) {
      if (!mounted || mine != _seq) return;
      state = state.copyWith(
          status: SearchStatus.error,
          error: e is SearchException
              ? e.message
              : 'Search failed. Check your connection and try again.');
    }
  }

  void clear() {
    _seq++; // cancels the effect of any search still in flight
    state = const SearchState();
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) => SearchNotifier(ref));


/// Filters a best-match list. "Official only" keeps just the uploads the
/// ranking trusts (Topic / VEVO / label / the artist's own channel).
List<Song> applySearchFilter(List<Song> songs, SearchFilter filter) =>
    filter == SearchFilter.officialOnly
        ? songs.where((s) => s.isOfficial).toList()
        : songs;

/// What the list shows for [filter]: All = YouTube's order, Best match =
/// Noor's ranking, Official only = the trusted uploads.
List<Song> searchResultsFor(SearchState s, SearchFilter filter) =>
    filter == SearchFilter.all
        ? (s.all.isEmpty ? s.results : s.all)
        : applySearchFilter(s.results, filter);

const _kFilterKey = 'search_filter';

/// The chosen filter, remembered between launches. Best match by default.
class SearchFilterNotifier extends StateNotifier<SearchFilter> {
  SearchFilterNotifier() : super(SearchFilter.bestMatch) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_kFilterKey);
      if (!mounted) return;
      for (final f in SearchFilter.values) {
        if (f.name == saved) state = f;
      }
    } catch (_) {/* default is fine */}
  }

  Future<void> set(SearchFilter filter) async {
    state = filter;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kFilterKey, filter.name);
    } catch (_) {/* not remembering is harmless */}
  }
}

final searchFilterProvider =
    StateNotifierProvider<SearchFilterNotifier, SearchFilter>(
        (ref) => SearchFilterNotifier());
