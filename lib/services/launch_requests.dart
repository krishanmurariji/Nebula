import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'audio_handler.dart';

/// Settings key: start playing as soon as Noor opens (for a Bixby quick
/// command such as "Noor" → "Open Noor", or Gemini's "open Noor").
const kPlayOnOpenKey = 'noor_play_on_open';

/// Coming back to Noor sooner than this after leaving it (a quick look at
/// another app) does not start the music; that is switching, not opening.
const kReturnCountsAsOpening = Duration(seconds: 20);

/// Whether Noor, brought back to the front after [away], should start
/// playing by itself.
bool shouldPlayOnReturn({
  required bool playOnOpen,
  required bool playing,
  required Duration away,
}) =>
    playOnOpen && !playing && away >= kReturnCountsAsOpening;

/// What Noor was opened to play: a voice request ("play X on Noor"), a
/// home-screen shortcut, or (if switched on) simply carrying on with the
/// last song when the app opens or comes back to the front.
class LaunchRequests {
  LaunchRequests._();

  static const channel = MethodChannel('noor/launch');

  static Future<bool> _playOnOpen() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(kPlayOnOpenKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Carry on: the loaded song if there is one, else the last one played.
  static Future<void> _carryOn(NebulaAudioHandler handler) async {
    if (handler.currentSong != null) {
      await handler.play();
    } else {
      await handler.playFromSearch('');
    }
  }

  /// Call once the audio service is up.
  static Future<void> start(NebulaAudioHandler handler) async {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        // A request that arrives while Noor is already open.
        case 'play':
          await handler.playFromSearch((call.arguments as String?) ?? '');
        // Brought back to the front with no request.
        case 'opened':
          final args = (call.arguments as Map?) ?? const {};
          final away = Duration(seconds: (args['away'] as num?)?.toInt() ?? 0);
          final playing = handler.playbackState.value.playing;
          final on = await _playOnOpen();
          nlog('[N] back in front after ${away.inSeconds}s (${args['how']}); '
              'play when opened: $on, playing: $playing');
          if (shouldPlayOnReturn(
              playOnOpen: on, playing: playing, away: away)) {
            await _carryOn(handler);
          }
      }
      return null;
    });

    String? asked;
    try {
      nlog('[N] opened: ${await channel.invokeMethod<String>('how')}');
      asked = await channel.invokeMethod<String>('take');
    } catch (_) {/* not on Android / no activity */}
    if (asked != null) {
      nlog('[N] opened to play "$asked"');
      await handler.playFromSearch(asked);
      return;
    }

    try {
      if (await _playOnOpen() && !handler.playbackState.value.playing) {
        nlog('[N] play when opened: carrying on');
        await _carryOn(handler);
      }
    } catch (e) {
      nlog('[N] play when opened failed: $e');
    }
  }
}
