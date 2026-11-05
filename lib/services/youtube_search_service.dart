import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';
import 'app_log.dart';

/// Thrown with a message that is safe to show to the user.
class SearchException implements Exception {
  final String message;
  const SearchException(this.message);
  @override
  String toString() => message;
}

/// Whether a search hit looks like a song rather than a live stream or a
/// multi-hour mix.
bool looksLikeSong({required Duration? duration, required bool isLive}) {
  if (isLive) return false;
  if (duration == null || duration == Duration.zero) return true; // unknown
  return duration <= const Duration(minutes: 20);
}

/// Keyless YouTube search (no API key, no daily quota).
class YoutubeSearchService {
  YoutubeSearchService({YoutubeExplode? yt}) : _yt = yt ?? YoutubeExplode();

  final YoutubeExplode _yt;

  Future<List<Song>> searchSongs(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final videos =
            await _yt.search.search('$q music').timeout(const Duration(seconds: 15));
        return videos
            .where((v) => looksLikeSong(duration: v.duration, isLive: v.isLive))
            .map((v) => Song(
                  videoId: v.id.value,
                  title: v.title,
                  artist: v.author,
                  thumbnailUrl: v.thumbnails.highResUrl,
                  isOfficial: Song.detectOfficial(v.title, v.author),
                ))
            .where((s) => s.videoId.isNotEmpty)
            .toList();
      } catch (e) {
        last = e;
        nlog('[N] search attempt ${attempt + 1} failed: $e');
        if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    throw SearchException(last is TimeoutException
        ? 'Search timed out. Check your connection and try again.'
        : 'Search failed. Check your connection and try again.');
  }
}
