import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/models/song.dart';
import 'package:nebula_music_player/providers/library_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

Map<String, dynamic> song(String id) =>
    {'videoId': id, 'title': 'T $id', 'artist': 'A', 'thumbnailUrl': '', 'isOfficial': false};

void main() {
  group('Song.fromMap survives garbage', () {
    test('wrong types never throw', () {
      final s = Song.fromMap({
        'videoId': 12345,
        'title': null,
        'artist': ['x'],
        'thumbnailUrl': {'a': 1},
        'isOfficial': 'yes',
      });
      expect(s.videoId, '');
      expect(s.title, 'Unknown');
      expect(s.artist, '');
      expect(s.isOfficial, false);
    });

    test('empty map and non-string keys', () {
      expect(() => Song.fromMap({}), returnsNormally);
      expect(() => Song.fromMap({1: 'x', null: 2}), returnsNormally);
    });

    test('isPlayable rejects ids that are unsafe or malformed', () {
      Song s(String id) => Song(videoId: id, title: '', artist: '', thumbnailUrl: '');
      expect(s('dQw4w9WgXcQ').isPlayable, isTrue);
      for (final bad in ['', ' ', '../../etc/passwd', 'a/b', 'a\\b', 'x' * 65, 'abc', 'id with space', 'é€', 'a\nb']) {
        expect(s(bad).isPlayable, isFalse, reason: 'should reject "$bad"');
      }
    });
  });

  group('decodeList', () {
    test('invalid JSON → empty list and onCorrupt called', () {
      Object? err;
      final r = decodeList<Song>('{{ not json', Song.fromMap, onCorrupt: (e) => err = e);
      expect(r, isEmpty);
      expect(err, isNotNull);
    });

    test('JSON that is not a list → empty, reported', () {
      var corrupt = false;
      expect(decodeList<Song>('{"a":1}', Song.fromMap, onCorrupt: (_) => corrupt = true), isEmpty);
      expect(corrupt, isTrue);
    });

    test('one bad entry never costs the good ones', () {
      final raw = jsonEncode([song('aaaaaaaaaaa'), 42, 'str', null, {'videoId': 5}, song('bbbbbbbbbbb')]);
      final r = decodeList<Song>(raw, (m) {
        final s = Song.fromMap(m);
        return s.videoId.isEmpty ? null : s;
      });
      expect(r.map((s) => s.videoId), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    });

    test('null / empty input', () {
      expect(decodeList<Song>(null, Song.fromMap), isEmpty);
      expect(decodeList<Song>('', Song.fromMap), isEmpty);
    });
  });

  group('library persistence under corruption', () {
    test('corrupt liked list → empty, original kept as backup', () async {
      SharedPreferences.setMockInitialValues({'nebula_liked': '%%% broken'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(likedProvider), isEmpty);
      await settle();
      final p = await SharedPreferences.getInstance();
      expect(c.read(likedProvider), isEmpty);
      expect(p.getString('nebula_liked_corrupt_backup'), '%%% broken');
    });

    test('mixed good and bad liked entries load the good ones', () async {
      SharedPreferences.setMockInitialValues({
        'nebula_liked': jsonEncode([song('aaaaaaaaaaa'), 7, {'videoId': null}, song('ccccccccccc')]),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(likedProvider);
      await settle();
      expect(c.read(likedProvider).map((s) => s.videoId), ['aaaaaaaaaaa', 'ccccccccccc']);
    });

    test('corrupt playlists and history do not crash', () async {
      SharedPreferences.setMockInitialValues({
        'nebula_playlists': '[[[',
        'nebula_history': '"just a string"',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(playlistProvider);
      c.read(historyProvider);
      await settle();
      expect(c.read(playlistProvider), isEmpty);
      expect(c.read(historyProvider), isEmpty);
    });

    test('playlist with garbage songs keeps the valid ones', () {
      final pl = Playlist.fromMap({
        'id': 'p1',
        'name': 99,
        'songs': [song('aaaaaaaaaaa'), 'x', null, {'videoId': ''}],
      });
      expect(pl.id, 'p1');
      expect(pl.name, 'Untitled');
      expect(pl.songs.length, 1);
      expect(Playlist.fromMap({'songs': 'nope'}).songs, isEmpty);
    });

    test('reorder with invalid indices is ignored, never throws', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final liked = c.read(likedProvider.notifier);
      await liked.toggle(Song.fromMap(song('aaaaaaaaaaa')));
      await liked.toggle(Song.fromMap(song('bbbbbbbbbbb')));
      await liked.reorder(-1, 0);
      await liked.reorder(99, 0);
      await liked.reorder(0, 99); // clamped
      expect(c.read(likedProvider).length, 2);

      final pls = c.read(playlistProvider.notifier);
      final pl = await pls.create('x');
      await pls.addSong(pl.id, Song.fromMap(song('aaaaaaaaaaa')));
      await pls.reorderSong(pl.id, 5, 0);
      await pls.reorderSong('missing', 0, 0);
      expect(c.read(playlistProvider).single.songs.length, 1);
    });

    test('playlist names are capped, ids are unique even when created back to back', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(playlistProvider.notifier);
      final a = await n.create('x' * 5000);
      final b = await n.create('   ');
      final d = await n.create('ok');
      expect(a.name.length, 60);
      expect(b.name, 'New Playlist');
      expect({a.id, b.id, d.id}.length, 3);
    });

    test('toggling the same song rapidly leaves a consistent list', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(likedProvider.notifier);
      final s = Song.fromMap(song('aaaaaaaaaaa'));
      await Future.wait([for (var i = 0; i < 51; i++) n.toggle(s)]);
      expect(c.read(likedProvider).length, 1); // odd number of toggles → liked
      final p = await SharedPreferences.getInstance();
      expect((jsonDecode(p.getString('nebula_liked')!) as List).length, 1);
    });

    test('history is capped at 30 and de-duplicated', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final h = c.read(historyProvider.notifier);
      for (var i = 0; i < 80; i++) {
        await h.add(Song.fromMap(song('vid${i.toString().padLeft(8, '0')}')));
      }
      await h.add(Song.fromMap(song('vid00000079')));
      expect(c.read(historyProvider).length, 30);
      expect(c.read(historyProvider).first.videoId, 'vid00000079');
    });
  });
}
