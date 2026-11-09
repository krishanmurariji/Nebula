import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/youtube_search_service.dart';
import '../widgets/search_filter_bar.dart';

enum SearchStatus { idle, loading, loaded, error }

class SearchState {
  final List<Song> results;
  final SearchStatus status;
  final String? error;
  final String query;
  const SearchState({
    this.results = const [], this.status = SearchStatus.idle,
    this.error, this.query = '',
  });
  SearchState copyWith({
    List<Song>? results, SearchStatus? status, String? error, String? query,
  }) => SearchState(
    results: results ?? this.results,
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
      final results = await _ref.read(searchServiceProvider).searchSongs(query);
      if (!mounted || mine != _seq) return;
      state = state.copyWith(status: SearchStatus.loaded, results: results);
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


/// The results to show for [filter]. "Official only" keeps just the uploads
/// the ranking trusts (Topic / VEVO / label / the artist's own channel).
List<Song> applySearchFilter(List<Song> songs, SearchFilter filter) =>
    filter == SearchFilter.officialOnly
        ? songs.where((s) => s.isOfficial).toList()
        : songs;

const _kFilterKey = 'search_filter';

/// The chosen filter, remembered between launches. Official only by default.
class SearchFilterNotifier extends StateNotifier<SearchFilter> {
  SearchFilterNotifier() : super(SearchFilter.officialOnly) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_kFilterKey);
      if (!mounted) return;
      if (saved == SearchFilter.bestMatch.name) {
        state = SearchFilter.bestMatch;
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
