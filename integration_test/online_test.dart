// The real app on an Android emulator, online: first run, search, tap a
// song, see feedback at once, and see how playback ends up.
//
// YouTube often refuses data-centre networks (like GitHub's), so the test
// does not fail when YouTube says no; it fails when the app itself does:
// a crash, a frozen screen, or no feedback after a tap.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nebula_music_player/main.dart' as app;
import 'package:nebula_music_player/theme/noor_play_pause.dart';
import 'package:nebula_music_player/widgets/song_details_panel.dart';
import 'package:nebula_music_player/widgets/song_row.dart';

import 'helpers.dart';

void main() {
  final b = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first run → search → play', (t) async {
    app.main();
    expect(await waitFor(t, find.text('Search'), timeout: const Duration(seconds: 90)),
        isTrue, reason: 'Home did not appear');
    await idle(t, const Duration(seconds: 2));
    await shot(b, t, '01_home_first_run');

    await t.tap(find.text('Search'));
    await idle(t, const Duration(seconds: 1));
    await t.enterText(find.byType(TextField).first, 'Kesariya');
    await t.testTextInput.receiveAction(TextInputAction.search);

    final outcome = find.byWidgetPredicate((w) =>
        w is NoorSongRow ||
        (w is Text &&
            (w.data ?? '').contains(RegExp(r"offline|limiting|failed|timed out|No results",
                caseSensitive: false))));
    expect(await waitFor(t, outcome, timeout: const Duration(seconds: 60)), isTrue,
        reason: 'Search gave no answer at all');
    await idle(t, const Duration(seconds: 1));
    await shot(b, t, '02_search');

    final rows = find.byType(NoorSongRow);
    if (rows.evaluate().isEmpty) {
      report('search: YouTube gave no results here (blocked or offline)');
      return;
    }
    report('search: ${rows.evaluate().length} results');

    // A tap on the card opens its details (it does not play).
    await t.tap(find.descendant(of: rows.first, matching: find.byType(Text)).first);
    expect(await waitFor(t, find.byType(SongDetailsPanel), timeout: const Duration(seconds: 3)),
        isTrue, reason: 'Tapping a search result did not open its details');
    final gotDetails = await waitFor(t, find.textContaining(' views'),
        timeout: const Duration(seconds: 20));
    await shot(b, t, '02b_details');
    report(gotDetails
        ? 'details: opened with views and likes'
        : 'details: opened, YouTube gave no details here');
    await t.tap(find.byType(SongDetailsPanel)); // fold it again
    await idle(t, const Duration(seconds: 1));
    expect(find.byType(SongDetailsPanel), findsNothing,
        reason: 'The details did not fold away');

    Finder playOn(int i) => find.descendant(
        of: find.byType(NoorSongRow).at(i), matching: find.byType(NoorPlayPauseButton));

    await t.tap(playOn(0));
    // Feedback must be quick: the card dips and "Loading…" appears.
    expect(await waitFor(t, find.text('Loading…'), timeout: const Duration(seconds: 3)),
        isTrue, reason: 'No loading feedback after tapping a song');
    await shot(b, t, '03_loading');

    final settled = await waitFor(
        t,
        find.byWidgetPredicate((w) =>
            w is Text &&
            (w.data ?? '').contains(RegExp(r'Retry in|Could not|refused|limiting|Skipped',
                caseSensitive: false))),
        timeout: const Duration(seconds: 60));
    final stillLoading = find.text('Loading…').evaluate().isNotEmpty;
    report(settled
        ? 'playback: YouTube refused here (see screenshot)'
        : stillLoading
            ? 'playback: still loading after 60 s'
            : 'playback: started');
    await shot(b, t, '04_after_play');

    // A second song from the same list must show the loading feedback too.
    if (find.byType(NoorSongRow).evaluate().length > 1) {
      await t.tap(playOn(1));
      expect(await waitFor(t, find.text('Loading…'), timeout: const Duration(seconds: 3)),
          isTrue, reason: 'No loading feedback for the second song');
      report('second song: loading shown');
      await idle(t, const Duration(seconds: 2));
    }
    expect(t.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
