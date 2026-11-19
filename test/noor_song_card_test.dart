import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/theme/noor_gap_border.dart';
import 'package:noor/models/song.dart';
import 'package:noor/providers/player_provider.dart';
import 'package:noor/screens/upnext_screen.dart';
import 'package:noor/theme/noor_play_pause.dart';
import 'package:noor/theme/noor_song_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

Song song(String id, String t) =>
    Song(videoId: id.padRight(11, 'x'), title: t, artist: 'Chan $id', thumbnailUrl: '');

class _Player extends StateNotifier<NebulaPlayerState> implements PlayerNotifier {
  _Player(super.s);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Finder heartIcon() => find.byIcon(Icons.favorite_rounded);
  Color heartColor(WidgetTester t) => t.widget<Icon>(heartIcon()).color!;

  group('NoorSongCard', () {
    testWidgets('title, artist and the play button; no heart until a double tap', (t) async {
      await t.pumpWidget(host(NoorSongCard(
          thumbnailUrl: '', title: 'Kesariya', artist: 'Arijit', onTap: () {}, onToggleLike: () {})));
      expect(find.text('Kesariya'), findsOneWidget);
      expect(find.text('Arijit'), findsOneWidget);
      expect(find.byType(NoorPlayPauseButton), findsOneWidget);
      expect(heartIcon(), findsNothing);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    });

    testWidgets('a badge follows the artist only when given', (t) async {
      await t.pumpWidget(host(NoorSongCard(
          thumbnailUrl: '', title: 'A', artist: 'c', badge: 'Official', onTap: () {})));
      expect(find.text('c  ·  Official'), findsOneWidget);
    });

    testWidgets('a tap plays; the button calls play/pause', (t) async {
      var plays = 0, toggles = 0;
      await t.pumpWidget(host(NoorSongCard(
          thumbnailUrl: '', title: 'A', artist: 'c',
          onTap: () => plays++, onPlayPause: () => toggles++, onToggleLike: () {})));
      await t.tap(find.text('A'));
      await t.pump(const Duration(milliseconds: 400)); // waits out a possible double tap
      expect(plays, 1);
      await t.tap(find.byType(NoorPlayPauseButton));
      await t.pump(const Duration(milliseconds: 400));
      expect(toggles, 1);
    });

    testWidgets('double tap on an unliked song: a white heart turns red, then fades', (t) async {
      var likes = 0, plays = 0;
      await t.pumpWidget(host(NoorSongCard(
          thumbnailUrl: '', title: 'A', artist: 'c',
          onTap: () => plays++, onToggleLike: () => likes++)));
      await t.tap(find.text('A'));
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(find.text('A'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(likes, 1);
      expect(plays, 0);
      expect(heartColor(t).value, Colors.white.value);
      await t.pump(const Duration(milliseconds: 500));
      expect(heartColor(t).green, lessThan(120)); // red now
      await t.pump(const Duration(milliseconds: 900));
      expect(heartIcon(), findsNothing);
    });

    testWidgets('double tap on a liked song: a red heart turns white', (t) async {
      await t.pumpWidget(host(NoorSongCard(
          thumbnailUrl: '', title: 'A', artist: 'c', liked: true, onTap: () {}, onToggleLike: () {})));
      await t.tap(find.text('A'));
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(find.text('A'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(heartColor(t).green, lessThan(120)); // starts red
      await t.pump(const Duration(milliseconds: 500));
      expect(heartColor(t).green, greaterThan(200)); // ends white
      await t.pump(const Duration(milliseconds: 900));
    });
  });

  /// Where the play button's dot is, in turns from the top.
  double dotTurn(WidgetTester t) => t
      .widgetList<CustomPaint>(find.descendant(
          of: find.byType(NoorPlayPauseButton), matching: find.byType(CustomPaint)))
      .map((c) => c.painter)
      .whereType<NoorGapRingPainter>()
      .single
      .turn;

  NoorGapBorderPainter outline(WidgetTester t) => t
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.foregroundPainter)
      .whereType<NoorGapBorderPainter>()
      .single;

  testWidgets('while loading: "Loading…" replaces the artist and the button dot goes round', (t) async {
    await t.pumpWidget(host(NoorSongCard(
        thumbnailUrl: '', title: 'A', artist: 'Artist', loading: true, current: true, onTap: () {})));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Loading…'), findsOneWidget);
    expect(find.text('Artist'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing); // no line any more
    final a = dotTurn(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(dotTurn(t), isNot(a)); // moving
    expect(outline(t).gap, greaterThan(0)); // the card itself stays still
  });

  testWidgets('when loading ends the dot glides back to the top and stays', (t) async {
    await t.pumpWidget(host(NoorSongCard(
        thumbnailUrl: '', title: 'A', artist: 'Artist', loading: true, onTap: () {})));
    await t.pump(const Duration(milliseconds: 500));
    expect(dotTurn(t), isNot(0));
    await t.pumpWidget(host(NoorSongCard(
        thumbnailUrl: '', title: 'A', artist: 'Artist', onTap: () {})));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(dotTurn(t), 0);
    expect(find.text('Artist'), findsOneWidget);
  });

  testWidgets('at rest the dot sits at the top', (t) async {
    await t.pumpWidget(host(NoorSongCard(thumbnailUrl: '', title: 'A', artist: 'c', onTap: () {})));
    await t.pump(const Duration(milliseconds: 300));
    expect(dotTurn(t), 0);
  });

  testWidgets('the card dips the moment it is touched', (t) async {
    await t.pumpWidget(host(NoorSongCard(thumbnailUrl: '', title: 'A', artist: 'c', onTap: () {})));
    final g = await t.startGesture(t.getCenter(find.text('A')));
    await t.pump(const Duration(milliseconds: 150));
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, lessThan(1));
    await g.up();
    await t.pump(const Duration(milliseconds: 400));
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  group('Up next', () {
    Future<void> open(WidgetTester t, NebulaPlayerState ps) async {
      t.view.physicalSize = const Size(411, 915);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [playerProvider.overrideWith((ref) => _Player(ps))],
        child: const MaterialApp(home: UpNextScreen()),
      ));
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('a liked song: My Favorites, with the same cards as Home', (t) async {
      final songs = [song('a', 'First'), song('b', 'Second'), song('c', 'Third')];
      SharedPreferences.setMockInitialValues({
        'nebula_liked': jsonEncode(songs.map((s) => s.toMap()).toList()),
      });
      await open(t, NebulaPlayerState(song: songs[1], status: NebulaPlayerStatus.paused));
      expect(find.text('My Favorites'), findsOneWidget);
      expect(find.byType(NoorSongCard), findsNWidgets(3));
    });

    testWidgets('a song in a playlist: the playlist, under its name', (t) async {
      final songs = [song('a', 'First'), song('b', 'Second')];
      SharedPreferences.setMockInitialValues({
        'nebula_liked': jsonEncode([songs[0].toMap()]),
        'nebula_playlists': jsonEncode([
          {'id': 'p1', 'name': 'Road Trip', 'songs': songs.map((s) => s.toMap()).toList()}
        ]),
      });
      await open(t, NebulaPlayerState(song: songs[0], status: NebulaPlayerStatus.paused));
      expect(find.text('Road Trip'), findsOneWidget);
      expect(find.byType(NoorSongCard), findsNWidgets(2));
    });

    testWidgets('nothing played before: just the playing song, as My History', (t) async {
      await open(t, NebulaPlayerState(song: song('a', 'Only'), status: NebulaPlayerStatus.paused));
      expect(find.text('My History'), findsOneWidget);
      expect(find.byType(NoorSongCard), findsOneWidget);
    });

    testWidgets('no song at all says so', (t) async {
      await open(t, const NebulaPlayerState());
      expect(find.text('No song available'), findsOneWidget);
    });
  });
}
