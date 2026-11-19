// The real app on an Android emulator in airplane mode (the workflow turns
// it on before this runs, and grants the music permission).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:noor/theme/noor_search_button.dart';
import 'package:noor/main.dart' as app;

import 'helpers.dart';

void main() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('airplane mode: offline pill, offline search, My Music', (t) async {
    app.main();
    expect(await waitFor(t, find.byType(NoorSearchButton), timeout: const Duration(seconds: 90)),
        isTrue, reason: 'Home did not appear');

    expect(
        await waitFor(t, find.text('Offline · saved songs only'),
            timeout: const Duration(seconds: 40)),
        isTrue,
        reason: 'The offline pill did not appear in airplane mode');
    await shot(b, t, '05_offline_home');
    report('offline: pill shown');

    // My Music with the permission granted: no permission button.
    // The slider is My History, My Favorites, My Music; Home opens on
    // whichever card first has songs, which can be History or Music
    // depending on when the phone's music finishes loading. Step right
    // (tap the card beside the open one) until My Music is on screen.
    for (var i = 0;
        i < 3 && find.byIcon(Icons.download_done_rounded).evaluate().isEmpty;
        i++) {
      final fav = find.byIcon(Icons.favorite_rounded);
      if (fav.evaluate().isEmpty) break;
      await t.tap(fav.first);
      await idle(t, const Duration(seconds: 2));
    }
    final music = find.byIcon(Icons.download_done_rounded);
    expect(await waitFor(t, music, timeout: const Duration(seconds: 5)), isTrue,
        reason: 'Could not reach the My Music card');
    await t.tap(music.first);
    // The workflow grants the permission right after install; the app
    // checks again when My Music opens. Give it a few seconds.
    Finder asks() => find.text('Allow access');
    Finder pill() => find.text('Show music from this phone');
    final end = DateTime.now().add(const Duration(seconds: 15));
    var tries = 0;
    while (DateTime.now().isBefore(end) &&
        (asks().evaluate().isNotEmpty || pill().evaluate().isNotEmpty)) {
      await idle(t, const Duration(milliseconds: 500));
      // Opening My Music again makes the app check the permission again.
      if (++tries % 4 == 0 && music.evaluate().isNotEmpty) {
        await t.tap(music.first, warnIfMissed: false);
      }
    }
    await shot(b, t, '06_my_music');
    expect(asks(), findsNothing,
        reason: 'Permission was granted but My Music still asks for it');
    expect(pill(), findsNothing,
        reason: 'Permission was granted but My Music still offers access');
    report('my music: permission respected');
    // A short tone is placed in the phone's Music folder by the workflow.
    final tone = find.text('Noor Test Tone');
    if (await waitFor(t, tone, timeout: const Duration(seconds: 10))) {
      report('my music: phone song listed');
      await t.tap(tone.first);
      await idle(t, const Duration(seconds: 3));
      await shot(b, t, '06b_phone_song_playing');
      report('my music: phone song tapped offline');
    } else {
      report('my music: phone song NOT listed');
    }

    await t.tap(find.byType(NoorSearchButton));
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
  }, timeout: const Timeout(Duration(minutes: 5)));
}
