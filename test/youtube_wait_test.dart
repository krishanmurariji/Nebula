import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/models/song.dart';
import 'package:noor/providers/player_provider.dart';
import 'package:noor/screens/mini_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_filter_test.dart' show FakePlayer;

const song = Song(videoId: 'waitxxxxxxx', title: 'Dil Darian', artist: 'Kambi', thumbnailUrl: '');

Future<void> show(WidgetTester t, NebulaPlayerState s) async {
  SharedPreferences.setMockInitialValues({});
  final p = FakePlayer();
  await t.pumpWidget(ProviderScope(
    overrides: [playerProvider.overrideWith((ref) => p..state = s)],
    child: const MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer()))),
  ));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('waiting for YouTube: the card says it plays by itself, with the seconds', (t) async {
    await show(t, const NebulaPlayerState(
        pendingSong: song, status: NebulaPlayerStatus.loading, cooldownSeconds: 35));
    expect(find.text('YouTube busy · plays in 35s'), findsOneWidget);
    expect(find.text('Loading…'), findsNothing);
  });

  testWidgets('a normal load still says Loading…', (t) async {
    await show(t, const NebulaPlayerState(pendingSong: song, status: NebulaPlayerStatus.loading));
    expect(find.text('Loading…'), findsOneWidget);
  });

  testWidgets('after giving up: the error countdown', (t) async {
    await show(t, const NebulaPlayerState(
        song: song, status: NebulaPlayerStatus.error, cooldownSeconds: 12));
    expect(find.text('Retry in 12s…'), findsOneWidget);
  });

  testWidgets('after giving up and the pause is over: tap play to retry', (t) async {
    await show(t, const NebulaPlayerState(song: song, status: NebulaPlayerStatus.error));
    expect(find.text('Tap play to retry'), findsOneWidget);
  });
}
