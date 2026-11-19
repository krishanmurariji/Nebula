import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/providers/library_provider.dart';
import 'package:noor/providers/player_provider.dart';
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
    expect(find.text('My Favorites'), findsOneWidget);
    expect(find.text('My History'), findsNothing);
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
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
    expect(find.widgetWithText(NoorSongCard, 'Loved Song'), findsOneWidget);
    await t.tap(find.byIcon(Icons.history_rounded));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.widgetWithText(NoorSongCard, 'Saved Song'), findsOneWidget);
    expect(find.widgetWithText(NoorSongCard, 'Loved Song'), findsNothing);
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
    expect(cats.map((c) => c.title), ['My Favorites', 'My History', 'My Music', 'Empty one']);
  });

  testWidgets('long press on a playlist card offers to delete it', (t) async {
    await openHome(t, {
      'nebula_playlists': jsonEncode([
        {'id': 'p1', 'name': 'Road Trip', 'songs': [_song]}
      ]),
    });
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // Home opens on the first card with songs: the playlist.
    final container = ProviderScope.containerOf(t.element(find.byType(HomeScreen)));
    await t.longPress(find.byIcon(Icons.queue_music_rounded));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Delete "Road Trip"?'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await t.pump(const Duration(milliseconds: 400));
    expect(container.read(playlistProvider), isEmpty);
  });
}
