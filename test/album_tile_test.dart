import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/models/song.dart';
import 'package:nebula_music_player/providers/library_provider.dart';
import 'package:nebula_music_player/providers/player_provider.dart';
import 'package:nebula_music_player/screens/upnext_screen.dart';
import 'package:nebula_music_player/theme/noor_album_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

Song song(String id, String t) =>
    Song(videoId: id.padRight(11, 'x'), title: t, artist: 'Chan $id', thumbnailUrl: '');

class _Player extends StateNotifier<NebulaPlayerState> implements PlayerNotifier {
  _Player(super.s);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Finder heartIcon() => find.byIcon(Icons.favorite_rounded);
  Color heartColor(WidgetTester t) => t.widget<Icon>(heartIcon()).color!;

  group('NoorAlbumTile', () {
    testWidgets('shows just the title and channel: no Play button, no heart on the border', (t) async {
      await t.pumpWidget(host(NoorAlbumTile(
          thumbnailUrl: '', title: 'Kesariya', channel: 'Sony', onPlay: () {}, onToggleLike: () {})));
      expect(find.text('Kesariya'), findsOneWidget);
      expect(find.text('Sony'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      expect(heartIcon(), findsNothing);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    });

    testWidgets('the OFFICIAL badge appears only when asked for', (t) async {
      await t.pumpWidget(host(NoorAlbumTile(
          thumbnailUrl: '', title: 'A', channel: 'c', onPlay: () {})));
      expect(find.text('OFFICIAL'), findsNothing);
      await t.pumpWidget(host(NoorAlbumTile(
          thumbnailUrl: '', title: 'A', channel: 'c', isOfficial: true, onPlay: () {})));
      expect(find.text('OFFICIAL'), findsOneWidget);
    });

    testWidgets('a tap plays', (t) async {
      var plays = 0;
      await t.pumpWidget(host(NoorAlbumTile(
          thumbnailUrl: '', title: 'A', channel: 'c', onPlay: () => plays++, onToggleLike: () {})));
      await t.tap(find.text('A'));
      await t.pump(const Duration(milliseconds: 400)); // waits out a possible double tap
      expect(plays, 1);
    });

    testWidgets('double tap on an unliked song: a white heart turns red, then fades', (t) async {
      var likes = 0;
      var plays = 0;
      await t.pumpWidget(host(NoorAlbumTile(
          thumbnailUrl: '',
          title: 'A',
          channel: 'c',
          liked: false,
          onPlay: () => plays++,
          onToggleLike: () => likes++)));
      await t.tap(find.text('A'));
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(find.text('A'));
      await t.pump(); // the animation starts on this frame
      await t.pump(const Duration(milliseconds: 60));
      expect(likes, 1);
      expect(plays, 0);
      expect(heartIcon(), findsOneWidget);
      expect(heartColor(t).value, Colors.white.value);
      await t.pump(const Duration(milliseconds: 500));
      final mid = heartColor(t);
      expect(mid.red, greaterThan(200));
      expect(mid.green, lessThan(120)); // red now
      await t.pump(const Duration(milliseconds: 600));
      expect(heartIcon(), findsNothing);
    });

    testWidgets('double tap on a liked song: a red heart turns white', (t) async {
      await t.pumpWidget(host(NoorAlbumTile(
          thumbnailUrl: '', title: 'A', channel: 'c', liked: true, onPlay: () {}, onToggleLike: () {})));
      await t.tap(find.text('A'));
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(find.text('A'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      final start = heartColor(t);
      expect(start.red, greaterThan(200));
      expect(start.green, lessThan(120)); // starts red
      await t.pump(const Duration(milliseconds: 500));
      expect(heartColor(t).green, greaterThan(200)); // ends white
      await t.pump(const Duration(milliseconds: 700));
    });
  });

  group('Up next', () {
    Future<void> open(WidgetTester t, List<Song> queue) async {
      t.view.physicalSize = const Size(411, 915);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => _Player(NebulaPlayerState(
              song: queue.first, status: NebulaPlayerStatus.playing, queue: queue))),
        ],
        child: const MaterialApp(home: UpNextScreen()),
      ));
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('lists the queue with the same tiles as Home', (t) async {
      await open(t, [song('a', 'First'), song('b', 'Second'), song('c', 'Third')]);
      expect(find.byType(NoorAlbumTile), findsNWidgets(3));
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('OFFICIAL'), findsNothing);
    });

    testWidgets('an empty queue says so', (t) async {
      t.view.physicalSize = const Size(411, 915);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [playerProvider.overrideWith((ref) => _Player(const NebulaPlayerState()))],
        child: const MaterialApp(home: UpNextScreen()),
      ));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Queue is empty'), findsOneWidget);
    });
  });
}
