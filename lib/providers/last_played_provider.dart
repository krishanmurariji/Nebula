import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

const _kLastPlayed = 'noor_last_played';

/// The last song that was played, remembered across launches so the bottom
/// card can show it (paused) when the app opens again.
class LastPlayedNotifier extends StateNotifier<Song?> {
  LastPlayedNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kLastPlayed);
      if (raw == null || !mounted) return;
      final m = json.decode(raw);
      if (m is Map) {
        final s = Song.fromMap(m);
        if (s.videoId.isNotEmpty && state == null) state = s;
      }
    } catch (_) {/* nothing remembered */}
  }

  Future<void> set(Song song) async {
    if (state?.videoId == song.videoId) return;
    state = song;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLastPlayed, json.encode(song.toMap()));
    } catch (_) {}
  }
}

final lastPlayedProvider =
    StateNotifierProvider<LastPlayedNotifier, Song?>((ref) => LastPlayedNotifier());
