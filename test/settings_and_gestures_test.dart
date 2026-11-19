import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/app_version.dart';
import 'package:noor/providers/gesture_settings_provider.dart';
import 'package:noor/providers/player_provider.dart';
import 'package:noor/screens/home_screen.dart';
import 'package:noor/screens/mini_player.dart';
import 'package:noor/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gestures_and_local_music_test.dart' show songs, openHome, settle;
import 'search_filter_test.dart' show FakePlayer;

void main() {
  group('gesture switches', () {
    test('all on by default; switching one off is kept on the phone', () async {
      SharedPreferences.setMockInitialValues({});
      final n = GestureSettingsNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state, NoorGesture.values.toSet());
      await n.set(NoorGesture.bottomCardSwipe, false);
      final again = GestureSettingsNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(again.state.contains(NoorGesture.bottomCardSwipe), isFalse);
      expect(again.state.contains(NoorGesture.playerRecordSwipe), isTrue);
    });

    test('an unreadable saved value keeps everything on', () async {
      SharedPreferences.setMockInitialValues({GestureSettingsNotifier.key: '{bad'});
      final n = GestureSettingsNotifier();
      await Future<void>.delayed(Duration.zero);
      expect(n.state, NoorGesture.values.toSet());
    });

    testWidgets('bottom card swipe switched off: dragging does not change the song',
        (t) async {
      final p = await openHome(t,
          player: NebulaPlayerState(song: songs[0], status: NebulaPlayerStatus.playing),
          prefs: {
            'nebula_history': jsonEncode(songs.map((x) => x.toMap()).toList()),
            GestureSettingsNotifier.key: jsonEncode(['bottomCardSwipe']),
          });
      await t.drag(
          find.descendant(of: find.byType(MiniPlayer), matching: find.text('Alpha')),
          const Offset(-220, 0));
      await settle(t, 10);
      expect(p.played, isEmpty);
    });

    testWidgets('swipe-down search switched off: Home stays as it is', (t) async {
      await openHome(t, prefs: {
        'nebula_history': jsonEncode(songs.map((x) => x.toMap()).toList()),
        GestureSettingsNotifier.key: jsonEncode(['homeSwipeDownSearch']),
      });
      await t.fling(find.text('My History'), const Offset(0, 300), 1200);
      await settle(t, 6);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('Settings page', () {
    Future<void> openSettings(WidgetTester t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(411, 2000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [playerProvider.overrideWith((ref) => FakePlayer())],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await t.pump(const Duration(milliseconds: 200));
    }

    testWidgets('Gestures come first, with a switch for each', (t) async {
      await openSettings(t);
      final gestures = t.getTopLeft(find.text('Gestures')).dy;
      expect(gestures, lessThan(t.getTopLeft(find.text('Library')).dy));
      expect(find.byType(NoorToggle), findsNWidgets(NoorGesture.values.length));
      for (final g in NoorGesture.values) {
        expect(find.text(g.title), findsOneWidget);
      }
    });

    testWidgets('a switch turns its gesture off and on again', (t) async {
      await openSettings(t);
      final c = ProviderScope.containerOf(t.element(find.byType(SettingsScreen)));
      await t.tap(find.byType(NoorToggle).first);
      await t.pump(const Duration(milliseconds: 300));
      expect(c.read(gestureOnProvider(NoorGesture.values.first)), isFalse);
      await t.tap(find.byType(NoorToggle).first);
      await t.pump(const Duration(milliseconds: 300));
      expect(c.read(gestureOnProvider(NoorGesture.values.first)), isTrue);
    });

    testWidgets('the version line shows what this build really is', (t) async {
      await openSettings(t);
      final label = t.widget<Text>(find.byKey(const ValueKey('app-version'))).data;
      // Tests run without the release workflow's values.
      expect(label, AppVersion.label);
      expect(label, 'Development build');
      expect(find.textContaining('1.0.0'), findsNothing);
    });

    testWidgets('clearing history asks first', (t) async {
      await openSettings(t);
      await t.tap(find.text('Clear history'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Clear your history?'), findsOneWidget);
      await t.tap(find.text('Keep'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Clear your history?'), findsNothing);
    });
  });
}
