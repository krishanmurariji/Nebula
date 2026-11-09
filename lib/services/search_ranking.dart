import 'dart:math';

/// What the ranking needs to know about one search result.
class SearchCandidate {
  const SearchCandidate({
    required this.videoId,
    required this.title,
    required this.author,
    this.thumbnailUrl = '',
    this.views,
    this.duration,
    this.isLive = false,
  });

  final String videoId;
  final String title;

  /// The uploading channel's name.
  final String author;
  final String thumbnailUrl;
  final int? views;
  final Duration? duration;
  final bool isLive;
}

class RankedCandidate {
  const RankedCandidate(this.candidate, this.score, this.official, this.reasons);
  final SearchCandidate candidate;
  final double score;

  /// True only when the channel can be trusted (Topic / VEVO / a known label /
  /// the artist's own channel). A title that merely says "Official Video" does
  /// NOT count, because anyone can write that.
  final bool official;
  final List<String> reasons;

  @override
  String toString() =>
      '${score.toStringAsFixed(0).padLeft(4)} ${official ? 'OFFICIAL' : '        '} '
      '${candidate.author} | ${candidate.title}';
}

/// Record labels and music companies whose channels are the genuine source of
/// a release. Matched against the normalised channel name.
const Set<String> kKnownLabels = {
  't series', 't series regional', 'tseries', 'zee music company',
  'zee music', 'sony music india', 'sony music', 'saregama music',
  'saregama', 'tips official', 'tips music', 'speed records', 'times music',
  'lahari music', 'white hill music', 'desi melodies', 'geet mp3',
  'rhythm boyz', 'humble music', 'brown studios', 'sidhu moose wala',
  'universal music', 'warner music', 'atlantic records', 'columbia records',
  'republic records', 'rca records', 'interscope records', 'def jam recordings',
  'capitol records', 'island records', 'emi', 'aditya music', 'lahari',
  'think music india', 'junglee music', 'eros now music', 'yrf',
  'vevo', 'hybe labels', 'sm town', 'jyp entertainment', 'yg entertainment',
};

// Modifiers that mark a fan edit / derivative. Penalised unless the user asked
// for them. Matched as whole words or phrases on the normalised title.
const Map<String, double> _derivativePenalty = {
  'lyrics': 22, 'lyric': 22, 'lyrical': 22,
  '8d': 45, '16d': 45, '8d audio': 45, '3d audio': 40,
  'slowed': 45, 'reverb': 40, 'sped up': 45, 'speed up': 45, 'nightcore': 45,
  'bass boosted': 40, 'bass boost': 40, 'bassboosted': 40,
  'remix': 38, 'remixed': 38, 'mashup': 40, 'mix': 18, 'dj': 18,
  'cover': 40, 'karaoke': 45, 'instrumental': 30, 'reaction': 50,
  'status': 35, 'whatsapp': 35, 'ringtone': 40, 'jukebox': 30,
  'lofi': 30, 'lo fi': 30, 'live': 12, 'concert': 12, 'acoustic': 10,
  'tutorial': 40, 'lesson': 40, 'how to': 40, 'trailer': 30, 'teaser': 25,
  'shorts': 25, 'edit': 20, 'fan made': 30, 'fanmade': 30, 'dance': 15,
  'choreography': 25, 'gameplay': 40, 'full album': 30, 'compilation': 30,
  'playlist': 30, 'nonstop': 25, 'non stop': 25, 'loop': 25, 'hour': 25,
  'hours': 25, 'reupload': 30, 'reuploaded': 30, 'copyright free': 30,
  'no copyright': 30, 'dhol': 15, 'extended': 15,
};

const List<String> _fanChannelWords = [
  'lyrics', 'lyrical', 'fan', 'fans', 'edits', 'edit', 'status', 'whatsapp',
  'remix', 'remixes', 'reaction', 'covers', 'cover', 'dj', 'bass', '8d',
  'slowed', 'nightcore', 'lofi', 'beat', 'beats', 'tune tube', 'roadshow',
];

const Map<String, double> _officialTitleBonus = {
  'official audio': 25, 'official video': 22, 'official music video': 25,
  'official mv': 22, 'official lyric video': 10, 'official visualizer': 15,
  'official video song': 22, 'official song': 20,
};

String normalizeForRanking(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _containsPhrase(String normalizedText, String phrase) {
  if (phrase.isEmpty) return false;
  return ' $normalizedText '.contains(' $phrase ');
}

/// Ranks [items] for [query], best first. Pure and deterministic: the same
/// input always gives the same order (ties keep the original order).
List<RankedCandidate> rankCandidates(
    String query, List<SearchCandidate> items) {
  if (items.isEmpty) return const [];
  final q = normalizeForRanking(query);
  final qTokens = q.split(' ').where((t) => t.isNotEmpty).toList();

  final maxViews = items.map((e) => e.views ?? 0).fold<int>(1, max);
  final normTitles = [for (final i in items) normalizeForRanking(i.title)];

  final scored = <RankedCandidate>[];
  for (var idx = 0; idx < items.length; idx++) {
    final c = items[idx];
    final title = normTitles[idx];
    final author = normalizeForRanking(c.author);
    var score = 0.0;
    final why = <String>[];
    void add(double d, String reason) {
      score += d;
      why.add('${d >= 0 ? '+' : ''}${d.toStringAsFixed(0)} $reason');
    }

    // ── Who uploaded it ────────────────────────────────────────────────────
    var trusted = false;
    if (c.author.toLowerCase().trim().endsWith('- topic')) {
      add(55, 'Topic channel (auto-generated from the label)');
      trusted = true;
    }
    if (author.contains('vevo')) {
      add(45, 'VEVO');
      trusted = true;
    }
    if (kKnownLabels.contains(author)) {
      add(40, 'known label');
      trusted = true;
    }
    // A channel named like the artist: it is in the query, or most results
    // talk about it ("Shubh" appears in the titles of most results).
    if (author.length >= 3) {
      final inQuery = _containsPhrase(q, author);
      final inTitles = [
        for (var j = 0; j < items.length; j++)
          if (j != idx && _containsPhrase(normTitles[j], author)) 1
      ].length;
      final share = items.length > 1 ? inTitles / (items.length - 1) : 0.0;
      if (inQuery || (inTitles >= 2 && share >= 0.3)) {
        add(28, 'channel is named like the artist');
        trusted = true;
      }
    }
    final fanHits = _fanChannelWords.where((w) => _containsPhrase(author, w)).length;
    if (fanHits > 0) add(-min<double>(35, 18.0 * fanHits), 'fan/edit-style channel name');

    // ── Title says "official" (only believed from a trusted channel) ──────
    var claimsOfficial = false;
    for (final e in _officialTitleBonus.entries) {
      if (_containsPhrase(title, e.key)) {
        claimsOfficial = true;
        add(trusted ? e.value : e.value * 0.2,
            trusted ? 'title: ${e.key}' : 'title says "${e.key}" but the channel is not trusted');
        break;
      }
    }

    // ── Derivative / fan-edit markers, unless the user asked for them ──────
    final matched = <String>{};
    var penalty = 0.0;
    for (final e in _derivativePenalty.entries) {
      if (_containsPhrase(q, e.key)) continue; // the user wants this kind
      if (_containsPhrase(title, e.key)) {
        // "lyric" next to "official" is a label's lyric video: mild.
        final p = (e.key.startsWith('lyric') && claimsOfficial) ? 6.0 : e.value;
        matched.add(e.key);
        penalty += p;
      }
    }
    if (penalty > 0) add(-min<double>(80, penalty), 'fan-edit markers: ${matched.join(', ')}');
    // The user explicitly asked for a modifier: reward titles that have it.
    for (final key in _derivativePenalty.keys) {
      if (_containsPhrase(q, key) && _containsPhrase(title, key)) {
        add(18, 'matches what you asked for ("$key")');
        break;
      }
    }

    // ── Popularity, relative to the other results ──────────────────────────
    final v = c.views ?? 0;
    if (v > 0) {
      add(25 * pow(v / maxViews, 0.35).toDouble(), 'views');
    }

    // ── Relevance to what was typed ────────────────────────────────────────
    if (qTokens.isNotEmpty) {
      final hay = '$title $author';
      final hit = qTokens.where((t) => _containsPhrase(hay, t) || hay.contains(t)).length;
      add(20.0 * hit / qTokens.length, 'matches the query');
      if (qTokens.every((t) => title.contains(t))) add(8, 'title has every query word');
    }

    // ── Shape of the video ─────────────────────────────────────────────────
    final d = c.duration;
    if (d != null && d > Duration.zero) {
      if (d < const Duration(seconds: 45)) {
        add(-30, 'under 45 s (a short)');
      } else if (d < const Duration(seconds: 90)) {
        add(-10, 'very short');
      } else if (d > const Duration(minutes: 12)) {
        add(-15, 'over 12 minutes');
      }
    }
    if (c.isLive) add(-60, 'live stream');
    final symbols = c.title.runes.where((r) => r > 0x2000 && r < 0x1FFFF && !_isLetterish(r)).length;
    if (symbols >= 3) add(-8, 'emoji/symbol clutter');
    if ('#'.allMatches(c.title).length >= 2) add(-6, 'hashtags');

    final official = trusted &&
        (c.author.toLowerCase().trim().endsWith('- topic') ||
            author.contains('vevo') ||
            kKnownLabels.contains(author) ||
            claimsOfficial ||
            penalty == 0);
    scored.add(RankedCandidate(c, score, official, why));
  }

  // Stable sort: higher score first; ties keep YouTube's original order.
  final order = List<int>.generate(scored.length, (i) => i)
    ..sort((a, b) {
      final byScore = scored[b].score.compareTo(scored[a].score);
      return byScore != 0 ? byScore : a.compareTo(b);
    });
  return [for (final i in order) scored[i]];
}

// Letters of non-Latin scripts (Hindi, Punjabi, Arabic, CJK …) are not
// "symbol clutter".
bool _isLetterish(int rune) {
  final s = String.fromCharCode(rune);
  return RegExp(r'\p{L}|\p{N}', unicode: true).hasMatch(s);
}
