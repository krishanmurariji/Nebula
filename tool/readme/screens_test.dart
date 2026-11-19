// Uses test-only hooks on purpose: this is a test, kept outside test/ so
// CI does not run it.
// ignore_for_file: invalid_use_of_visible_for_testing_member

// Renders the README screenshots and animation frames from the real app
// widgets, with fictional songs and the abstract art in docs/readme/art.
//
//   python3 tool/readme/make_art.py
//   flutter test tool/readme/screens_test.dart --update-goldens
//   python3 tool/readme/compose.py
//
// Frames land in build/readme/ (git-ignored); compose.py turns them into
// the framed screenshots and GIFs in docs/readme/.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/models/song.dart';
import 'package:nebula_music_player/providers/library_provider.dart';
import 'package:nebula_music_player/providers/player_provider.dart';
import 'package:nebula_music_player/providers/search_provider.dart';
import 'package:nebula_music_player/screens/home_screen.dart';
import 'package:nebula_music_player/screens/player_screen.dart';
import 'package:nebula_music_player/theme/noor_artwork.dart';
import 'package:nebula_music_player/theme/noor_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = 'build/readme';

final songs = [
  for (final (i, t, a) in [
    (1, 'Monsoon Letters', 'Aanya Rao'),
    (2, 'Saffron Skies', 'Kabir Sethi'),
    (3, 'Moonlit Qawwali', 'Noor Ensemble'),
    (4, 'Old Delhi Rain', 'Meera Kaul'),
    (5, 'Desert Rose', 'Zaid Khan'),
    (6, 'Lanterns', 'Ira Malhotra'),
    (7, 'Velvet Night', 'Arjun Dev'),
    (8, 'Golden Hour Raag', 'Tara Iyer'),
  ])
    Song(
        videoId: 'readme$i'.padRight(11, 'x'),
        title: t,
        artist: a,
        thumbnailUrl: 'readme://art/$i',
        isOfficial: i.isOdd),
];

class _Player extends StateNotifier<NebulaPlayerState>
    implements PlayerNotifier {
  _Player(super.s);
  @override
  Future<void> playSong(Song song, {List<Song>? queue}) async {
    state = NebulaPlayerState(
        song: state.song,
        pendingSong: song,
        status: NebulaPlayerStatus.loading,
        queue: queue ?? [song]);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    state = NebulaPlayerState(
        song: song, status: NebulaPlayerStatus.playing, queue: queue ?? [song]);
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Search extends SearchNotifier {
  _Search(super.ref, SearchState s) {
    state = s;
  }
  @override
  void clear() {}
}

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await l.load();
}

String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null) return env;
  // .../flutter/bin/cache/dart-sdk/bin/dart -> .../flutter
  return File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
}

Map<String, Object> _library({int playlists = 2, bool liked = true}) => {
      'nebula_history': jsonEncode(songs.map((s) => s.toMap()).toList()),
      if (liked)
        'nebula_liked': jsonEncode(
            [songs[1], songs[3], songs[6]].map((s) => s.toMap()).toList()),
      'nebula_playlists': jsonEncode([
        for (var i = 0; i < playlists; i++)
          {
            'id': 'p$i',
            'name': const [
              'Road Trip', 'Late Night', 'Sufi', 'Workout', 'Rainy Days',
              'Old Gold', 'Focus', 'Wedding', 'Chill', 'Party'
            ][i],
            'songs': i == 0
                ? [songs[4].toMap(), songs[5].toMap()]
                : i == 1
                    ? [songs[2].toMap()]
                    : [],
          }
      ]),
    };

void main() {
  final art = <String, MemoryImage>{};

  setUpAll(() async {
    final m = '${_flutterRoot()}/bin/cache/artifacts/material_fonts';
    await _font('Roboto',
        ['$m/Roboto-Regular.ttf', '$m/Roboto-Medium.ttf', '$m/Roboto-Bold.ttf']);
    await _font('MaterialIcons', ['$m/MaterialIcons-Regular.otf']);
    await _font('NoorScript', ['assets/fonts/DancingScript-Bold.ttf']);
    await _font('Cormorant', ['assets/fonts/CormorantGaramond-Bold.ttf']);
    for (var i = 1; i <= 8; i++) {
      art['readme://art/$i'] =
          MemoryImage(File('docs/readme/art/$i.jpg').readAsBytesSync());
    }
    NoorArtwork.debugImageFor = (url) => art[url];
  });

  Future<void> boot(WidgetTester t, Widget home,
      {Map<String, Object>? prefs,
      NebulaPlayerState? player,
      SearchState? search}) async {
    SharedPreferences.setMockInitialValues(prefs ?? _library());
    t.view.physicalSize = const Size(411 * 2, 891 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final t0 = NoorTheme.light;
    await t.runAsync(() async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => _Player(player ??
              NebulaPlayerState(
                  song: songs[0],
                  status: NebulaPlayerStatus.playing,
                  queue: songs))),
          playbackProgressProvider.overrideWith((ref) => Stream.value(
              const PlaybackProgress(
                  Duration(minutes: 1, seconds: 24), Duration(minutes: 3, seconds: 52)))),
          if (search != null)
            searchProvider.overrideWith((ref) => _Search(ref, search)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Roboto',
            scaffoldBackgroundColor: t0.bg,
            colorScheme: ColorScheme.fromSeed(
                seedColor: t0.ac, primary: t0.ac, surface: t0.bg),
          ),
          home: home,
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _precache(t);
    });
    await settle(t, 20);
    await t.runAsync(() => _precache(t));
    await t.pump();
  }

  Future<void> shot(WidgetTester t, String name) =>
      expectLater(find.byType(MaterialApp), matchesGoldenFile('../../$_out/$name.png'));

  Future<void> frames(WidgetTester t, String name, int count, int stepMs) async {
    for (var i = 0; i < count; i++) {
      await shot(t, '${name}_${i.toString().padLeft(3, '0')}');
      await t.pump(Duration(milliseconds: stepMs));
    }
  }

  testWidgets('home', (t) async {
    await boot(t, const HomeScreen());
    await t.tap(find.byIcon(Icons.history_rounded));
    await settle(t, 20);
    await t.runAsync(() => _precache(t));
    await t.pump();
    await shot(t, 'home');
  });

  testWidgets('home slider animation', (t) async {
    await boot(t, const HomeScreen());
    await t.tap(find.byIcon(Icons.history_rounded));
    await settle(t, 20);
    await t.runAsync(() => _precache(t));
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.byIcon(Icons.favorite_rounded).first);
    await t.pump();
    await frames(t, 'slider', 26, 50);
  });

  testWidgets('player', (t) async {
    await boot(t, const PlayerScreen());
    await shot(t, 'player');
  });

  testWidgets('player record swap animation', (t) async {
    await boot(t, const _LibraryLoaded(child: PlayerScreen()));
    final turntable = t.getCenter(find.byType(PlayerScreen)) - const Offset(0, 120);
    // The record follows the finger and the next one slides in; a little
    // back (it can be taken back), then on past a third and let go.
    final g = await t.startGesture(turntable);
    var n = 0;
    var ms = 0;
    Future<void> step(double dx) async {
      ms += 60;
      await g.moveBy(Offset(dx, 0), timeStamp: Duration(milliseconds: ms));
      await t.pump(const Duration(milliseconds: 60));
      await shot(t, 'swap_${(n++).toString().padLeft(3, '0')}');
    }

    for (var i = 0; i < 12; i++) {
      await step(-10);
    }
    for (var i = 0; i < 6; i++) {
      await step(8);
    }
    for (var i = 0; i < 10; i++) {
      await step(-12);
    }
    await g.up();
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 60));
      await shot(t, 'swap_${(n++).toString().padLeft(3, '0')}');
    }
    await settle(t, 12);
  });

  testWidgets('search', (t) async {
    await boot(t, const HomeScreen(),
        search: SearchState(
            results: songs, status: SearchStatus.loaded, query: 'monsoon'));
    await t.tap(find.text('Search'));
    await settle(t, 8);
    await t.runAsync(() => _precache(t));
    await t.pump();
    await shot(t, 'search');
  });

  testWidgets('song actions and playlist circle', (t) async {
    await boot(t, const HomeScreen(), prefs: _library(playlists: 8));
    await t.tap(find.byIcon(Icons.history_rounded));
    await settle(t, 20);
    await t.runAsync(() => _precache(t));
    await t.pump();
    await t.fling(find.text('Old Delhi Rain'), const Offset(-260, 0), 1200);
    await settle(t, 12);
    await shot(t, 'actions');
    await t.tap(find.bySemanticsLabel('Add to playlist'));
    await t.pump();
    await frames(t, 'circle', 22, 50);
    await settle(t, 6);
    await shot(t, 'circle');
    await t.tapAt(const Offset(20, 60));
    await settle(t, 14);
  });

  testWidgets('new install', (t) async {
    await boot(t, const HomeScreen(),
        prefs: {}, player: const NebulaPlayerState());
    await shot(t, 'empty');
  });
}

/// Keeps the library providers alive, as Home does in the app, so the
/// player knows which song comes next.
class _LibraryLoaded extends ConsumerWidget {
  const _LibraryLoaded({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(historyProvider);
    ref.watch(likedSongsProvider);
    ref.watch(playlistProvider);
    return child;
  }
}

Future<void> settle(WidgetTester t, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _precache(WidgetTester t) async {
  for (final e in find.byType(Image).evaluate()) {
    await precacheImage((e.widget as Image).image, e);
  }
}
