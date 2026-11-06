import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../services/youtube_search_service.dart';

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
