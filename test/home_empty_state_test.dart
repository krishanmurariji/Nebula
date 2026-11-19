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

  Future<ProviderContainer> arrange(WidgetTester t) async {
    final c = await home(t);
    // Home opens on the first card with songs: the playlist.
    final g = await pickUp(t, Icons.queue_music_rounded);
    await g.up();
    await frames(t, 6);
    return c;
  }

  testWidgets('holding a slider card shrinks the open card: all cards in a row, centred',
      (t) async {
    await arrange(t);
    for (final icon in [
      Icons.history_rounded,
      Icons.favorite_rounded,
      Icons.download_done_rounded,
      Icons.queue_music_rounded,
    ]) {
      expect(find.byIcon(icon), findsOneWidget);
    }
    // All the same narrow size, and centred on the screen.
    final hist = t.getRect(find.byIcon(Icons.history_rounded));
    final road = t.getRect(find.byIcon(Icons.queue_music_rounded));
    final mid = (hist.center.dx + road.center.dx) / 2;
    expect((mid - 411 / 2).abs(), lessThan(4));
    expect(find.text('Done'), findsOneWidget);
    await t.tap(find.text('Done'));
    await frames(t, 6);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('one hold flows straight into a drag', (t) async {
    await home(t);
    final g = await pickUp(t, Icons.queue_music_rounded);
    await g.moveBy(const Offset(-10, 0));
    await frames(t, 4);
    expect(find.text('Done'), findsOneWidget); // arranging while still held
    await g.up();
    await frames(t, 4);
  });

  testWidgets('dragging a card onto another reorders them, and it is kept', (t) async {
    final c = await arrange(t);
    final g = await pickUp(t, Icons.download_done_rounded);
    await g.moveTo(t.getCenter(find.byIcon(Icons.history_rounded)));
    await frames(t, 3);
    await g.up();
    await frames(t, 6);
    expect(c.read(homeOrderProvider).take(2), ['music', 'hist']);
    expect(t.getCenter(find.byIcon(Icons.download_done_rounded)).dx,
        lessThan(t.getCenter(find.byIcon(Icons.history_rounded)).dx));
  });

  testWidgets('a playlist dropped on the bin at the top falls in and is deleted; Undo brings it back',
      (t) async {
    final c = await arrange(t);
    // Hidden (slid up, untouchable) until a playlist is picked up.
    expect(find.text('Drag here to delete the playlist').hitTestable(), findsNothing);
    final g = await pickUp(t, Icons.queue_music_rounded);
    await g.moveBy(const Offset(0, -10));
    await frames(t, 4);
    final zone = find.text('Drag here to delete the playlist');
    expect(zone.hitTestable(), findsOneWidget); // faint, at the top
    expect(t.getRect(zone).top, lessThan(120));
    await g.moveTo(t.getCenter(zone));
    await frames(t, 3);
    expect(find.text('Let go to delete'), findsOneWidget); // turned red
    await g.up();
    await frames(t, 14); // lid opens, card falls in, lid closes
    expect(c.read(playlistProvider), isEmpty);
    expect(find.text('Undo'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await frames(t, 4);
    expect(c.read(playlistProvider).single.name, 'Road Trip');
  });

  testWidgets('My History, Favorites and Music cannot be binned', (t) async {
    await arrange(t);
    final g = await pickUp(t, Icons.history_rounded);
    await g.moveBy(const Offset(0, -10));
    await frames(t, 4);
    expect(find.text('Drag here to delete the playlist').hitTestable(), findsNothing);
    await g.up();
    await frames(t, 4);
  });


}
