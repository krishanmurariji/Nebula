import 'package:flutter_test/flutter_test.dart';
import 'package:noor/services/launch_requests.dart';

void main() {
  test(
      'coming back to Noor plays only when switched on, paused, and away a while',
      () {
    bool go({bool on = true, bool playing = false, int away = 120}) =>
        shouldPlayOnReturn(
            playOnOpen: on, playing: playing, away: Duration(seconds: away));
    expect(go(), isTrue); // e.g. Gemini: "open Noor"
    expect(go(on: false), isFalse);
    expect(go(playing: true), isFalse);
    expect(go(away: 5), isFalse); // a quick look at another app
    expect(go(away: 20), isTrue);
  });
}
