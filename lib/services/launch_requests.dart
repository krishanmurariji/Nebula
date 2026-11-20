import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'audio_handler.dart';

/// Settings key: start playing as soon as Noor opens (for a Bixby quick
/// command such as "Noor" → "Open Noor").
const kPlayOnOpenKey = 'noor_play_on_open';

/// What Noor was opened to play: a voice request ("play X on Noor"), a
/// home-screen shortcut, or (if switched on) simply carrying on with the
/// last song when the app opens.
class LaunchRequests {
  LaunchRequests._();

  static const channel = MethodChannel('noor/launch');

  /// Call once the audio service is up.
  static Future<void> start(NebulaAudioHandler handler) async {
    // Requests that arrive while Noor is already open.
    channel.setMethodCallHandler((call) async {
      if (call.method == 'play') {
        await handler.playFromSearch((call.arguments as String?) ?? '');
      }
      return null;
    });

    String? asked;
    try {
      asked = await channel.invokeMethod<String>('take');
    } catch (_) {/* not on Android / no activity */}
    if (asked != null) {
      nlog('[N] opened to play "$asked"');
      await handler.playFromSearch(asked);
      return;
    }

    try {
      final p = await SharedPreferences.getInstance();
      if ((p.getBool(kPlayOnOpenKey) ?? false) &&
          handler.currentSong == null &&
          !handler.playbackState.value.playing) {
        nlog('[N] play when opened: carrying on');
        await handler.playFromSearch('');
      }
    } catch (e) {
      nlog('[N] play when opened failed: $e');
    }
  }
}
