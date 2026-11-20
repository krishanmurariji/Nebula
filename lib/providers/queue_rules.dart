import '../models/song.dart';
import 'library_provider.dart';

/// The list a song "belongs to" when the user swipes to the previous or next
/// song, in priority order:
///  1. the playlist that contains it (a song lives in at most one playlist);
///  2. My Favorites (liked songs);
///  3. My History (recently played);
///  4. otherwise just the song itself (it repeats).
List<Song> contextListFor(
  Song song, {
  required List<Playlist> playlists,
  required List<Song> liked,
  required List<Song> history,
}) {
  bool has(List<Song> l) => l.any((s) => s.videoId == song.videoId);
  for (final p in playlists) {
    if (has(p.songs)) return p.songs;
  }
  if (has(liked)) return liked;
  final seen = <String>{};
  final distinct = history.where((s) => seen.add(s.videoId)).toList();
  if (has(distinct)) return distinct;
  return [song];
}

/// The song before ([step] = -1) or after ([step] = 1) [song] in its context
/// list, wrapping around at the ends. With nothing else in the list the same
/// song is returned (it plays again).
Song neighbourOf(
  Song song,
  int step, {
  required List<Playlist> playlists,
  required List<Song> liked,
  required List<Song> history,
}) {
  final list = contextListFor(song,
      playlists: playlists, liked: liked, history: history);
  final i = list.indexWhere((s) => s.videoId == song.videoId);
  if (i < 0 || list.length < 2) return song;
  final n = list.length;
  return list[((i + step) % n + n) % n];
}

/// The name of the list [contextListFor] picks: the playlist's name,
/// "My Favorites", or "My History" (also when the song is alone).
String contextTitleFor(
  Song song, {
  required List<Playlist> playlists,
  required List<Song> liked,
  required List<Song> history,
}) {
  bool has(List<Song> l) => l.any((s) => s.videoId == song.videoId);
  for (final p in playlists) {
    if (has(p.songs)) return p.name;
  }
  if (has(liked)) return 'My Favorites';
  if (has(history)) return 'My History';
  return 'My History';
}

/// Which list [contextListFor] picks for [song], as a kind and (for a
/// playlist) its id, so Up next can rearrange that very list.
({String kind, String? playlistId}) contextSourceFor(
  Song song, {
  required List<Playlist> playlists,
  required List<Song> liked,
}) {
  bool has(List<Song> l) => l.any((s) => s.videoId == song.videoId);
  for (final p in playlists) {
    if (has(p.songs)) return (kind: 'playlist', playlistId: p.id);
  }
  if (has(liked)) return (kind: 'liked', playlistId: null);
  return (kind: 'history', playlistId: null);
}
