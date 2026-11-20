import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noor/models/song.dart';
import 'package:noor/services/voice_requests.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song s(String id, String t, [String a = 'A']) =>
    Song(videoId: id.padRight(11, 'x'), title: t, artist: a, thumbnailUrl: '');

final kesariya = s('kes', 'Kesariya', 'Arijit Singh');
final tumHiHo = s('tum', 'Tum Hi Ho', 'Arijit Singh');
final lofi = s('lofi', 'Monsoon Lofi', 'Anuv');
final road1 = s('road1', 'Highway Song');
final road2 = s('road2', 'Long Drive');
final fromYoutube = s('ytbest', 'Channa Mereya (Official)');

String enc(List<Song> l) => jsonEncode(l.map((x) => x.toMap()).toList());

void main() {
  late List<String> searched;

  VoiceRequestResolver resolver({Map<String, Object> prefs = const {}}) {
    SharedPreferences.setMockInitialValues({
      'nebula_history': enc([tumHiHo, kesariya, lofi]),
      'nebula_liked': enc([lofi, kesariya]),
      'nebula_playlists': jsonEncode([
        {
          'id': 'p1',
          'name': 'Road Trip',
          'songs': [road1.toMap(), road2.toMap()]
        }
      ]),
      'noor_last_played': jsonEncode(kesariya.toMap()),
      ...prefs,
    });
    searched = [];
    return VoiceRequestResolver(searchYoutube: (q) async {
      searched.add(q);
      return [fromYoutube];
    });
  }

  group('what was said', () {
    test('filler is dropped, shuffle is noticed', () {
      expect(
          VoiceRequestResolver.clean('Play Kesariya on Noor').text, 'kesariya');
      expect(
          VoiceRequestResolver.clean('please play some music').text, 'music');
      final c = VoiceRequestResolver.clean('Shuffle my favorites on Noor');
      expect(c.text, 'my favorites');
      expect(c.shuffle, isTrue);
      expect(VoiceRequestResolver.clean('Play my history').shuffle, isFalse);
    });
  });

  group('resolving', () {
    test('nothing in particular: carry on with the last song, in My History',
        () async {
      final r = (await resolver().resolve(''))!;
      expect(r.first.title, 'Kesariya');
      expect(r.queue.map((x) => x.title),
          ['Tum Hi Ho', 'Kesariya', 'Monsoon Lofi']);
      expect((await resolver().resolve('play music on Noor'))!.first.title,
          'Kesariya');
    });

    test('my favorites / liked songs', () async {
      for (final q in [
        'my favorites',
        'my favourites',
        'liked songs',
        'Play my favorites on Noor'
      ]) {
        final r = (await resolver().resolve(q))!;
        expect(r.label, 'My Favorites', reason: q);
        expect(r.queue.map((x) => x.title), ['Monsoon Lofi', 'Kesariya']);
      }
    });

    test('my history', () async {
      expect(
          (await resolver().resolve('play my history'))!.label, 'My History');
      expect(
          (await resolver().resolve('recently played'))!.label, 'My History');
    });

    test('a playlist by name, with or without the word playlist', () async {
      for (final q in [
        'road trip',
        'my road trip playlist',
        'Shuffle Road Trip playlist on Noor'
      ]) {
        final r = (await resolver().resolve(q))!;
        expect(r.label, 'Road Trip', reason: q);
        expect(r.queue.map((x) => x.title), ['Highway Song', 'Long Drive']);
      }
      expect((await resolver().resolve('shuffle road trip'))!.shuffle, isTrue);
    });

    test(
        'a song already in the library is played from there, without searching',
        () async {
      final r = (await resolver().resolve('Play Kesariya on Noor'))!;
      expect(r.first.title, 'Kesariya');
      expect(searched, isEmpty);
      expect((await resolver().resolve('tum hi ho arijit'))!.first.title,
          'Tum Hi Ho');
    });

    test('anything else: YouTube\'s best match, then the history', () async {
      final r = (await resolver().resolve('Play Channa Mereya on Noor'))!;
      expect(searched, ['channa mereya']);
      expect(r.first.title, 'Channa Mereya (Official)');
      expect(r.queue.skip(1).map((x) => x.title),
          ['Tum Hi Ho', 'Kesariya', 'Monsoon Lofi']);
    });

    test('nothing found, or a search that fails: no request', () async {
      SharedPreferences.setMockInitialValues({});
      final none = VoiceRequestResolver(searchYoutube: (_) async => const []);
      expect(await none.resolve('zzz unknown'), isNull);
      final broken = VoiceRequestResolver(
          searchYoutube: (_) async => throw Exception('offline'));
      expect(await broken.resolve('zzz unknown'), isNull);
      expect(await broken.resolve(''),
          isNull); // a new install: nothing to carry on
    });

    test('a corrupt library never breaks a request', () async {
      final r = resolver(prefs: {
        'nebula_liked': '{bad',
        'nebula_playlists': '[1,2',
        'noor_last_played': 'x'
      });
      expect(
          (await r.resolve('my favorites')), isNull); // nothing readable there
      expect((await r.resolve(''))!.label, 'My History');
    });
  });
}
