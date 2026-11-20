import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/models/song.dart';
import 'package:noor/providers/library_provider.dart';
import 'package:noor/providers/player_provider.dart';
import 'package:noor/screens/mini_player.dart';
import 'package:noor/screens/player_screen.dart';
import 'package:noor/screens/upnext_screen.dart';
import 'package:noor/theme/noor_like_burst.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song s(String t) => Song(videoId: t.padRight(11, 'x').substring(0, 11), title: t, artist: 'A', thumbnailUrl: '');
final songs = [s('One'), s('Two'), s('Three'), s('Four')];

class _P extends StateNotifier<NebulaPlayerState> implements PlayerNotifier {
  _P(super.s);
  List<Song>? order;
  @override
  Future<void> setQueueOrder(List<Song> songs) async => order = songs;
  @override
  Future<void> playSong(Song song, {List<Song>? queue}) async {}
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<void> frames(WidgetTester t, int n) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test('moving a song in a list', () {
    expect(moveSongInList(songs, songs[0].videoId, 2).map((x) => x.title),
        ['Two', 'Three', 'One', 'Four']);
    expect(moveSongInList(songs, 'missingxxxx', 1), songs);
    expect(moveSongInList(songs, songs[3].videoId, 0).first.title, 'Four');
  });

  testWidgets('Up next: hold a song and drag it; the list and what plays next follow',
      (t) async {
    SharedPreferences.setMockInitialValues(
        {'nebula_liked': jsonEncode(songs.map((x) => x.toMap()).toList())});
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final p = _P(NebulaPlayerState(song: songs[0], status: NebulaPlayerStatus.paused));
    await t.pumpWidget(ProviderScope(
      overrides: [playerProvider.overrideWith((ref) => p)],
      child: const MaterialApp(home: UpNextScreen()),
    ));
    await frames(t, 3);
    final c = ProviderScope.containerOf(t.element(find.byType(UpNextScreen)));
    expect(find.text('My Favorites'), findsOneWidget);

    // Hold "One" and drag it down past "Three".
    final from = t.getCenter(find.text('One'));
    final below = t.getCenter(find.text('Three'));
    final g = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 700)); // the hold
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, below + const Offset(0, 30), i / 10)!);
      await t.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await frames(t, 6);

    expect(c.read(likedProvider).map((x) => x.title), ['Two', 'Three', 'One', 'Four']);
    expect(p.order!.map((x) => x.title), ['Two', 'Three', 'One', 'Four']);
  });

  testWidgets('swiping the bottom card up: the player rises out of it', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final p = _P(NebulaPlayerState(song: songs[0], status: NebulaPlayerStatus.paused));
    await t.pumpWidget(ProviderScope(
      overrides: [playerProvider.overrideWith((ref) => p)],
      child: const MaterialApp(
          home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer()))),
    ));
    await frames(t, 2);
    await t.fling(find.text('One'), const Offset(0, -200), 1200);
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
    // Mid-way: still below its final place and a little smaller.
    final lift = t.widget<FractionalTranslation>(find.ancestor(
        of: find.byType(PlayerScreen), matching: find.byType(FractionalTranslation)).first);
    expect(lift.translation.dy, greaterThan(0));
    await frames(t, 6);
    expect(find.byType(PlayerScreen), findsOneWidget);
    final done = t.widget<FractionalTranslation>(find.ancestor(
        of: find.byType(PlayerScreen), matching: find.byType(FractionalTranslation)).first);
    expect(done.translation.dy, 0);
  });

  testWidgets('a double tap on the bottom card plays the shared like animation', (t) async {
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final p = _P(NebulaPlayerState(song: songs[0], status: NebulaPlayerStatus.paused));
    await t.pumpWidget(ProviderScope(
      overrides: [playerProvider.overrideWith((ref) => p)],
      child: const MaterialApp(
          home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer()))),
    ));
    await frames(t, 2);
    await t.tap(find.text('One'));
    await t.pump(const Duration(milliseconds: 40));
    await t.tap(find.text('One'));
    await t.pump(const Duration(milliseconds: 100));
    final b = t.widget<NoorLikeBurst>(find.byType(NoorLikeBurst));
    expect(b.trigger, 1);
    expect(b.liked, isTrue);
    await frames(t, 12);
  });
}
