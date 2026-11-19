import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The gestures the user can switch off. Each one has another way to do the
/// same thing, so turning it off never locks anything away:
enum NoorGesture {
  /// Swipe the bottom card left / right for the next / previous song
  /// (also: the buttons in the player).
  bottomCardSwipe(
      'Swipe the bottom card', 'Left / right for the next or previous song'),

  /// Swipe the bottom card up to open the player (also: tap it).
  bottomCardSwipeUp('Swipe the bottom card up', 'Opens the player'),

  /// Swipe down (or pull the list down) on Home to open search (also: the
  /// search button).
  homeSwipeDownSearch('Swipe down on Home', 'Opens search'),

  /// Swipe the record left / right in the player (also: the next /
  /// previous buttons).
  playerRecordSwipe('Swipe the record', 'In the player: next or previous song'),

  /// Swipe a song card left for Like / Add to playlist / Delete (also: a
  /// long press on the card).
  songCardSwipe('Swipe a song left', 'Shows Like, Playlist and Delete');

  const NoorGesture(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// Which gestures are on (all of them unless switched off). Kept on the
/// phone.
class GestureSettingsNotifier extends StateNotifier<Set<NoorGesture>> {
  GestureSettingsNotifier({bool autoLoad = true})
      : super(NoorGesture.values.toSet()) {
    if (autoLoad) _load();
  }

  static const key = 'noor_gestures_off';

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null) return;
      final off = (jsonDecode(raw) as List).whereType<String>().toSet();
      state = {
        for (final g in NoorGesture.values)
          if (!off.contains(g.name)) g
      };
    } catch (_) {/* unreadable: keep everything on */}
  }

  Future<void> set(NoorGesture g, bool on) async {
    state = on ? {...state, g} : ({...state}..remove(g));
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          key,
          jsonEncode([
            for (final x in NoorGesture.values)
              if (!state.contains(x)) x.name
          ]));
    } catch (_) {}
  }
}

final gestureSettingsProvider =
    StateNotifierProvider<GestureSettingsNotifier, Set<NoorGesture>>(
        (ref) => GestureSettingsNotifier());

/// Whether gesture [g] is on.
final gestureOnProvider = Provider.family<bool, NoorGesture>(
    (ref, g) => ref.watch(gestureSettingsProvider).contains(g));
