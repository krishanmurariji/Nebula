import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/models/song.dart';
import 'package:nebula_music_player/providers/library_provider.dart';
import 'package:nebula_music_player/providers/queue_rules.dart';

Song s(String id) => Song(videoId: id.padRight(11, 'x'), title: id, artist: 'a', thumbnailUrl: '');

void main() {
  final a = s('a'), b = s('b'), c = s('c'), d = s('d');

  test('a song in a playlist moves within that playlist first', () {
    final pls = [Playlist(id: 'p', name: 'P', songs: [a, b, c])];
    expect(neighbourOf(b, 1, playlists: pls, liked: [d, b], history: []), c);
    expect(neighbourOf(b, -1, playlists: pls, liked: [d, b], history: []), a);
    expect(neighbourOf(c, 1, playlists: pls, liked: [], history: []), a); // wraps
  });

  test('otherwise liked songs, then history', () {
    expect(neighbourOf(b, 1, playlists: [], liked: [a, b, c], history: [d, b]), c);
    expect(neighbourOf(b, 1, playlists: [], liked: [], history: [d, b, b, a]), a);
  });

  test('nowhere else to go: the same song again', () {
    expect(neighbourOf(a, 1, playlists: [], liked: [], history: []), a);
    expect(neighbourOf(a, -1, playlists: [], liked: [a], history: [a]), a);
  });
}
