import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/providers/player_provider.dart';
import 'package:nebula_music_player/screens/home_screen.dart';
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

void main() {
  const empty = 'Nothing here yet';

  testWidgets('no saved songs: the empty page appears only after loading', (t) async {
    await openHome(t, {});
    // First frame: the library has not been read yet, so claim nothing.
    expect(find.text(empty), findsNothing);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(empty), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('saved songs: the empty page never flashes', (t) async {
    final song = {'videoId': 'abcdefghijk', 'title': 'Saved Song', 'artist': 'Someone', 'thumbnailUrl': ''};
    await openHome(t, {'nebula_history': jsonEncode([song])});
    expect(find.text(empty), findsNothing);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text(empty), findsNothing);
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.text('Saved Song'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the header is just the search bar (no app icon)', (t) async {
    await openHome(t, {});
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Search songs, artists…'), findsOneWidget);
    expect(find.bySemanticsLabel('Noor'), findsNothing);
  });
}
