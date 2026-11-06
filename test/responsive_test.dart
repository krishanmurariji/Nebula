import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/app.dart';
import 'package:nebula_music_player/models/song.dart';
import 'package:nebula_music_player/widgets/song_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A spread of real device sizes (logical pixels) and font scales.
const sizes = <String, Size>{
  'tiny 320x480': Size(320, 480),
  'small 360x640': Size(360, 640),
  'Galaxy S24 411x915': Size(411, 915),
  'big phone 430x932': Size(430, 932),
  'foldable cover 280x653': Size(280, 653),
  'tablet portrait 800x1280': Size(800, 1280),
  'tablet landscape 1280x800': Size(1280, 800),
  'desktop 1920x1080': Size(1920, 1080),
};
const scales = [0.5, 1.0, 1.5, 2.0, 3.0];

Future<void> pumpAt(WidgetTester t, Size size, double scale, Widget child) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    child: MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: ResponsiveFrame(child: c!),
      ),
      home: Scaffold(body: child),
    ),
  ));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ResponsiveFrame', () {
    for (final e in sizes.entries) {
      for (final scale in scales) {
        testWidgets('${e.key} @ text ${scale}x: width capped, text scale clamped', (t) async {
          double? w, textScale;
          await pumpAt(t, e.value, scale, Builder(builder: (ctx) {
            w = MediaQuery.of(ctx).size.width;
            textScale = MediaQuery.of(ctx).textScaler.scale(10) / 10;
            return const SizedBox();
          }));
          expect(w, lessThanOrEqualTo(kMaxContentWidth));
          expect(w, lessThanOrEqualTo(e.value.width));
          expect(textScale, inInclusiveRange(kMinTextScale - 0.001, kMaxTextScale + 0.001));
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('on a wide screen the content is centered', (t) async {
      await pumpAt(t, const Size(1280, 800), 1.0, const SizedBox.expand(key: Key('content')));
      final r = t.getRect(find.byKey(const Key('content')));
      expect(r.width, kMaxContentWidth);
      expect(r.center.dx, closeTo(640, 1));
    });

    testWidgets('on a phone nothing is added around the content', (t) async {
      await pumpAt(t, const Size(411, 915), 1.0, const SizedBox.expand(key: Key('content')));
      expect(t.getRect(find.byKey(const Key('content'))).width, 411);
    });
  });

  group('SongTile never overflows or throws', () {
    final songs = <String, Song>{
      'normal': const Song(videoId: 'dQw4w9WgXcQ', title: 'Never Gonna Give You Up', artist: 'Rick Astley', thumbnailUrl: ''),
      'empty strings': const Song(videoId: 'x', title: '', artist: '', thumbnailUrl: ''),
      'very long': Song(videoId: 'x', title: 'T' * 400, artist: 'A' * 400, thumbnailUrl: ''),
      'no spaces unbreakable': Song(videoId: 'x', title: 'W' * 120, artist: 'M' * 120, thumbnailUrl: ''),
      'rtl + emoji': const Song(videoId: 'x', title: 'أغنية جميلة 🎵 דוגמה', artist: '歌手 🎤', thumbnailUrl: ''),
    };
    for (final sz in sizes.entries) {
      for (final sc in const [1.0, 2.0, 3.0]) {
        for (final song in songs.entries) {
          testWidgets('${sz.key} @ ${sc}x / ${song.key}', (t) async {
            await pumpAt(t, sz.value, sc, SongTile(song: song.value, isPlaying: false, onTap: () {}));
            await t.pump();
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  });
}
