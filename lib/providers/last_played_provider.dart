import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

const _kLastPlayed = 'noor_last_played';

/// The last song that was played, remembered across launches so the bottom
/// card can show it (paused) when the app opens again.
class LastPlayedNotifier extends StateNotifier<Song?> {
  LastPlayedNotifier() : super(null) {
    loaded = _load();
  }

  /// Completes once the remembered song has been read from storage.
  late final Future<void> loaded;

  /// Set once [set] or [clear] has run: the value read from storage is then
  /// older than what the user just did and must not replace it.
  bool _changed = false;

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kLastPlayed);
      if (raw == null || !mounted) return;
      final m = json.decode(raw);
      if (m is Map) {
        final s = Song.fromMap(m);
        if (s.videoId.isNotEmpty && state == null && !_changed) state = s;
      }
    } catch (_) {/* nothing remembered */}
  }

  /// Forgets the remembered song (it was deleted).
  Future<void> clear() async {
    _changed = true;
    state = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kLastPlayed);
    } catch (_) {}
  }

  Future<void> set(Song song) async {
    if (state?.videoId == song.videoId) return;
    _changed = true;
    state = song;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLastPlayed, json.encode(song.toMap()));
    } catch (_) {}
  }
}

final lastPlayedProvider = StateNotifierProvider<LastPlayedNotifier, Song?>(
    (ref) => LastPlayedNotifier());
