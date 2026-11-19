import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/models/song.dart';
import 'package:noor/providers/player_provider.dart';
import 'package:noor/screens/player_screen.dart';
import 'package:noor/theme/noor_turntable.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _P extends StateNotifier<NebulaPlayerState> implements PlayerNotifier {
  _P(super.s);
  final played = <String>[];
  @override
  Future<void> playSong(Song song, {List<Song>? queue}) async => played.add(song.title);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Song s(String t) => Song(videoId: t.padRight(11, 'x').substring(0, 11), title: t, artist: 'A', thumbnailUrl: '');

void main() {
  final songs = [s('One'), s('Two'), s('Three')];

  Future<_P> open(WidgetTester t) async {
    SharedPreferences.setMockInitialValues(
        {'nebula_liked': jsonEncode(songs.map((x) => x.toMap()).toList())});
    t.view.physicalSize = const Size(411, 891);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final p = _P(NebulaPlayerState(song: songs[1], status: NebulaPlayerStatus.paused));
    await t.pumpWidget(ProviderScope(
      overrides: [playerProvider.overrideWith((ref) => p)],
      child: const MaterialApp(home: PlayerScreen()),
    ));
    await t.pump(const Duration(milliseconds: 200));
    return p;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('turntable, title, Search and the five controls', (t) async {
    await open(t);
    expect(find.byType(NoorTurntable), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    for (final l in ['Shuffle', 'Previous', 'Next', 'Repeat this song']) {
      expect(find.bySemanticsLabel(l), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('swipe left on the record plays the next song, right the previous', (t) async {
    final p = await open(t);
    await t.fling(find.byType(NoorTurntable), const Offset(-300, 0), 1500);
    await settle(t);
    expect(p.played, ['Three']);
    await t.fling(find.byType(NoorTurntable), const Offset(300, 0), 1500);
    await settle(t);
    expect(p.played, ['Three', 'One']);
  });

  testWidgets('the Next button follows the same list', (t) async {
    final p = await open(t);
    await t.tap(find.bySemanticsLabel('Next'));
    await settle(t);
    expect(p.played, ['Three']);
  });

  /// Drags the record in [steps] slow moves of [dx] (slow, so letting go is
  /// not a fling).
  Future<void> drag(WidgetTester t, TestGesture g, double dx, int steps) async {
    for (var i = 0; i < steps; i++) {
      await g.moveBy(Offset(dx, 0), timeStamp: Duration(milliseconds: 60 * (i + 1)));
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  NoorTurntable table(WidgetTester t) => t.widget<NoorTurntable>(find.byType(NoorTurntable));

  testWidgets('while swiping, the next record slides in beside the current one', (t) async {
    final p = await open(t);
    final g = await t.startGesture(t.getCenter(find.byType(NoorTurntable)));
    await drag(t, g, -12, 10);
    expect(table(t).discShift, lessThan(0));
    expect(table(t).incomingArtUrl, isNotNull);
    expect(table(t).incomingShift, greaterThan(table(t).discShift));
    expect(table(t).armDown, isFalse);
    expect(p.played, isEmpty); // nothing changes until the swipe is finished
    await g.up();
    await settle(t);
  });

  testWidgets('letting go early puts the record back; nothing changes', (t) async {
    final p = await open(t);
    final g = await t.startGesture(t.getCenter(find.byType(NoorTurntable)));
    await drag(t, g, -8, 10); // a short way
    await g.up();
    await settle(t);
    expect(p.played, isEmpty);
    expect(table(t).discShift, 0);
    expect(table(t).incomingArtUrl, isNull);
  });

  testWidgets('dragging back takes the swipe back', (t) async {
    final p = await open(t);
    final g = await t.startGesture(t.getCenter(find.byType(NoorTurntable)));
    await drag(t, g, -14, 20); // well past half way...
    expect(table(t).discShift, lessThan(-0.5));
    await drag(t, g, 14, 20); // ...and back
    await g.up();
    await settle(t);
    expect(p.played, isEmpty);
    expect(table(t).discShift, 0);
  });

  testWidgets('a slow swipe past a third finishes the change', (t) async {
    final p = await open(t);
    final g = await t.startGesture(t.getCenter(find.byType(NoorTurntable)));
    await drag(t, g, 12, 16); // right: the previous song
    await g.up();
    await settle(t);
    expect(p.played, ['One']);
    expect(table(t).discShift, 0);
  });
}
