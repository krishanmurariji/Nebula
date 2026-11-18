import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/providers/player_provider.dart';
import 'package:nebula_music_player/screens/home_screen.dart';
import 'package:nebula_music_player/screens/mini_player.dart';
import 'package:nebula_music_player/theme/noor_song_card.dart';
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
  const first = "Let's play your first song";

  testWidgets('new install: the three cards and the first-song message, no bottom card', (t) async {
    await openHome(t, {});
    expect(find.text(first), findsNothing); // not before the library is read
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(first), findsOneWidget);
    expect(find.text('Tap Search above to find one'), findsOneWidget);
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
    expect(find.text('Official only'), findsOneWidget);
    expect(find.text('Best match'), findsOneWidget);
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

  test('the three default cards always come first; empty playlists are left out', () {
    final cats = homeCategories(liked: [], history: [], onDevice: [], playlists: []);
    expect(cats.map((c) => c.title), ['My Favorites', 'My History', 'My Music']);
  });
}
