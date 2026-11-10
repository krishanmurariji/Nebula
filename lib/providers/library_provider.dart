import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

/// Decodes a saved JSON list defensively: a corrupt file yields an empty list
/// (and is reported via [onCorrupt] so it can be backed up), and one bad entry
/// never costs the good ones.
List<T> decodeList<T>(
  String? raw,
  T? Function(Map<dynamic, dynamic>) parse, {
  void Function(Object error)? onCorrupt,
}) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = json.decode(raw);
    if (decoded is! List) throw const FormatException('expected a list');
    final out = <T>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      try {
        final v = parse(e);
        if (v != null) out.add(v);
      } catch (_) {/* skip just this entry */}
    }
    return out;
  } catch (e) {
    onCorrupt?.call(e);
    return [];
  }
}

Song? _parseSong(Map<dynamic, dynamic> m) {
  final s = Song.fromMap(m);
  return s.videoId.isEmpty ? null : s;
}

/// Keeps a copy of unreadable data instead of silently overwriting it.
Future<void> _backupCorrupt(SharedPreferences p, String key, String? raw) async {
  if (raw == null) return;
  await p.setString('${key}_corrupt_backup', raw);
}

const _kLiked     = 'nebula_liked';
const _kPlaylists = 'nebula_playlists';
const _kHistory   = 'nebula_history';

// ── Liked ──────────────────────────────────────────────────────────────────
final likedProvider =
    StateNotifierProvider<LikedNotifier, List<Song>>((ref) => LikedNotifier());

// Alias so both likedProvider and likedSongsProvider work
final likedSongsProvider = likedProvider;

final isLikedProvider = Provider.family<bool, String>(
    (ref, id) => ref.watch(likedProvider).any((s) => s.videoId == id));

class LikedNotifier extends StateNotifier<List<Song>> {
  LikedNotifier() : super([]) {
    loaded = _load();
  }

  /// Completes when the saved list has been read from the device.
  late final Future<void> loaded;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kLiked);
    final loaded = decodeList<Song>(raw, _parseSong,
        onCorrupt: (_) => _backupCorrupt(p, _kLiked, raw));
    if (!mounted) return;
    // Merge: keep anything the user liked while this was still loading.
    state = [...state, ...loaded.where((s) => !state.contains(s))];
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLiked, json.encode(state.map((s) => s.toMap()).toList()));
  }

  Future<void> toggle(Song song) async {
    state = state.any((s) => s.videoId == song.videoId)
        ? state.where((s) => s.videoId != song.videoId).toList()
        : [song, ...state];
    await _save();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    state = list;
    await _save();
  }
}

// ── Playlists ──────────────────────────────────────────────────────────────
class Playlist {
  final String id, name;
  final List<Song> songs;
  const Playlist({required this.id, required this.name, this.songs = const []});

  Playlist copyWith({String? name, List<Song>? songs}) =>
      Playlist(id: id, name: name ?? this.name, songs: songs ?? this.songs);

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'songs': songs.map((s) => s.toMap()).toList(),
  };

  factory Playlist.fromMap(Map<dynamic, dynamic> m) => Playlist(
    id: m['id'] is String ? m['id'] as String : '',
    name: m['name'] is String ? m['name'] as String : 'Untitled',
    songs: m['songs'] is List
        ? (m['songs'] as List)
            .whereType<Map>()
            .map(Song.fromMap)
            .where((s) => s.videoId.isNotEmpty)
            .toList()
        : const [],
  );
}

final playlistProvider =
    StateNotifierProvider<PlaylistNotifier, List<Playlist>>(
        (ref) => PlaylistNotifier());

class PlaylistNotifier extends StateNotifier<List<Playlist>> {
  PlaylistNotifier() : super([]) {
    loaded = _load();
  }

  late final Future<void> loaded;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kPlaylists);
    final loaded = decodeList<Playlist>(
        raw, (m) => Playlist.fromMap(m).id.isEmpty ? null : Playlist.fromMap(m),
        onCorrupt: (_) => _backupCorrupt(p, _kPlaylists, raw));
    if (!mounted) return;
    state = [...state, ...loaded.where((l) => !state.any((s) => s.id == l.id))];
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPlaylists,
        json.encode(state.map((pl) => pl.toMap()).toList()));
  }

  Future<Playlist> create(String name) async {
    final pl = Playlist(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim().isEmpty
            ? 'New Playlist'
            : (name.trim().length > 60 ? name.trim().substring(0, 60) : name.trim()));
    state = [...state, pl];
    await _save();
    return pl;
  }

  Future<void> delete(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _save();
  }

  Future<void> addSong(String playlistId, Song song) async {
    state = state.map((p) {
      if (p.id != playlistId) return p;
      if (p.songs.any((s) => s.videoId == song.videoId)) return p;
      return p.copyWith(songs: [...p.songs, song]);
    }).toList();
    await _save();
  }

  Future<void> removeSong(String playlistId, String videoId) async {
    state = state.map((p) {
      if (p.id != playlistId) return p;
      return p.copyWith(
          songs: p.songs.where((s) => s.videoId != videoId).toList());
    }).toList();
    await _save();
  }

  Future<void> reorderSong(String playlistId, int oldIndex, int newIndex) async {
    state = state.map((p) {
      if (p.id != playlistId) return p;
      if (oldIndex < 0 || oldIndex >= p.songs.length) return p;
      final newSongs = [...p.songs];
      final item = newSongs.removeAt(oldIndex);
      newSongs.insert(newIndex.clamp(0, newSongs.length), item);
      return p.copyWith(songs: newSongs);
    }).toList();
    await _save();
  }

  bool contains(String playlistId, String videoId) =>
      state.where((p) => p.id == playlistId)
           .any((p) => p.songs.any((s) => s.videoId == videoId));
}

// ── History ────────────────────────────────────────────────────────────────
final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<Song>>((ref) => HistoryNotifier());

class HistoryNotifier extends StateNotifier<List<Song>> {
  HistoryNotifier() : super([]) {
    loaded = _load();
  }

  late final Future<void> loaded;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kHistory);
    final loaded = decodeList<Song>(raw, _parseSong,
        onCorrupt: (_) => _backupCorrupt(p, _kHistory, raw));
    if (!mounted) return;
    state = [...state, ...loaded.where((s) => !state.contains(s))].take(30).toList();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kHistory, json.encode(state.map((s) => s.toMap()).toList()));
  }

  Future<void> add(Song song) async {
    state = [song, ...state.where((s) => s.videoId != song.videoId)].take(30).toList();
    await _save();
  }

  Future<void> clear() async {
    state = [];
    final p = await SharedPreferences.getInstance();
    await p.remove(_kHistory);
  }
}


/// True once liked songs, playlists and history have been read from the
/// device. Until then Home must not claim "nothing here yet".
final libraryReadyProvider = FutureProvider<bool>((ref) async {
  await Future.wait([
    ref.read(likedProvider.notifier).loaded,
    ref.read(playlistProvider.notifier).loaded,
    ref.read(historyProvider.notifier).loaded,
  ]);
  return true;
});
