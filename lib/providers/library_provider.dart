import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

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
  LikedNotifier() : super([]) { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kLiked);
    if (raw == null) return;
    state = (json.decode(raw) as List)
        .map((e) => Song.fromMap(e as Map<String, dynamic>)).toList();
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
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
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

  factory Playlist.fromMap(Map<String, dynamic> m) => Playlist(
    id: m['id'] as String? ?? '', name: m['name'] as String? ?? 'Untitled',
    songs: (m['songs'] as List? ?? [])
        .map((e) => Song.fromMap(e as Map<String, dynamic>)).toList(),
  );
}

final playlistProvider =
    StateNotifierProvider<PlaylistNotifier, List<Playlist>>(
        (ref) => PlaylistNotifier());

class PlaylistNotifier extends StateNotifier<List<Playlist>> {
  PlaylistNotifier() : super([]) { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kPlaylists);
    if (raw == null) return;
    state = (json.decode(raw) as List)
        .map((e) => Playlist.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPlaylists,
        json.encode(state.map((pl) => pl.toMap()).toList()));
  }

  Future<Playlist> create(String name) async {
    final pl = Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.trim().isEmpty ? 'New Playlist' : name.trim());
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
      final newSongs = [...p.songs];
      final item = newSongs.removeAt(oldIndex);
      newSongs.insert(newIndex, item);
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
  HistoryNotifier() : super([]) { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kHistory);
    if (raw == null) return;
    state = (json.decode(raw) as List)
        .map((e) => Song.fromMap(e as Map<String, dynamic>)).toList();
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
