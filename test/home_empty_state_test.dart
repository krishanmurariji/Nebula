import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/providers/library_provider.dart';
import 'package:noor/providers/player_provider.dart';
import 'package:noor/providers/home_order_provider.dart';
import 'package:noor/screens/home_screen.dart';
import 'package:noor/screens/mini_player.dart';
import 'package:noor/theme/noor_song_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'search_filter_test.dart' show FakePlayer;

Future<void> openHome(WidgetTester t, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  t.view.physicalSize = const Size(411, 915);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [playerProvider.overrideWith((ref) => FakePlayer())],
    child: const MaterialApp(home: HomeScreen()),
  ));
}

const _song = {'videoId': 'abcdefghijk', 'title': 'Saved Song', 'artist': 'Someone', 'thumbnailUrl': ''};

void main() {
  const first = 'No song available';

  testWidgets('new install: the three cards and "No song available", no bottom card', (t) async {
    await openHome(t, {});
    expect(find.text(first), findsNothing); // not before the library is read
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(first), findsOneWidget);
    expect(find.byIcon(Icons.music_off_rounded), findsOneWidget);
    // Only the open card's name, under the slider; the cards show icons.
    // My History comes first now; My Favorites is the card beside it.
    expect(find.text('My History'), findsOneWidget);
    expect(find.text('My Favorites'), findsNothing);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('Saved Song'), findsNothing);
    expect(find.descendant(of: find.byType(MiniPlayer), matching: find.byType(Text)), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('saved history: opens on My History, never flashes the empty message', (t) async {
    await openHome(t, {'nebula_history': jsonEncode([_song])});
    expect(find.text(first), findsNothing);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(first), findsNothing);
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.widgetWithText(NoorSongCard, 'Saved Song'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('after a restart the last played song waits, paused, in the bottom card', (t) async {
    await openHome(t, {'noor_last_played': jsonEncode(_song)});
    await t.pump(const Duration(milliseconds: 100));
    expect(find.descendant(of: find.byType(MiniPlayer), matching: find.text('Saved Song')),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a side card opens it and shows its songs', (t) async {
    final other = Map<String, Object>.from(_song)..['videoId'] = 'zzzzzzzzzzz'..['title'] = 'Loved Song';
    await openHome(t, {
      'nebula_history': jsonEncode([_song]),
      'nebula_liked': jsonEncode([other]),
    });
    await t.pump(const Duration(milliseconds: 1500));
    // Opens on My History (first), then the favorites card beside it.
    expect(find.widgetWithText(NoorSongCard, 'Saved Song'), findsOneWidget);
    await t.tap(find.byIcon(Icons.favorite_rounded));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.widgetWithText(NoorSongCard, 'Loved Song'), findsOneWidget);
    expect(find.widgetWithText(NoorSongCard, 'Saved Song'), findsNothing);
  });

  testWidgets('search opens from the icon, shows the watermark, and closes', (t) async {
    await openHome(t, {});
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.bySemanticsLabel('Search'));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(TextField), findsOneWidget);
    // The filters now sit behind the settings button, which says so.
    expect(find.bySemanticsLabel('Search filters'), findsOneWidget);
    expect(find.bySemanticsLabel('Noor'), findsWidgets); // the faded mark
    expect(find.text(first), findsNothing);
    await t.tap(find.bySemanticsLabel('Close search'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsNothing);
    expect(find.text(first), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('back closes search instead of leaving Home', (t) async {
    await openHome(t, {});
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.bySemanticsLabel('Search'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsNothing);
  });

  test('the three default cards always come first, then every playlist', () {
    final cats = homeCategories(liked: [], history: [], onDevice: [], playlists: [
      const Playlist(id: 'p', name: 'Empty one'),
    ]);
    expect(cats.map((c) => c.title), ['My History', 'My Favorites', 'My Music', 'Empty one']);
  });

  test('the slider follows the order the user arranged; new playlists go last', () {
    final cats = homeCategories(
        liked: [],
        history: [],
        onDevice: [],
        playlists: [const Playlist(id: 'p', name: 'Road'), const Playlist(id: 'q', name: 'New')],
        order: ['p', 'music', 'hist', 'fav']);
    expect(cats.map((c) => c.id), ['p', 'music', 'hist', 'fav', 'q']);
  });

  Future<void> frames(WidgetTester t, int n) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> home(WidgetTester t) async {
    await openHome(t, {
      'nebula_playlists': jsonEncode([
        {'id': 'p1', 'name': 'Road Trip', 'songs': [_song]}
      ]),
    });
    await frames(t, 10);
    return ProviderScope.containerOf(t.element(find.byType(HomeScreen)));
  }

  /// Holds [icon]'s card long enough to pick it up.
  Future<TestGesture> pickUp(WidgetTester t, IconData icon) async {
    final g = await t.startGesture(t.getCenter(find.byIcon(icon).first));
    await frames(t, 5);
    return g;
  }

  testWidgets('holding a card: it stays under the finger, the others gather round it narrow',
      (t) async {
    await home(t);
    final where = t.getCenter(find.byIcon(Icons.queue_music_rounded));
    final g = await pickUp(t, Icons.queue_music_rounded);
    await frames(t, 6);
    for (final icon in [
      Icons.history_rounded,
      Icons.favorite_rounded,
      Icons.download_done_rounded,
      Icons.queue_music_rounded,
    ]) {
      expect(find.byIcon(icon), findsWidgets);
    }
    // The card being held is drawn under the finger, not moved away.
    final lifted = t.getCenter(find.byIcon(Icons.queue_music_rounded).last);
    expect((lifted.dx - where.dx).abs(), lessThan(30));
    expect(find.text('Drag to a new place, let go to finish'), findsOneWidget);
    expect(find.text('Done'), findsNothing); // no button: letting go finishes
    await g.up();
    await frames(t, 6);
    expect(find.text('Drag to a new place, let go to finish'), findsNothing);
    expect(find.text('Road Trip'), findsOneWidget); // back to the open card
  });

  testWidgets('drag over another card to swap places; letting go keeps it', (t) async {
    final c = await home(t);
    final g = await pickUp(t, Icons.queue_music_rounded);
    await frames(t, 6);
    await g.moveTo(t.getCenter(find.byIcon(Icons.history_rounded).first));
    await frames(t, 3);
    await g.up();
    await frames(t, 6);
    expect(c.read(homeOrderProvider).first, 'p1');
  });

  testWidgets('a playlist let go over the wormhole at the top is swallowed and deleted; Undo brings it back',
      (t) async {
    final c = await home(t);
    expect(find.text('Drag here to delete the playlist').hitTestable(), findsNothing);
    final g = await pickUp(t, Icons.queue_music_rounded);
    await g.moveBy(const Offset(0, -10));
    await frames(t, 4);
    final zone = find.text('Drag here to delete the playlist');
    expect(zone.hitTestable(), findsOneWidget); // faint, at the top
    expect(t.getRect(zone).top, lessThan(140));
    await g.moveTo(t.getCenter(zone));
    await frames(t, 3);
    expect(find.text('Let go to delete'), findsOneWidget); // turned red
    await g.up();
    await frames(t, 12); // spirals in and vanishes
    expect(c.read(playlistProvider), isEmpty);
    // The message: a capsule at the top, with Undo.
    expect(find.text('"Road Trip" deleted'), findsOneWidget);
    expect(t.getRect(find.text('"Road Trip" deleted')).top, lessThan(80));
    await t.tap(find.text('Undo'));
    await frames(t, 6);
    expect(c.read(playlistProvider).single.name, 'Road Trip');
  });

  testWidgets('My History, Favorites and Music cannot be deleted', (t) async {
    await home(t);
    final g = await pickUp(t, Icons.download_done_rounded);
    await g.moveBy(const Offset(0, -10));
    await frames(t, 4);
    expect(find.text('Drag here to delete the playlist').hitTestable(), findsNothing);
    await g.up();
    await frames(t, 4);
  });



}
