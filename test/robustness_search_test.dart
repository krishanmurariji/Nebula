import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/models/song.dart';
import 'package:nebula_music_player/providers/search_provider.dart';
import 'package:nebula_music_player/services/youtube_search_service.dart';

class FakeSearch implements YoutubeSearchService {
  final Map<String, Completer<List<Song>>> pending = {};
  final List<String> queries = [];

  @override
  Future<List<Song>> searchSongs(String query) {
    queries.add(query);
    return (pending[query] = Completer<List<Song>>()).future;
  }
}

Song s(String id) => Song(videoId: id, title: id, artist: '', thumbnailUrl: '');

void main() {
  late FakeSearch fake;
  late ProviderContainer c;

  setUp(() {
    fake = FakeSearch();
    c = ProviderContainer(overrides: [searchServiceProvider.overrideWithValue(fake)]);
    addTearDown(c.dispose);
  });

  test('a slow older search can never overwrite a newer one', () async {
    final n = c.read(searchProvider.notifier);
    final first = n.search('first');
    final second = n.search('second');

    fake.pending['second']!.complete([s('NEW_RESULT_1')]);
    await second;
    fake.pending['first']!.complete([s('OLD_RESULT_1')]); // arrives late
    await first;

    final state = c.read(searchProvider);
    expect(state.results.single.videoId, 'NEW_RESULT_1');
    expect(state.query, 'second');
    expect(state.status, SearchStatus.loaded);
  });

  test('an older search that FAILS late does not replace newer results with an error', () async {
    final n = c.read(searchProvider.notifier);
    final first = n.search('first');
    final second = n.search('second');
    fake.pending['second']!.complete([s('GOOD_RESULT_1')]);
    await second;
    fake.pending['first']!.completeError(Exception('late failure'));
    await first;
    expect(c.read(searchProvider).status, SearchStatus.loaded);
  });

  test('failures show a friendly message, never a raw exception', () async {
    final n = c.read(searchProvider.notifier);
    final f = n.search('boom');
    fake.pending['boom']!.completeError(Exception('SocketException: secret.host:443 refused'));
    await f;
    final st = c.read(searchProvider);
    expect(st.status, SearchStatus.error);
    expect(st.error, isNot(contains('secret.host')));
    expect(st.error, contains('Search failed'));
  });

  test('SearchException messages pass through', () async {
    final n = c.read(searchProvider.notifier);
    final f = n.search('t');
    fake.pending['t']!.completeError(const SearchException('Search timed out.'));
    await f;
    expect(c.read(searchProvider).error, 'Search timed out.');
  });

  test('clear() cancels the effect of an in-flight search', () async {
    final n = c.read(searchProvider.notifier);
    final f = n.search('x');
    n.clear();
    fake.pending['x']!.complete([s('LATE_RESULT_1')]);
    await f;
    expect(c.read(searchProvider).status, SearchStatus.idle);
    expect(c.read(searchProvider).results, isEmpty);
  });

  test('empty / whitespace-only queries reset instead of searching', () async {
    final n = c.read(searchProvider.notifier);
    await n.search('   \n\t ');
    expect(fake.queries, isEmpty);
    expect(c.read(searchProvider).status, SearchStatus.idle);
  });

  group('sanitizeQuery', () {
    test('strips control characters and collapses whitespace', () {
      expect(sanitizeQuery('  hello\u0000\u0007   wor\nld\t'), 'hello wor ld');
    });

    test('caps absurdly long input', () {
      expect(sanitizeQuery('a' * 100000).length, 150);
    });

    test('keeps unicode (other languages / emoji)', () {
      expect(sanitizeQuery('दो गल्लां 🎵'), 'दो गल्लां 🎵');
    });
  });

  test('50 rapid searches: exactly the last one wins', () async {
    final n = c.read(searchProvider.notifier);
    final futures = [for (var i = 0; i < 50; i++) n.search('q$i')];
    // complete in random-ish (reverse) order
    for (var i = 49; i >= 0; i--) {
      fake.pending['q$i']!.complete([s('RESULT_FOR_$i')]);
    }
    await Future.wait(futures);
    expect(c.read(searchProvider).results.single.videoId, 'RESULT_FOR_49');
  });
}
