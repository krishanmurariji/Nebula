import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/models/song.dart';
import 'package:noor/providers/last_played_provider.dart';
import 'package:noor/providers/library_provider.dart';
import 'package:noor/providers/player_provider.dart';
import 'package:noor/widgets/song_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song song(String id, String title) =>
    Song(videoId: id.padRight(11, 'x'), title: title, artist: 'A', thumbnailUrl: '');

final a = song('a', 'Alpha');

Map<String, Object> playlists(int n, {List<Song> songsInFirst = const []}) => {
      'nebula_playlists': jsonEncode([
        for (var i = 0; i < n; i++)
          {
            'id': 'p$i',
            'name': 'List $i',
            'songs': i == 0 ? songsInFirst.map((s) => s.toMap()).toList() : [],
          }
      ]),
    };

class _Player extends StateNotifier<NebulaPlayerState> implements PlayerNotifier {
  _Player([NebulaPlayerState s = const NebulaPlayerState()]) : super(s);
  int cleared = 0;
  @override
  Future<void> stopAndClear() async {
    cleared++;
    state = const NebulaPlayerState();
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<ProviderContainer> open(WidgetTester t, Map<String, Object> prefs,
    {Widget Function(Widget row)? wrap, _Player? player}) async {
  SharedPreferences.setMockInitialValues(prefs);
  t.view.physicalSize = const Size(411, 891);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final row = NoorSongRow(song: a, onTap: () {});
  await t.pumpWidget(ProviderScope(
    overrides: [playerProvider.overrideWith((ref) => player ?? _Player())],
    child: MaterialApp(
      home: Scaffold(
        body: wrap != null
            ? wrap(row)
            : ListView(padding: const EdgeInsets.only(top: 400), children: [row]),
      ),
    ),
  ));
  await t.pump(const Duration(milliseconds: 100));
  return ProviderScope.containerOf(t.element(find.byType(NoorSongRow)));
}

Future<void> settle(WidgetTester t, [int frames = 15]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> swipeOpen(WidgetTester t) async {
  await t.fling(find.text('Alpha'), const Offset(-260, 0), 1200);
  await settle(t);
}

void main() {
  testWidgets('swipe left shrinks the card and shows like, add to playlist and delete', (t) async {
    await open(t, {});
    expect(find.bySemanticsLabel('Like'), findsNothing);
    await swipeOpen(t);
    expect(find.bySemanticsLabel('Like'), findsOneWidget);
    expect(find.bySemanticsLabel('Add to playlist'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove from history'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a short drag snaps back; swipe right puts the card back', (t) async {
    await open(t, {});
    await t.drag(find.text('Alpha'), const Offset(-60, 0));
    await settle(t);
    expect(find.bySemanticsLabel('Like'), findsNothing);
    await swipeOpen(t);
    await t.fling(find.text('Alpha'), const Offset(220, 0), 1200);
    await settle(t);
    expect(find.bySemanticsLabel('Like'), findsNothing);
  });

  testWidgets('tapping the shrunk card puts it back instead of playing', (t) async {
    var plays = 0;
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [playerProvider.overrideWith((ref) => _Player())],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(children: [NoorSongRow(song: a, onTap: () => plays++)]),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    await swipeOpen(t);
    // The shrunk card keeps its record and title; the actions sit to its right.
    expect(find.text('Alpha'), findsOneWidget);
    expect(t.getRect(find.bySemanticsLabel('Like')).left,
        greaterThan(t.getRect(find.text('Alpha')).left));
    await t.tap(find.text('Alpha'));
    await settle(t);
    expect(plays, 0);
    expect(find.bySemanticsLabel('Like'), findsNothing);
  });

  testWidgets('6 or more playlists fan out in a full circle', (t) async {
    await open(t, playlists(8));
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await settle(t, 14);
    final centre = t.getCenter(find.bySemanticsLabel('Make a new playlist'));
    final below = [
      for (var i = 0; i < 8; i++)
        t.getCenter(find.bySemanticsLabel('Add to List $i')).dy > centre.dy + 10
    ].where((b) => b).length;
    expect(below, greaterThanOrEqualTo(3)); // bubbles all the way round
    expect(t.takeException(), isNull);
  });

  testWidgets('a right swipe is left to whatever is behind the list', (t) async {
    var parentDrags = 0;
    await open(t, {},
        wrap: (row) => GestureDetector(
              onHorizontalDragEnd: (_) => parentDrags++,
              child: ListView(children: [row]),
            ));
    await t.fling(find.text('Alpha'), const Offset(260, 0), 1200);
    await settle(t);
    expect(parentDrags, 1);
    expect(find.bySemanticsLabel('Like'), findsNothing);
  });

  testWidgets('like fills and unfills, the actions stay open', (t) async {
    final c = await open(t, {});
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Like'));
    await settle(t, 3);
    expect(c.read(likedProvider).map((s) => s.title), ['Alpha']);
    expect(find.bySemanticsLabel('Unlike'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Unlike'));
    await settle(t, 3);
    expect(c.read(likedProvider), isEmpty);
  });

  testWidgets('delete removes the song from the history and closes', (t) async {
    final c = await open(t, {
      'nebula_history': jsonEncode([a.toMap(), song('b', 'Beta').toMap()]),
    });
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Remove from history'));
    await settle(t);
    expect(c.read(historyProvider).map((s) => s.title), ['Beta']);
    expect(find.bySemanticsLabel('Like'), findsNothing);
  });

  testWidgets('deleting the playing song stops it and clears the bottom card', (t) async {
    final p = _Player(NebulaPlayerState(song: a, status: NebulaPlayerStatus.playing));
    final c = await open(t, {
      'nebula_history': jsonEncode([a.toMap()]),
      'noor_last_played': jsonEncode(a.toMap()),
    }, player: p);
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Remove from history'));
    await settle(t);
    expect(p.cleared, 1);
    expect(c.read(playerProvider).displaySong, isNull);
    expect(c.read(lastPlayedProvider), isNull);
    expect(c.read(historyProvider), isEmpty);
  });

  testWidgets('deleting the song waiting in the bottom card after a restart clears it', (t) async {
    final p = _Player();
    final c = await open(t, {
      'nebula_history': jsonEncode([a.toMap()]),
      'noor_last_played': jsonEncode(a.toMap()),
    }, player: p);
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Remove from history'));
    await settle(t);
    expect(p.cleared, 0); // nothing was playing
    expect(c.read(lastPlayedProvider), isNull);
  });

  testWidgets('deleting another song leaves playback alone', (t) async {
    final other = song('z', 'Zeta');
    final p = _Player(NebulaPlayerState(song: other, status: NebulaPlayerStatus.playing));
    final c = await open(t, {
      'nebula_history': jsonEncode([a.toMap(), other.toMap()]),
      'noor_last_played': jsonEncode(other.toMap()),
    }, player: p);
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Remove from history'));
    await settle(t);
    expect(p.cleared, 0);
    expect(c.read(playerProvider).song?.title, 'Zeta');
    expect(c.read(lastPlayedProvider)?.title, 'Zeta');
  });

  testWidgets('delete is disabled for a song not in the history', (t) async {
    await open(t, {});
    await swipeOpen(t);
    final node = t.getSemantics(find.bySemanticsLabel('Remove from history'));
    expect(node.flagsCollection.isEnabled, isNot(true));
  });

  testWidgets('the menu fans out the playlists; picking one adds the song', (t) async {
    final c = await open(t, playlists(3));
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await settle(t, 8);
    expect(find.text('List 0'), findsOneWidget);
    expect(find.text('List 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Make a new playlist'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Add to List 1'));
    await settle(t, 30);
    expect(c.read(playlistProvider)[1].songs.map((s) => s.title), ['Alpha']);
    // Back in place after the thumbs-up.
    expect(find.bySemanticsLabel('Like'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('picking the playlist the song is in takes it out', (t) async {
    final c = await open(t, playlists(2, songsInFirst: [a]));
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await settle(t, 8);
    await t.tap(find.bySemanticsLabel('Remove from List 0'));
    await settle(t, 30);
    expect(c.read(playlistProvider)[0].songs, isEmpty);
  });

  testWidgets('tapping outside folds the menu back', (t) async {
    await open(t, playlists(2));
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await settle(t, 8);
    await t.tapAt(const Offset(20, 860));
    await settle(t, 8);
    expect(find.text('List 0'), findsNothing);
    expect(find.bySemanticsLabel('Like'), findsOneWidget); // still open
  });

  testWidgets('new playlist: name it, check, it is created with the song', (t) async {
    final c = await open(t, playlists(1));
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await settle(t, 8);
    await t.tap(find.bySemanticsLabel('Make a new playlist'));
    await settle(t, 8);
    expect(find.text('Enter name'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Road Trip');
    await t.tap(find.bySemanticsLabel('Create playlist'));
    await settle(t, 3);
    expect(find.byIcon(Icons.thumb_up_alt_rounded), findsOneWidget);
    await settle(t, 20);
    final pls = c.read(playlistProvider);
    expect(pls.map((p) => p.name), ['List 0', 'Road Trip']);
    expect(pls[1].songs.map((s) => s.title), ['Alpha']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('an empty or duplicate name is refused in place', (t) async {
    final c = await open(t, playlists(1));
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await settle(t, 8);
    await t.tap(find.bySemanticsLabel('Make a new playlist'));
    await settle(t, 8);
    await t.tap(find.bySemanticsLabel('Create playlist'));
    await settle(t, 2);
    expect(find.text('Enter a name'), findsOneWidget);
    await t.enterText(find.byType(TextField), '  list 0 ');
    await t.tap(find.bySemanticsLabel('Create playlist'));
    await settle(t, 2);
    expect(find.text('Name already used'), findsOneWidget);
    expect(c.read(playlistProvider), hasLength(1));
  });

  testWidgets('at 10 playlists the middle button only closes', (t) async {
    final c = await open(t, playlists(10));
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await settle(t, 12);
    expect(find.bySemanticsLabel('Make a new playlist'), findsNothing);
    expect(find.text('Limit of 10'), findsOneWidget);
    expect(find.text('List 9'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Close'));
    await settle(t, 12);
    expect(find.text('List 9'), findsNothing);
    expect(c.read(playlistProvider), hasLength(10));
  });

  testWidgets('back closes one layer at a time', (t) async {
    await open(t, playlists(2));
    await swipeOpen(t);
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await settle(t, 8);
    await t.binding.handlePopRoute();
    await settle(t, 8);
    expect(find.text('List 0'), findsNothing);
    expect(find.bySemanticsLabel('Like'), findsOneWidget);
    await t.binding.handlePopRoute();
    await settle(t, 8);
    expect(find.bySemanticsLabel('Like'), findsNothing);
  });

  testWidgets('opening another row closes this one', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(ProviderScope(
      overrides: [playerProvider.overrideWith((ref) => _Player())],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            NoorSongRow(song: a, onTap: () {}),
            NoorSongRow(song: song('b', 'Beta'), onTap: () {}),
          ]),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    await swipeOpen(t);
    expect(find.bySemanticsLabel('Like'), findsOneWidget);
    await t.fling(find.text('Beta'), const Offset(-260, 0), 1200);
    await settle(t);
    expect(find.bySemanticsLabel('Like'), findsOneWidget); // only Beta's
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('naming a card low on the screen scrolls it above the keyboard', (t) async {
    SharedPreferences.setMockInitialValues(playlists(1));
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final songs = [for (var i = 0; i < 20; i++) song('s$i', 'Song $i')];
    await t.pumpWidget(ProviderScope(
      overrides: [playerProvider.overrideWith((ref) => _Player())],
      child: MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Builder(
            builder: (context) => ListView(
              padding: EdgeInsets.only(
                  bottom: 120 + MediaQuery.viewInsetsOf(context).bottom),
              children: [for (final x in songs) NoorSongRow(song: x, onTap: () {})],
            ),
          ),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    // Song 10 sits near the bottom of the screen.
    final target = find.text('Song 10');
    expect(t.getRect(target).bottom, greaterThan(600));
    await t.fling(target, const Offset(-260, 0), 1200);
    await settle(t);
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await settle(t, 8);
    await t.tap(find.bySemanticsLabel('Make a new playlist'));
    await settle(t, 8);
    t.view.viewInsets = const FakeViewPadding(bottom: 340); // keyboard up
    await settle(t, 8);
    final field = t.getRect(find.byType(TextField));
    expect(field.bottom, lessThan(891 - 340));
    expect(t.takeException(), isNull);
  });

  test('no more than 10 playlists can be created', () async {
    SharedPreferences.setMockInitialValues(playlists(10));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(playlistProvider.notifier).loaded;
    expect(() => c.read(playlistProvider.notifier).create('Eleven'),
        throwsA(isA<PlaylistLimitException>()));
  });
}
