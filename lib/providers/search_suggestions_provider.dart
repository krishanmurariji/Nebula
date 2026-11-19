import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_log.dart';
import 'connection_provider.dart';
import 'search_provider.dart';

/// The searches typed on this phone, newest first. Kept only on the phone.
class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier({bool autoLoad = true}) : super(const []) {
    loaded = autoLoad ? _load() : Future.value();
  }

  static const key = 'nebula_search_history';
  static const max = 30;

  late final Future<void> loaded;
  bool _changed = false;

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null || _changed) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      state = [
        for (final e in list)
          if (e is String && e.trim().isNotEmpty) e
      ].take(max).toList();
    } catch (e) {
      nlog('[N] search history could not be read: $e'); // start empty
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode(state));
    } catch (e) {
      nlog('[N] search history could not be saved: $e');
    }
  }

  /// Puts [query] at the top (once, whatever its letter case).
  Future<void> add(String query) async {
    final q = sanitizeQuery(query);
    if (q.isEmpty) return;
    await loaded;
    _changed = true;
    final low = q.toLowerCase();
    state =
        [q, ...state.where((s) => s.toLowerCase() != low)].take(max).toList();
    await _save();
  }

  Future<void> remove(String query) async {
    await loaded;
    _changed = true;
    state = state.where((s) => s != query).toList();
    await _save();
  }

  Future<void> clear() async {
    await loaded;
    _changed = true;
    state = const [];
    await _save();
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>(
        (ref) => SearchHistoryNotifier());

/// Where YouTube's suggestions come from. A seam so tests never go online.
final suggestionFetcherProvider =
    Provider<Future<List<String>> Function(String query)>(
        (ref) => ref.read(searchServiceProvider).suggestions);

/// YouTube's suggestions for what is typed, as YouTube shows them. Waits a
/// moment first, so fast typing asks once rather than at every letter;
/// offline, or when YouTube does not answer, there are simply none.
final youtubeSuggestionsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, typed) async {
  final q = sanitizeQuery(typed);
  if (q.isEmpty) return const [];
  if (ref.watch(connectionProvider) == Connection.offline) return const [];
  var gone = false;
  ref.onDispose(() => gone = true);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (gone) return const [];
  try {
    final list = await ref
        .read(suggestionFetcherProvider)(q)
        .timeout(const Duration(seconds: 4));
    // Keep the answer for a minute: typing back to it shows it at once.
    final link = ref.keepAlive();
    final timer = Timer(const Duration(minutes: 1), link.close);
    ref.onDispose(timer.cancel);
    return list;
  } catch (e) {
    nlog('[N] suggestions skipped: $e');
    return const [];
  }
});

/// One line of the suggestions list.
class SearchSuggestion {
  const SearchSuggestion(this.text, {required this.recent});
  final String text;

  /// From this phone's own searches (can be removed) rather than YouTube.
  final bool recent;
}

/// What the list shows for [typed]: with nothing typed, the recent searches;
/// otherwise up to three recent searches that match, then YouTube's
/// suggestions (without repeating them).
List<SearchSuggestion> mergeSuggestions(
    String typed, List<String> recent, List<String> youtube) {
  final q = typed.trim().toLowerCase();
  if (q.isEmpty) {
    return [for (final r in recent.take(12)) SearchSuggestion(r, recent: true)];
  }
  final mine = recent
      .where((r) => r.toLowerCase().contains(q) && r.toLowerCase() != q)
      .take(3)
      .toList();
  final seen = {for (final r in mine) r.toLowerCase()};
  return [
    for (final r in mine) SearchSuggestion(r, recent: true),
    for (final y in youtube)
      if (y.trim().isNotEmpty && seen.add(y.trim().toLowerCase()))
        SearchSuggestion(y.trim(), recent: false),
  ].take(12).toList();
}
