import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/song.dart';
import '../services/app_log.dart';

/// Whether Noor may read the phone's music files.
enum LocalAccess { unknown, granted, denied, blocked, unsupported }

class LocalMusicState {
  const LocalMusicState({this.access = LocalAccess.unknown, this.songs = const []});
  final LocalAccess access;
  final List<Song> songs;
}

/// Talks to MainActivity.kt over this channel.
const MethodChannel localMusicChannel = MethodChannel('noor/local_music');

/// Songs stored on the phone, read from Android's media library.
///
/// Nothing is asked at start-up: if access was already given the list is
/// read quietly; otherwise My Music shows a button that calls [requestAccess].
class LocalMusicNotifier extends StateNotifier<LocalMusicState> {
  LocalMusicNotifier({bool autoLoad = true}) : super(const LocalMusicState()) {
    if (autoLoad) _init();
  }

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _init() async {
    if (!_android) {
      state = const LocalMusicState(access: LocalAccess.unsupported);
      return;
    }
    try {
      if (await _granted()) await refresh();
    } catch (e) {
      nlog('[N] local music: status check failed: $e');
    }
  }

  /// READ_MEDIA_AUDIO on Android 13+, READ_EXTERNAL_STORAGE before that.
  static Future<bool> _granted() async =>
      await Permission.audio.isGranted || await Permission.storage.isGranted;

  /// Asks for access (once Android has blocked the prompt, opens the app's
  /// settings instead) and reads the library when given.
  Future<void> requestAccess() async {
    if (!_android) return;
    try {
      if (state.access == LocalAccess.blocked) {
        await openAppSettings();
        return;
      }
      final results = await [Permission.audio, Permission.storage].request();
      if (results.values.any((s) => s.isGranted || s.isLimited)) {
        await refresh();
        return;
      }
      final blocked = results.values.any((s) => s.isPermanentlyDenied);
      if (mounted) {
        state = LocalMusicState(
            access: blocked ? LocalAccess.blocked : LocalAccess.denied);
      }
    } catch (e) {
      nlog('[N] local music: permission request failed: $e');
      if (mounted) state = const LocalMusicState(access: LocalAccess.denied);
    }
  }

  /// Reads the phone's music again.
  Future<void> refresh() async {
    try {
      final raw = await localMusicChannel.invokeListMethod<Map>('list') ?? [];
      final songs = [
        for (final m in raw)
          if (m['id'] is num && m['uri'] is String)
            Song(
              videoId: 'local_${m['id']}',
              title: (m['title'] as String?)?.trim().isNotEmpty == true
                  ? m['title'] as String
                  : 'Unknown',
              artist: (m['artist'] as String?) ?? '',
              thumbnailUrl: 'localart://${m['id']}',
              localUri: m['uri'] as String,
            ),
      ];
      nlog('[N] local music: ${songs.length} songs on the phone');
      if (mounted) {
        state = LocalMusicState(access: LocalAccess.granted, songs: songs);
      }
    } catch (e) {
      nlog('[N] local music: could not read the library: $e');
      if (mounted) {
        state = LocalMusicState(access: LocalAccess.granted, songs: state.songs);
      }
    }
  }
}

final localMusicProvider =
    StateNotifierProvider<LocalMusicNotifier, LocalMusicState>(
        (ref) => LocalMusicNotifier());

/// Album art of a phone song (a small JPEG), cached in memory.
final _artCache = <String, Uint8List?>{};

Future<Uint8List?> localArtwork(String url) async {
  if (_artCache.containsKey(url)) return _artCache[url];
  final id = int.tryParse(url.replaceFirst('localart://', ''));
  Uint8List? bytes;
  if (id != null) {
    try {
      bytes = await localMusicChannel.invokeMethod<Uint8List>('art', {'id': id});
    } catch (_) {/* no art */}
  }
  if (_artCache.length > 300) _artCache.clear();
  return _artCache[url] = bytes;
}
