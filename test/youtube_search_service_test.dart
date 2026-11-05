import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/models/song.dart';
import 'package:nebula_music_player/services/youtube_search_service.dart';

void main() {
  group('looksLikeSong', () {
    test('keeps normal songs and unknown durations', () {
      expect(looksLikeSong(duration: const Duration(minutes: 4), isLive: false), isTrue);
      expect(looksLikeSong(duration: null, isLive: false), isTrue);
      expect(looksLikeSong(duration: Duration.zero, isLive: false), isTrue);
    });

    test('drops live streams and very long mixes', () {
      expect(looksLikeSong(duration: const Duration(minutes: 4), isLive: true), isFalse);
      expect(looksLikeSong(duration: const Duration(hours: 3), isLive: false), isFalse);
    });
  });

  test('official-release detection still works', () {
    expect(Song.detectOfficial('Song (Official Video)', 'Someone'), isTrue);
    expect(Song.detectOfficial('Song', 'Artist - Topic'), isTrue);
    expect(Song.detectOfficial('Song cover', 'Random'), isFalse);
  });
}
