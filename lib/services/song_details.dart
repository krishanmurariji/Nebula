import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Extra facts about a song that YouTube knows: who uploaded it, when, how
/// popular it is, its description, and (for music uploads) song / artist /
/// album as the label tagged them.
class SongDetails {
  const SongDetails({
    required this.videoId,
    required this.channel,
    this.description = '',
    this.published,
    this.views,
    this.likes,
    this.duration,
    this.keywords = const [],
    this.songName,
    this.artistName,
    this.albumName,
  });

  final String videoId;
  final String channel;
  final String description;
  final DateTime? published;
  final int? views;
  final int? likes;
  final Duration? duration;
  final List<String> keywords;
  final String? songName;
  final String? artistName;
  final String? albumName;

  /// 1234 → "1.2K", 1500000 → "1.5M", 2300000000 → "2.3B".
  static String compactCount(int n) {
    String one(double v, String unit) {
      final s = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
      return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}$unit';
    }

    if (n >= 1000000000) return one(n / 1000000000, 'B');
    if (n >= 1000000) return one(n / 1000000, 'M');
    if (n >= 1000) return one(n / 1000, 'K');
    return '$n';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  /// "Mar 2013".
  static String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  static String clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  /// One short line for under the song title, e.g.
  /// "12M views · Mar 2013 · 4:22". Parts that are unknown are left out.
  String get metaLine => [
        if (views != null) '${compactCount(views!)} views',
        if (published != null) monthYear(published!),
        if (duration != null && duration! > Duration.zero) clock(duration!),
      ].join('  ·  ');

  /// Who made the song, read from the description lines labels usually
  /// write ("Singer: Arijit Singh", "Lyrics - Amitabh Bhattacharya",
  /// "Music by Pritam"), plus YouTube's own music tags. In a fixed order:
  /// Singer, Lyrics, Music, Starring, Album, Label. Only what is found.
  List<(String, String)> get credits {
    final found = parseCredits(description);
    if ((artistName ?? '').trim().isNotEmpty) {
      found.putIfAbsent('Singer', () => artistName!.trim());
    }
    if ((albumName ?? '').trim().isNotEmpty) {
      found.putIfAbsent('Album', () => albumName!.trim());
    }
    return [
      for (final k in creditOrder)
        if (found[k] != null) (k, found[k]!),
    ];
  }

  static const creditOrder = [
    'Singer',
    'Lyrics',
    'Music',
    'Starring',
    'Album',
    'Label'
  ];

  // Longest phrases first: "music director" must win over "music".
  static RegExp _key(String alts) =>
      RegExp('^(?:$alts)(?![A-Za-z])', caseSensitive: false);
  static final _creditKeys = <String, RegExp>{
    'Singer': _key(
        r'playback singers?|sung by|singers?|vocalists?|vocals?|voice|artists?'),
    'Lyrics': _key(
        r'lyrics written by|lyrics by|lyricists?|lyrics|written by|penned by|words|geet'),
    'Music': _key(
        r'music composed by|music directors?|music by|composed by|composers?|music|sangeet'),
    'Starring': _key(r'star cast|starring|cast|featuring|feat\.?|ft\.?'),
    'Album': _key(r'album|movie|film'),
    'Label': _key(r'record label|music label|music on|label'),
  };

  /// Reads "Key: value" style credit lines from a video description. The
  /// first line found for each kind wins; links and over-long values are
  /// ignored so a paragraph is never mistaken for a credit.
  static Map<String, String> parseCredits(String description) {
    final out = <String, String>{};
    for (var raw in description.split(RegExp(r'[\r\n]+'))) {
      // Drop leading bullets, emoji and other decoration.
      var line = raw.replaceFirst(RegExp(r'^[^A-Za-z]+'), '').trim();
      if (line.isEmpty || line.length > 120) continue;
      for (final e in _creditKeys.entries) {
        if (out.containsKey(e.key)) continue;
        final m = e.value.firstMatch(line);
        if (m == null) continue;
        var rest = line.substring(m.end).trim();
        // "Music by Pritam" has no separator; "Music : Pritam" has one.
        final sep = RegExp(r'^(?:[:：\-–—|=]+|by\b)\s*', caseSensitive: false)
            .firstMatch(rest);
        // "Music by Pritam", "Music on T-Series", "feat. X" need none.
        final k = m.group(0)!.toLowerCase();
        final open = k.endsWith('by') ||
            k.endsWith(' on') ||
            k.startsWith('feat') ||
            k.startsWith('ft');
        if (sep == null && !open) continue;
        if (sep != null) rest = rest.substring(sep.end).trim();
        rest = rest.replaceAll(RegExp(r'\s+'), ' ');
        if (rest.isEmpty ||
            rest.length > 70 ||
            rest.contains('http') ||
            rest.contains('www.')) {
          continue;
        }
        out[e.key] = rest;
        break;
      }
    }
    return out;
  }

  bool get hasMusicTags =>
      (songName ?? '').isNotEmpty ||
      (artistName ?? '').isNotEmpty ||
      (albumName ?? '').isNotEmpty;
}

/// Where details come from. A seam so tests never touch the network.
abstract class SongDetailsSource {
  Future<SongDetails?> fetch(String videoId);
}

/// Reads the public YouTube watch page. Failing (offline, rate limited, a
/// changed page) is normal and simply means "no extra details".
class YoutubeSongDetailsSource implements SongDetailsSource {
  YoutubeSongDetailsSource({YoutubeExplode? yt}) : _yt = yt;
  YoutubeExplode? _yt;

  @override
  Future<SongDetails?> fetch(String videoId) async {
    try {
      final yt = _yt ??= YoutubeExplode();
      final v =
          await yt.videos.get(videoId).timeout(const Duration(seconds: 12));
      final music = v.musicData.isNotEmpty ? v.musicData.first : null;
      return SongDetails(
        videoId: videoId,
        channel: v.author,
        description: v.description,
        published: v.publishDate ?? v.uploadDate,
        views: v.engagement.viewCount,
        likes: v.engagement.likeCount,
        duration: v.duration,
        keywords: v.keywords.take(14).toList(),
        songName: music?.song,
        artistName: music?.artist,
        albumName: music?.album,
      );
    } catch (_) {
      return null;
    }
  }
}

final songDetailsSourceProvider =
    Provider<SongDetailsSource>((ref) => YoutubeSongDetailsSource());

/// Details for one song, fetched once and kept for the session.
/// (A failed fetch gives null; invalidate the entry to try again.)
final songDetailsProvider =
    FutureProvider.family<SongDetails?, String>((ref, videoId) async {
  if (videoId.isEmpty) return null;
  return ref.read(songDetailsSourceProvider).fetch(videoId);
});
