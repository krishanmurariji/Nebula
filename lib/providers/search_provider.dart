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

class SearchNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  SearchNotifier(this._ref) : super(const SearchState());

  Future<void> search(String query) async {
    if (query.trim().isEmpty) { state = const SearchState(); return; }
    state = state.copyWith(status: SearchStatus.loading, query: query, error: null);
    try {
      final results = await _ref.read(searchServiceProvider).searchSongs(query);
      state = state.copyWith(status: SearchStatus.loaded, results: results);
    } catch (e) {
      state = state.copyWith(status: SearchStatus.error, error: e.toString());
    }
  }

  void clear() => state = const SearchState();
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) => SearchNotifier(ref));
