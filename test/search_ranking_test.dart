import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/search_ranking.dart';
import 'package:nebula_music_player/services/youtube_search_service.dart';

SearchCandidate c(String id, String author, String title, int views, String mmss,
    {bool live = false}) {
  final p = mmss.split(':').map(int.parse).toList();
  return SearchCandidate(
    videoId: id,
    title: title,
    author: author,
    views: views,
    duration: Duration(minutes: p[0], seconds: p[1]),
    isLive: live,
  );
}

List<String> ids(List<RankedCandidate> r) => [for (final e in r) e.candidate.videoId];
RankedCandidate pick(List<RankedCandidate> r, String id) =>
    r.firstWhere((e) => e.candidate.videoId == id);
int pos(List<RankedCandidate> r, String id) => ids(r).indexOf(id);

void main() {
  group('"king shit" (the results from the real screenshot)', () {
    // Deliberately in an order where the genuine upload is LAST.
    final results = [
      c('lyrics', 'ChillPind', 'Shubh - King Shit (Lyrics)', 3000000, '3:00'),
      c('d8', '8D Active Music', 'Shubh - King Shit (8D AUDIO)', 1200000, '3:00'),
      c('fake', 'RAHUL BEAT', 'King Shit - Shubh ( Official Video ) King Shit', 400000, '3:10'),
      c('slowed', 'Tune Tube', 'Shubh - King Shit🔥 ✨🦁|| Slowed Reverb', 800000, '3:00'),
      c('dhol', 'DJ SSS NEXTLEVEL ROADSHOW', 'King Shit (Dhol Remix) - Shubh x DJ SSS x NextLevel', 200000, '4:00'),
      c('jass', 'Dj Jass Beatzz', 'King Shit ( Dhol Remix ) | Shubh | Leo | Dj Jass Beatzz | New Punjabi Songs 2023', 2000000, '3:30'),
      c('real', 'SHUBH', 'Shubh - King Shit (Official Audio)', 95000000, '3:00'),
    ];
    final ranked = rankCandidates('shubh king shit', results);

    test('the genuine upload is first', () {
      expect(ids(ranked).first, 'real', reason: ranked.join('\n'));
      expect(pick(ranked, 'real').official, isTrue);
    });

    test('a fan upload that writes "Official Video" in the title is NOT official', () {
      expect(pick(ranked, 'fake').official, isFalse);
      expect(pos(ranked, 'fake'), greaterThan(0));
      expect(pick(ranked, 'fake').reasons.join(' '), contains('not trusted'));
    });

    test('edits (8D, slowed+reverb, remixes) end up below the genuine one and the lyrics video', () {
      final real = pos(ranked, 'real');
      for (final edit in ['d8', 'slowed', 'dhol', 'jass']) {
        expect(pos(ranked, edit), greaterThan(real), reason: edit);
      }
      expect(pos(ranked, 'lyrics'), lessThan(pos(ranked, 'd8')));
      expect(pos(ranked, 'lyrics'), lessThan(pos(ranked, 'slowed')));
    });

    test('only the genuine one is flagged official', () {
      expect([for (final r in ranked) if (r.official) r.candidate.videoId], ['real']);
    });

    test('every score has human-readable reasons', () {
      expect(pick(ranked, 'd8').reasons.join(' '), contains('8d'));
      expect(pick(ranked, 'slowed').reasons.join(' '), anyOf(contains('slowed'), contains('reverb')));
    });
  });

  group('Topic channels and record labels', () {
    final results = [
      c('lyr', 'Lyrical Lover', 'Tum Hi Ho lyrics', 10000000, '4:22'),
      c('slow', 'Sad Status', 'Tum Hi Ho Slowed + Reverb', 5000000, '4:00'),
      c('tseries', 'T-Series', 'Tum Hi Ho Full Video Song | Aashiqui 2', 1400000000, '4:22'),
      c('topic', 'Arijit Singh - Topic', 'Tum Hi Ho', 40000000, '4:22'),
      c('cover', 'Singer Anna', 'Tum Hi Ho (Cover)', 2000000, '3:50'),
    ];
    final ranked = rankCandidates('tum hi ho', results);

    test('the Topic upload and the label upload are the top two, both official', () {
      expect(ids(ranked).take(2).toSet(), {'tseries', 'topic'}, reason: ranked.join('\n'));
      expect(pick(ranked, 'topic').official, isTrue);
      expect(pick(ranked, 'tseries').official, isTrue);
    });

    test('lyrics, slowed and covers are below both', () {
      for (final fan in ['lyr', 'slow', 'cover']) {
        expect(pos(ranked, fan), greaterThan(1), reason: fan);
        expect(pick(ranked, fan).official, isFalse, reason: fan);
      }
    });
  });

  test('identical titles: the trusted channel beats the random uploader', () {
    final ranked = rankCandidates('some song', [
      c('rand', 'RandomUser123', 'Some Song (Official Video)', 900000, '3:30'),
      c('label', 'T-Series', 'Some Song (Official Video)', 900000, '3:30'),
    ]);
    expect(ids(ranked), ['label', 'rand']);
    expect(pick(ranked, 'label').official, isTrue);
    expect(pick(ranked, 'rand').official, isFalse);
  });

  group('when you ask for a remix, you get remixes', () {
    final results = [
      c('real', 'SHUBH', 'Shubh - King Shit (Official Audio)', 95000000, '3:00'),
      c('d8', '8D Active Music', 'Shubh - King Shit (8D AUDIO)', 1200000, '3:00'),
      c('dhol', 'DJ SSS NEXTLEVEL ROADSHOW', 'King Shit (Dhol Remix) - Shubh x DJ SSS', 3000000, '4:00'),
      c('slowed', 'Tune Tube', 'Shubh - King Shit Slowed Reverb', 800000, '3:00'),
    ];

    test('the remix is not penalised and rises above the other edits and fan-edit uploads', () {
      final ranked = rankCandidates('king shit remix', results);
      expect(pos(ranked, 'dhol'), lessThan(pos(ranked, 'd8')));
      expect(pos(ranked, 'dhol'), lessThan(pos(ranked, 'slowed')));
      expect(pick(ranked, 'dhol').reasons.join(' '), contains('what you asked for'));
    });

    test('without asking for it, the same remix is pushed down', () {
      final plain = rankCandidates('king shit', results);
      expect(pos(plain, 'dhol'), greaterThan(pos(plain, 'real')));
    });
  });

  test('lyrics requested → lyric videos are welcome', () {
    final r = rankCandidates('king shit lyrics', [
      c('real', 'SHUBH', 'Shubh - King Shit (Official Audio)', 95000000, '3:00'),
      c('lyr', 'ChillPind', 'Shubh - King Shit (Lyrics)', 3000000, '3:00'),
    ]);
    expect(r.firstWhere((e) => e.candidate.videoId == 'lyr').reasons.join(' '),
        isNot(contains('fan-edit markers')));
  });

  group('shape of the video', () {
    test('a 30-second short and a live stream rank below a normal song', () {
      final r = rankCandidates('song', [
        c('short', 'Chan', 'Song', 1000000, '0:30'),
        c('live', 'Chan', 'Song', 1000000, '3:00', live: true),
        c('normal', 'Chan', 'Song', 1000000, '3:00'),
      ]);
      expect(ids(r).first, 'normal');
    });

    test('emoji/hashtag clutter is a small penalty, other scripts are not clutter', () {
      final r = rankCandidates('x', [
        c('emoji', 'Chan', 'Song 🔥🔥✨🦁 #a #b', 1000000, '3:00'),
        c('gurmukhi', 'Chan', 'ਦੋ ਗੱਲਾਂ - ਗੁਰਨਾਮ ਭੁੱਲਰ', 1000000, '3:00'),
        c('hindi', 'Chan', 'तुम ही हो', 1000000, '3:00'),
      ]);
      expect(pick(r, 'emoji').reasons.join(' '), contains('clutter'));
      expect(pick(r, 'gurmukhi').reasons.join(' '), isNot(contains('clutter')));
      expect(pick(r, 'hindi').reasons.join(' '), isNot(contains('clutter')));
    });
  });

  group('robustness', () {
    test('empty input', () => expect(rankCandidates('x', const []), isEmpty));

    test('missing views and durations never throw', () {
      final r = rankCandidates('x', const [
        SearchCandidate(videoId: 'a', title: 'A', author: ''),
        SearchCandidate(videoId: 'b', title: '', author: 'B', views: 0),
      ]);
      expect(r.length, 2);
    });

    test('empty / symbol-only / very long queries', () {
      final items = [c('a', 'A', 'Some title', 10, '3:00')];
      for (final q in ['', '   ', '!!!', '🔥🔥', 'x' * 5000]) {
        expect(rankCandidates(q, items).length, 1, reason: q.length > 20 ? 'long' : q);
      }
    });

    test('ties keep the original (YouTube) order', () {
      final r = rankCandidates('x', [for (var i = 0; i < 5; i++) c('id$i', 'Chan', 'Same Title', 1000, '3:00')]);
      expect(ids(r), ['id0', 'id1', 'id2', 'id3', 'id4']);
    });

    test('deterministic and a permutation of the input (500 random lists)', () {
      final rnd = Random(7);
      const words = ['song', 'official', 'audio', 'remix', 'lyrics', '8d', 'live', 'slowed', 'cover', 'x', 'ਗੀਤ', '🔥'];
      const chans = ['T-Series', 'Foo - Topic', 'RandomFan', 'DJ Bar', 'ArtistName', 'VEVO'];
      for (var n = 0; n < 500; n++) {
        final items = [
          for (var i = 0; i < rnd.nextInt(30); i++)
            SearchCandidate(
              videoId: 'v$i',
              title: [for (var k = 0; k < 1 + rnd.nextInt(6); k++) words[rnd.nextInt(words.length)]].join(' '),
              author: chans[rnd.nextInt(chans.length)],
              views: rnd.nextBool() ? null : rnd.nextInt(1 << 30),
              duration: rnd.nextBool() ? null : Duration(seconds: rnd.nextInt(2000)),
              isLive: rnd.nextInt(10) == 0,
            ),
        ];
        final a = rankCandidates('official song', items);
        final b = rankCandidates('official song', items);
        expect(ids(a), ids(b));
        expect(ids(a).toSet(), {for (final i in items) i.videoId});
        expect(a.length, items.length);
        for (final r in a) {
          expect(r.score.isFinite, isTrue);
        }
      }
    });
  });

  group('second page is fetched only when no trusted result is near the top', () {
    test('confident when an official result is in the top 3', () {
      final r = rankCandidates('shubh king shit', [
        c('real', 'SHUBH', 'Shubh - King Shit (Official Audio)', 95000000, '3:00'),
        c('lyr', 'ChillPind', 'Shubh - King Shit (Lyrics)', 3000000, '3:00'),
      ]);
      expect(YoutubeSearchService.isConfident(r), isTrue);
    });

    test('not confident when only fan uploads were found', () {
      final r = rankCandidates('king shit', [
        c('a', 'Fan A', 'King Shit 8D', 1000, '3:00'),
        c('b', 'Fan B', 'King Shit slowed', 1000, '3:00'),
        c('d', 'Fan C', 'King Shit remix', 1000, '3:00'),
      ]);
      expect(YoutubeSearchService.isConfident(r), isFalse);
    });
  });
}
