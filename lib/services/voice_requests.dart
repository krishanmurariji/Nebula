import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'app_log.dart';

/// What a voice request asked for: the songs to play, which one first, and
/// whether to shuffle. [label] says it in words ("My Favorites", the song).
class VoiceRequest {
  const VoiceRequest(this.queue, {this.start = 0, this.shuffle = false, required this.label});
  final List<Song> queue;
  final int start;
  final bool shuffle;
  final String label;

  Song get first => queue[start];
}

/// Turns what a voice assistant (or a shortcut, or "play when Noor opens")
/// asks for into songs, from the library saved on the phone, so it also
/// works when Noor is not on screen:
///
///  * nothing / "music" / "something": carry on with the last song played;
///  * "my favorites" / "liked songs": My Favorites;
///  * "my history" / "recent": My History;
///  * "my music" / "songs on my phone": the phone's own music;
///  * a playlist's name (with or without "playlist"): that playlist;
///  * anything else: the best match in the library, else YouTube's best.
///
/// "shuffle" anywhere shuffles. "play", "please", "on Noor" are ignored.
class VoiceRequestResolver {
  VoiceRequestResolver({
    Future<SharedPreferences> Function()? prefs,
    required this.searchYoutube,
    this.phoneSongs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  /// YouTube's results for a query, best first.
  final Future<List<Song>> Function(String query) searchYoutube;

  /// The phone's own music, when it can be read here.
  final Future<List<Song>> Function()? phoneSongs;

  /// The request reduced to its words: lower case, no filler.
  static ({String text, bool shuffle}) clean(String raw) {
    var q = ' ${raw.toLowerCase().replaceAll(RegExp(r"[^\w\s']"), ' ')} ';
    final shuffle = q.contains(' shuffle ') || q.contains(' shuffled ') || q.contains(' random ');
    for (final w in [
      ' on noor ', ' in noor ', ' from noor ', ' using noor ', ' with noor ',
      ' noor ', ' please ', ' play ', ' shuffle ', ' shuffled ', ' random ',
      ' some ', ' the ', ' me ', ' a ', ' song ', ' songs ', ' track ', ' tracks ',
    ]) {
      while (q.contains(w)) {
        q = q.replaceAll(w, ' ');
      }
    }
    return (text: q.trim().replaceAll(RegExp(r'\s+'), ' '), shuffle: shuffle);
  }

  Future<VoiceRequest?> resolve(String raw) async {
    final c = clean(raw);
    final q = c.text;
    final p = await _prefs();
    final liked = _songs(p, 'nebula_liked');
    final history = _distinct(_songs(p, 'nebula_history'));
    final playlists = _playlists(p);
    final last = _lastPlayed(p);

    VoiceRequest? of(List<Song> list, String label, {int start = 0}) =>
        list.isEmpty
            ? null
            : VoiceRequest(list, start: start, shuffle: c.shuffle, label: label);

    // Nothing in particular: carry on where the user left off.
    if (q.isEmpty || const {'music', 'something', 'anything', 'my', 'my music app'}.contains(q)) {
      if (last != null) {
        final inHistory = history.indexWhere((s) => s.videoId == last.videoId);
        return inHistory >= 0
            ? of(history, last.title, start: inHistory)
            : VoiceRequest([last, ...history], label: last.title, shuffle: c.shuffle);
      }
      return of(history, 'My History') ?? of(liked, 'My Favorites');
    }

    if (RegExp(r'\b(favou?rites?|liked|likes|loved)\b').hasMatch(q)) {
      return of(liked, 'My Favorites');
    }
    if (RegExp(r'\b(history|recent|recently|last played)\b').hasMatch(q)) {
      return of(history, 'My History');
    }
    if (RegExp(r'^(my music|my own music|on my phone|my phone|downloaded|downloads|local|offline)$')
        .hasMatch(q)) {
      try {
        final phone = await phoneSongs?.call() ?? const <Song>[];
        if (phone.isNotEmpty) return of(phone, 'My Music');
      } catch (e) {
        nlog('[N] voice: phone music not readable here: $e');
      }
    }

    // A playlist by name.
    final name = q.replaceAll(RegExp(r'\b(my|playlist|list)\b'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isNotEmpty) {
      for (final pl in playlists) {
        final n = pl.name.toLowerCase().trim();
        if (n == name || (q.contains('playlist') && (n.contains(name) || name.contains(n)))) {
          return of(pl.songs, pl.name);
        }
      }
    }

    // A song already in the library: every word in its title or artist.
    final words = q.split(' ').where((w) => w.length > 1).toList();
    final library = _distinct([...history, ...liked, for (final pl in playlists) ...pl.songs]);
    for (final s in library) {
      final hay = '${s.title} ${s.artist}'.toLowerCase();
      if (words.isNotEmpty && words.every(hay.contains)) {
        return VoiceRequest([s, ...history.where((h) => h.videoId != s.videoId)],
            label: s.title, shuffle: c.shuffle);
      }
    }

    // Otherwise YouTube's best match, then what was played recently.
    try {
      final found = await searchYoutube(q);
      if (found.isEmpty) return null;
      final s = found.first;
      return VoiceRequest([s, ...history.where((h) => h.videoId != s.videoId)],
          label: s.title, shuffle: c.shuffle);
    } catch (e) {
      nlog('[N] voice: search for "$q" failed: $e');
      return null;
    }
  }

  static List<Song> _songs(SharedPreferences p, String key) {
    try {
      final raw = p.getString(key);
      if (raw == null) return const [];
      return [
        for (final m in jsonDecode(raw) as List)
          if (m is Map) Song.fromMap(m)
      ].where((s) => s.isPlayable).toList();
    } catch (_) {
      return const [];
    }
  }

  static List<({String name, List<Song> songs})> _playlists(SharedPreferences p) {
    try {
      final raw = p.getString('nebula_playlists');
      if (raw == null) return const [];
      return [
        for (final m in jsonDecode(raw) as List)
          if (m is Map && m['name'] is String)
            (
              name: m['name'] as String,
              songs: [
                for (final s in (m['songs'] as List? ?? const []))
                  if (s is Map) Song.fromMap(s)
              ].where((s) => s.isPlayable).toList(),
            )
      ];
    } catch (_) {
      return const [];
    }
  }

  static Song? _lastPlayed(SharedPreferences p) {
    try {
      final raw = p.getString('noor_last_played');
      if (raw == null) return null;
      final s = Song.fromMap(jsonDecode(raw) as Map);
      return s.isPlayable ? s : null;
    } catch (_) {
      return null;
    }
  }

  static List<Song> _distinct(List<Song> l) {
    final seen = <String>{};
    return l.where((s) => seen.add(s.videoId)).toList();
  }
}
