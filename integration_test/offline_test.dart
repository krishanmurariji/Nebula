// The real app on an Android emulator in airplane mode (the workflow turns
// it on before this runs, and grants the music permission).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nebula_music_player/main.dart' as app;

import 'helpers.dart';

void main() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('airplane mode: offline pill, offline search, My Music', (t) async {
    app.main();
    expect(await waitFor(t, find.text('Search'), timeout: const Duration(seconds: 90)),
        isTrue, reason: 'Home did not appear');

    expect(
        await waitFor(t, find.text('Offline · saved songs only'),
            timeout: const Duration(seconds: 40)),
        isTrue,
        reason: 'The offline pill did not appear in airplane mode');
    await shot(b, t, '05_offline_home');
    report('offline: pill shown');

    // My Music with the permission granted: no permission button.
    // On a fresh install the slider opens on My Favorites, so step along it
    // (My History, then My Music) to bring My Music on screen.
    final history = find.byIcon(Icons.history_rounded);
    if (history.evaluate().isNotEmpty) {
      await t.tap(history.first);
      await idle(t, const Duration(seconds: 2));
    }
    final music = find.byIcon(Icons.download_done_rounded);
    expect(await waitFor(t, music, timeout: const Duration(seconds: 5)), isTrue,
        reason: 'Could not reach the My Music card');
    {
      await t.tap(music.first);
      await idle(t, const Duration(seconds: 2));
      expect(find.bySemanticsLabel('Allow access'), findsNothing,
          reason: 'Permission was granted but My Music still asks for it');
      await shot(b, t, '06_my_music');
      report('my music: permission respected');
    }

    await t.tap(find.text('Search'));
    await idle(t, const Duration(seconds: 1));
    await t.enterText(find.byType(TextField).first, 'rain');
    await t.testTextInput.receiveAction(TextInputAction.search);
    expect(
        await waitFor(t, find.textContaining("You're offline"),
            timeout: const Duration(seconds: 15)),
        isTrue,
        reason: 'Offline search did not say so');
    await shot(b, t, '07_offline_search');
    report('offline: search explains and searches the phone');
    expect(t.takeException(), isNull);
  });
}
