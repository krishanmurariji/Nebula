import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/song_details.dart';

class _Fake implements SongDetailsSource {
  int calls = 0;
  @override
  Future<SongDetails?> fetch(String videoId) async {
    calls++;
    return SongDetails(videoId: videoId, channel: 'Chan', views: 1234567);
  }
}

void main() {
  group('compactCount', () {
    test('small numbers stay as they are', () {
      expect(SongDetails.compactCount(0), '0');
      expect(SongDetails.compactCount(999), '999');
    });
    test('thousands, millions, billions', () {
      expect(SongDetails.compactCount(1000), '1K');
      expect(SongDetails.compactCount(1234), '1.2K');
      expect(SongDetails.compactCount(15300), '15.3K');
      expect(SongDetails.compactCount(1500000), '1.5M');
      expect(SongDetails.compactCount(123456789), '123M');
      expect(SongDetails.compactCount(2300000000), '2.3B');
    });
  });

  group('metaLine', () {
    test('joins what is known and skips the rest', () {
      final d = SongDetails(
          videoId: 'x',
          channel: 'c',
          views: 12000000,
          published: DateTime(2013, 3, 5),
          duration: const Duration(minutes: 4, seconds: 22));
      expect(d.metaLine, '12M views  ·  Mar 2013  ·  4:22');
      expect(const SongDetails(videoId: 'x', channel: 'c').metaLine, '');
      expect(
          const SongDetails(videoId: 'x', channel: 'c', views: 5).metaLine,
          '5 views');
    });
    test('long songs show hours', () {
      expect(SongDetails.clock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });
  });

  test('the provider asks the source once per song and caches the answer', () async {
    final src = _Fake();
    final c = ProviderContainer(overrides: [songDetailsSourceProvider.overrideWithValue(src)]);
    addTearDown(c.dispose);
    final sub = c.listen(songDetailsProvider('abc'), (_, __) {});
    final first = await c.read(songDetailsProvider('abc').future);
    final second = await c.read(songDetailsProvider('abc').future);
    expect(first?.channel, 'Chan');
    expect(identical(first, second), isTrue);
    expect(src.calls, 1);
    sub.close();
  });

  test('an empty id never calls the network', () async {
    final src = _Fake();
    final c = ProviderContainer(overrides: [songDetailsSourceProvider.overrideWithValue(src)]);
    addTearDown(c.dispose);
    expect(await c.read(songDetailsProvider('').future), isNull);
    expect(src.calls, 0);
  });
}
