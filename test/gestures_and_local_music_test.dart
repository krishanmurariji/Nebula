import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/models/song.dart';
import 'package:noor/providers/library_provider.dart';
import 'package:noor/providers/local_music_provider.dart';
import 'package:noor/providers/player_provider.dart';
import 'package:noor/screens/home_screen.dart';
import 'package:noor/screens/mini_player.dart';
import 'package:noor/screens/player_screen.dart';
import 'package:noor/screens/search_screen.dart';
import 'package:noor/widgets/song_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song s(String id, String t) =>
    Song(videoId: id.padRight(11, 'x'), title: t, artist: 'A', thumbnailUrl: '');

final songs = [s('a', 'Alpha'), s('b', 'Beta'), s('c', 'Gamma')];

class _Player extends StateNotifier<NebulaPlayerState> implements PlayerNotifier {
  _Player(super.s);
  final played = <String>[];
  @override
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    played.add(song.title);
    state = NebulaPlayerState(song: song, status: NebulaPlayerStatus.playing);
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<void> settle(WidgetTester t, [int frames = 15]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<_Player> openHome(WidgetTester t,
    {NebulaPlayerState player = const NebulaPlayerState(),
    Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ??
      {'nebula_history': jsonEncode(songs.map((x) => x.toMap()).toList())});
  t.view.physicalSize = const Size(411, 891);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final p = _Player(player);
  await t.pumpWidget(ProviderScope(
    overrides: [playerProvider.overrideWith((ref) => p)],
    child: const MaterialApp(home: HomeScreen()),
  ));
  await settle(t);
  return p;
}

void main() {
  group('Song: phone files', () {
    test('a phone song keeps its address through saving and loading', () {
      const song = Song(
          videoId: 'local_42',
          title: 'From phone',
          artist: 'Me',
          thumbnailUrl: 'localart://42',
          localUri: 'content://media/external/audio/media/42');
      final back = Song.fromMap(jsonDecode(jsonEncode(song.toMap())));
      expect(back.isLocal, isTrue);
      expect(back.localUri, song.localUri);
      expect(back.isPlayable, isTrue);
    });

    test('only media-library addresses are accepted', () {
      for (final bad in ['file:///etc/passwd', 'https://x.example/a.mp3', 42]) {
        final m = {'videoId': 'local_1', 'title': 't', 'artist': '', 'thumbnailUrl': '', 'localUri': bad};
        expect(Song.fromMap(m).isLocal, isFalse, reason: '$bad');
      }
      expect(s('yt', 'YouTube').isLocal, isFalse);
    });
  });

  group('My Music from the phone', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localMusicChannel, (call) async {
        if (call.method == 'list') {
          return [
            {'id': 7, 'title': 'Phone Song', 'artist': 'Me', 'durationMs': 200000,
              'uri': 'content://media/external/audio/media/7'},
            {'id': 'bad', 'title': 'Broken'}, // ignored
          ];
        }
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localMusicChannel, null));

    test('refresh reads the library into phone songs', () async {
      final n = LocalMusicNotifier(autoLoad: false);
      await n.refresh();
      expect(n.state.access, LocalAccess.granted);
      expect(n.state.songs.single.title, 'Phone Song');
      expect(n.state.songs.single.localUri, 'content://media/external/audio/media/7');
      expect(n.state.songs.single.thumbnailUrl, 'localart://7');
    });

    test('My Music lists only the phone songs, not songs Noor saved', () async {
      SharedPreferences.setMockInitialValues({});
      final n = LocalMusicNotifier(autoLoad: false);
      await n.refresh();
      final c = ProviderContainer(overrides: [
        localMusicProvider.overrideWith((ref) => n),
        isOnDeviceProvider.overrideWithValue((id) => id == songs[1].videoId),
      ]);
      addTearDown(c.dispose);
      await c.read(historyProvider.notifier).add(songs[1]);
      expect(c.read(myMusicProvider).map((x) => x.title), ['Phone Song']);
    });

    test('a library that cannot be read never throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(localMusicChannel,
              (call) async => throw PlatformException(code: 'query_failed'));
      final n = LocalMusicNotifier(autoLoad: false);
      await n.refresh();
      expect(n.state.songs, isEmpty);
    });
  });

  group('Home gestures', () {
    testWidgets('swipe down on the top of Home opens search', (t) async {
      await openHome(t);
      await t.fling(find.text('My History'), const Offset(0, 300), 1200);
      await settle(t, 6);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('swipe up on the top of Home no longer opens the player', (t) async {
      await openHome(t,
          player: NebulaPlayerState(song: songs[0], status: NebulaPlayerStatus.playing));
      await t.fling(find.text('My History'), const Offset(0, -300), 1200);
      await settle(t, 8);
      expect(find.byType(PlayerScreen), findsNothing);
    });

    testWidgets('swipe up does nothing when no song is playing', (t) async {
      await openHome(t);
      await t.fling(find.text('My History'), const Offset(0, -300), 1200);
      await settle(t, 8);
      expect(find.byType(PlayerScreen), findsNothing);
    });

    testWidgets('pulling the song list down past its top opens search', (t) async {
      await openHome(t);
      await t.drag(find.text('Beta').first, const Offset(0, 260));
      await settle(t, 6);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('My Music without access offers the permission button', (t) async {
      await openHome(t);
      await t.tap(find.byIcon(Icons.download_done_rounded));
      await settle(t, 20);
      expect(find.bySemanticsLabel('Allow access'), findsOneWidget);
    });
  });

  group('Bottom card', () {
    Future<_Player> withCard(WidgetTester t) => openHome(t,
        player: NebulaPlayerState(song: songs[0], status: NebulaPlayerStatus.playing));

    Finder card() => find.descendant(
        of: find.byType(MiniPlayer), matching: find.text('Alpha'));

    testWidgets('a short swipe springs back without changing song', (t) async {
      final p = await withCard(t);
      await t.drag(card(), const Offset(-40, 0));
      await settle(t, 8);
      expect(p.played, isEmpty);
      expect(t.getTopLeft(card()).dx, lessThan(200));
    });

    testWidgets('swiping left slides the card out and plays the next song', (t) async {
      final p = await withCard(t);
      await t.drag(card(), const Offset(-200, 0));
      await settle(t, 10);
      expect(p.played, ['Beta']);
      expect(t.takeException(), isNull);
    });

    testWidgets('swiping right plays the previous song', (t) async {
      final p = await withCard(t);
      await t.drag(card(), const Offset(200, 0));
      await settle(t, 10);
      expect(p.played, ['Gamma']); // wraps round from the first
    });

    testWidgets('while the card is dragged, the next song slides in beside it', (t) async {
      final p = await withCard(t);
      final g = await t.startGesture(t.getCenter(card()));
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(-12, 0), timeStamp: Duration(milliseconds: 60 * (i + 1)));
        await t.pump(const Duration(milliseconds: 16));
      }
      final next = find.descendant(of: find.byType(MiniPlayer), matching: find.text('Beta'));
      expect(next, findsOneWidget);
      expect(t.getTopLeft(next).dx, greaterThan(t.getTopLeft(card()).dx));
      expect(p.played, isEmpty);
      // Brought back: nothing changes and the next card goes away.
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(12, 0), timeStamp: Duration(milliseconds: 600 + 60 * i));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await settle(t, 8);
      expect(p.played, isEmpty);
      expect(next, findsNothing);
    });

    testWidgets('swipe up on the card opens the player', (t) async {
      await withCard(t);
      await t.fling(card(), const Offset(0, -200), 1200);
      await settle(t, 8);
      expect(find.byType(PlayerScreen), findsOneWidget);
    });
  });

  testWidgets('Search from the player comes back to the player', (t) async {
    await openHome(t,
        player: NebulaPlayerState(song: songs[0], status: NebulaPlayerStatus.playing));
    await t.tap(find.descendant(of: find.byType(MiniPlayer), matching: find.text('Alpha')));
    await settle(t, 8);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await t.tap(find.text('Search').last);
    await settle(t, 8);
    expect(find.byType(SearchPage), findsOneWidget);
    await t.binding.handlePopRoute();
    await settle(t, 8);
    expect(find.byType(SearchPage), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);
  });

  testWidgets('the playlist button is outlined, then filled once the song is in one', (t) async {
    SharedPreferences.setMockInitialValues({
      'nebula_playlists': jsonEncode([
        {'id': 'p1', 'name': 'Road', 'songs': []}
      ]),
    });
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
          home: Scaffold(body: ListView(children: [NoorSongRow(song: songs[0], onTap: () {})]))),
    ));
    await settle(t, 2);
    final container = ProviderScope.containerOf(t.element(find.byType(NoorSongRow)));
    await t.fling(find.text('Alpha'), const Offset(-260, 0), 1200);
    await settle(t);
    Color iconColor() => t.widget<Icon>(find.byIcon(Icons.playlist_add_rounded)).color!;
    final outlined = iconColor();
    await container.read(playlistProvider.notifier).addSong('p1', songs[0]);
    await t.pump();
    expect(iconColor(), isNot(outlined)); // icon flips to sit on the fill
  });
}
