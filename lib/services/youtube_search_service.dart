import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';
import 'app_log.dart';
import 'playback_failure.dart';
import 'search_ranking.dart';

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

  /// Whether the ranked list already has a trustworthy result near the top.
  /// If not, a second page of results is fetched in the hope the genuine
  /// upload is on it.
  @visibleForTesting
  static bool isConfident(List<RankedCandidate> ranked) =>
      ranked.take(3).any((r) => r.official);

  static List<SearchCandidate> _toCandidates(Iterable<Video> videos) => [
        for (final v in videos)
          if (looksLikeSong(duration: v.duration, isLive: v.isLive) &&
              v.id.value.isNotEmpty)
            SearchCandidate(
              videoId: v.id.value,
              title: v.title,
              author: v.author,
              thumbnailUrl: v.thumbnails.highResUrl,
              views: v.engagement.viewCount,
              duration: v.duration,
              isLive: v.isLive,
            ),
      ];

  Future<List<Song>> searchSongs(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    Object? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        // The query is sent as typed: adding "music" used to attract fan
        // channels with "Music" in their name.
        final first = await _yt.search.search(q).timeout(const Duration(seconds: 15));
        var candidates = _toCandidates(first);
        var ranked = rankCandidates(q, candidates);

        if (!isConfident(ranked)) {
          try {
            final more = await first.nextPage().timeout(const Duration(seconds: 10));
            if (more != null) {
              final seen = {for (final c in candidates) c.videoId};
              candidates = [
                ...candidates,
                ..._toCandidates(more).where((c) => !seen.contains(c.videoId)),
              ];
              ranked = rankCandidates(q, candidates);
            }
          } catch (e) {
            nlog('[N] search: second page skipped: $e');
          }
        }

        for (final r in ranked.take(5)) {
          nlog('[N] rank $r');
        }
        return [
          for (final r in ranked.take(30))
            Song(
              videoId: r.candidate.videoId,
              title: r.candidate.title,
              artist: r.candidate.author,
              thumbnailUrl: r.candidate.thumbnailUrl,
              isOfficial: r.official,
            ),
        ];
      } catch (e) {
        last = e;
        nlog('[N] search attempt ${attempt + 1} failed: $e');
        if (classifyPlaybackError(e) == FailureKind.rateLimited) {
          throw const SearchException(
              'YouTube is limiting requests from your network. '
              'Please wait a few minutes and try again.');
        }
        if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    throw SearchException(last is TimeoutException
        ? 'Search timed out. Check your connection and try again.'
        : 'Search failed. Check your connection and try again.');
  }
}
