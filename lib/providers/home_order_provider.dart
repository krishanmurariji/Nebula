import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The order of the Home slider's cards, by id ('hist', 'fav', 'music',
/// then playlist ids), as the user arranged it. Empty until they do.
class HomeOrderNotifier extends StateNotifier<List<String>> {
  HomeOrderNotifier({bool autoLoad = true}) : super(const []) {
    if (autoLoad) _load();
  }

  static const key = 'noor_home_order';
  bool _changed = false;

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null || _changed) return;
      state = (jsonDecode(raw) as List).whereType<String>().toList();
    } catch (_) {/* unreadable: the default order */}
  }

  Future<void> set(List<String> order) async {
    _changed = true;
    state = List.unmodifiable(order);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode(order));
    } catch (_) {}
  }
}

final homeOrderProvider =
    StateNotifierProvider<HomeOrderNotifier, List<String>>(
        (ref) => HomeOrderNotifier());

/// [ids] in the saved [order]: the ones the user placed first, in their
/// order, then any others (a new playlist) in their default order.
List<T> applyHomeOrder<T>(
    List<T> items, String Function(T) id, List<String> order) {
  if (order.isEmpty) return items;
  final pos = {for (var i = 0; i < order.length; i++) order[i]: i};
  final placed = items.where((x) => pos.containsKey(id(x))).toList()
    ..sort((a, b) => pos[id(a)]!.compareTo(pos[id(b)]!));
  return [...placed, ...items.where((x) => !pos.containsKey(id(x)))];
}
