import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/models/song.dart';
import 'package:nebula_music_player/providers/connection_provider.dart';
import 'package:nebula_music_player/providers/library_provider.dart';
import 'package:nebula_music_player/providers/player_provider.dart';
import 'package:nebula_music_player/providers/search_provider.dart';
import 'package:nebula_music_player/screens/search_screen.dart';
import 'package:nebula_music_player/services/youtube_search_service.dart';
import 'package:nebula_music_player/widgets/offline_pill.dart';
import 'package:nebula_music_player/widgets/song_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song s(String id, String t, {String artist = 'A'}) =>
    Song(videoId: id.padRight(11, 'x'), title: t, artist: artist, thumbnailUrl: '');

/// A connection whose answer the test sets.
class FakeNet {
  bool up = true;
  int checks = 0;
  Future<bool> check() async {
    checks++;
    return up;
  }

  ConnectionNotifier notifier() => ConnectionNotifier(check: check, start: false);
}

class FakeSearch implements YoutubeSearchService {
  int calls = 0;
  Object? error;
  @override
  Future<SongSearchResult> searchAll(String q) async {
    calls++;
    if (error != null) throw error!;
    return SongSearchResult([s('yt1', 'From YouTube $q')], const []);
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Player extends StateNotifier<NebulaPlayerState> implements PlayerNotifier {
  _Player() : super(const NebulaPlayerState());
  final played = <String>[];
  @override
  Future<void> playSong(Song song, {List<Song>? queue}) async => played.add(song.title);
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('connection watcher', () {
    test('follows the check, and a failing check counts as offline', () async {
      final net = FakeNet();
      final n = net.notifier();
      await n.recheck();
      expect(n.state, Connection.online);
      net.up = false;
      await n.recheck();
      expect(n.state, Connection.offline);
      net.up = true;
      await n.recheck();
      expect(n.state, Connection.online);
      final broken = ConnectionNotifier(
          check: () async => throw Exception('dns exploded'), start: false);
      await broken.recheck();
      expect(broken.state, Connection.offline);
    });

    test('a reported failure shows offline at once; a success brings it back', () {
      final n = FakeNet().notifier();
      n.reportFailure();
      expect(n.isOffline, isTrue);
      n.reportSuccess();
      expect(n.isOffline, isFalse);
    });

    test('while offline it checks again by itself and recovers', () {
      fakeAsyncRun((async) {
        final net = FakeNet()..up = false;
        final n = ConnectionNotifier(
            check: net.check,
            start: true,
            offlineEvery: const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(n.state, Connection.offline);
        net.up = true;
        async.elapse(const Duration(seconds: 6));
        expect(n.state, Connection.online);
        n.dispose();
      });
    });
  });

  group('search', () {
    late FakeNet net;
    late FakeSearch yt;
    late ProviderContainer c;
    setUp(() {
      net = FakeNet();
      yt = FakeSearch();
      c = ProviderContainer(overrides: [
        searchServiceProvider.overrideWithValue(yt),
        connectionProvider.overrideWith((ref) => net.notifier()),
      ]);
    });
    tearDown(() => c.dispose());

    test('offline: YouTube is not asked, the panel searches the phone', () async {
      c.read(connectionProvider.notifier).reportFailure();
      net.up = false;
      await c.read(searchProvider.notifier).search('rain');
      expect(yt.calls, 0);
      expect(c.read(searchProvider).status, SearchStatus.offline);
      expect(c.read(searchProvider).query, 'rain');
    });

    test('a failed search on a dead connection becomes the offline view', () async {
      yt.error = const SearchException('Search timed out.');
      net.up = false;
      await c.read(searchProvider.notifier).search('rain');
      expect(c.read(searchProvider).status, SearchStatus.offline);
      expect(c.read(connectionProvider), Connection.offline);
    });

    test('a failed search with working internet stays an error', () async {
      yt.error = const SearchException('Search failed. Check your connection and try again.');
      await c.read(searchProvider.notifier).search('rain');
      expect(c.read(searchProvider).status, SearchStatus.error);
      expect(c.read(connectionProvider), Connection.online);
    });

    test('rate limiting is not mistaken for offline (no check needed)', () async {
      yt.error = const SearchException('YouTube is limiting requests from your network.');
      await c.read(searchProvider.notifier).search('rain');
      expect(c.read(searchProvider).status, SearchStatus.error);
      expect(net.checks, 0);
    });

    test('a search that works marks the connection online again', () async {
      c.read(connectionProvider.notifier).reportFailure();
      c.read(connectionProvider.notifier).reportSuccess();
      await c.read(searchProvider.notifier).search('rain');
      expect(c.read(searchProvider).status, SearchStatus.loaded);
    });

    test('CHAOS: the connection flapping 50 times never leaves search confused', () async {
      for (var i = 0; i < 50; i++) {
        net.up = i.isEven;
        if (i % 3 == 0) {
          c.read(connectionProvider.notifier).reportFailure();
        } else {
          await c.read(connectionProvider.notifier).recheck();
        }
        yt.error = i % 4 == 0 ? const SearchException('Search timed out.') : null;
        await c.read(searchProvider.notifier).search('song $i');
        final st = c.read(searchProvider).status;
        expect(st, isNot(SearchStatus.loading));
        if (st == SearchStatus.loaded) {
          expect(c.read(connectionProvider), Connection.online);
        }
        if (c.read(connectionProvider) == Connection.offline) {
          expect(st, anyOf(SearchStatus.offline, SearchStatus.error));
        }
      }
    });
  });

  group('offline screens', () {
    final saved = s('sv', 'Monsoon Rain', artist: 'Aanya');
    final notSaved = s('ns', 'Rainy Night', artist: 'Kabir');
    final other = s('ot', 'Desert Rose');

    Future<(ProviderContainer, _Player)> pump(WidgetTester t, Widget body,
        {bool offline = true, String query = 'rain'}) async {
      SharedPreferences.setMockInitialValues({
        'nebula_history': jsonEncode([saved, notSaved, other].map((x) => x.toMap()).toList()),
      });
      t.view.physicalSize = const Size(411, 891);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final net = FakeNet()..up = !offline;
      final p = _Player();
      await t.pumpWidget(ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => p),
          connectionProvider.overrideWith((ref) {
            final n = net.notifier();
            if (offline) n.reportFailure();
            return n;
          }),
          isOnDeviceProvider.overrideWithValue((id) => id == saved.videoId),
          searchProvider.overrideWith((ref) => _StubSearch(ref,
              SearchState(status: SearchStatus.offline, query: query))),
        ],
        child: MaterialApp(home: Scaffold(body: body)),
      ));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      return (ProviderScope.containerOf(t.element(find.byType(Scaffold))), p);
    }

    testWidgets('offline search shows only saved songs that match', (t) async {
      await pump(t, SearchPanel(onRetry: () {}));
      expect(find.textContaining("You're offline"), findsOneWidget);
      expect(find.text('Monsoon Rain'), findsOneWidget);
      expect(find.text('Rainy Night'), findsNothing); // not saved
      expect(find.text('Desert Rose'), findsNothing); // does not match
      expect(find.text('On this phone'), findsOneWidget);
      expect(find.text('Best match'), findsNothing); // YouTube filters hidden
    });

    testWidgets('offline search with no saved match says so', (t) async {
      await pump(t, SearchPanel(onRetry: () {}), query: 'qawwali');
      expect(find.textContaining('No saved song matches'), findsOneWidget);
      expect(find.text('Monsoon Rain'), findsNothing);
    });

    testWidgets('offline, a song that needs internet is faded and explains itself', (t) async {
      final (_, p) = await pump(
          t,
          ListView(children: [
            NoorSongRow(song: notSaved, onTap: () {}),
            NoorSongRow(song: saved, onTap: () {}),
          ]));
      final faded = t.widget<AnimatedOpacity>(find.ancestor(
          of: find.text('Rainy Night'), matching: find.byType(AnimatedOpacity)).first);
      expect(faded.opacity, lessThan(1));
      final normal = t.widget<AnimatedOpacity>(find.ancestor(
          of: find.text('Monsoon Rain'), matching: find.byType(AnimatedOpacity)).first);
      expect(normal.opacity, 1);
      await t.tap(find.text('Rainy Night'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining("isn't saved on the phone"), findsOneWidget);
      expect(p.played, isEmpty);
    });

    testWidgets('online, the same song is normal', (t) async {
      await pump(t, ListView(children: [NoorSongRow(song: notSaved, onTap: () {})]),
          offline: false);
      final o = t.widget<AnimatedOpacity>(find.ancestor(
          of: find.text('Rainy Night'), matching: find.byType(AnimatedOpacity)).first);
      expect(o.opacity, 1);
    });

    testWidgets('the offline pill comes and goes with the connection', (t) async {
      final (c, _) = await pump(t, const NoorOfflinePill());
      expect(find.text('Offline · saved songs only'), findsOneWidget);
      c.read(connectionProvider.notifier).reportSuccess();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Offline · saved songs only'), findsNothing);
    });

    testWidgets('tapping a matched offline song plays it from the matches', (t) async {
      final (_, p) = await pump(t, SearchPanel(onRetry: () {}));
      await t.tap(find.text('Monsoon Rain'));
      await t.pump(const Duration(milliseconds: 400));
      expect(p.played, ['Monsoon Rain']);
    });
  });
}

class _StubSearch extends SearchNotifier {
  _StubSearch(super.ref, SearchState s) {
    state = s;
  }
}

/// Runs [body] in fake time (timers advance only when told).
void fakeAsyncRun(void Function(FakeAsyncLike async) body) {
  FakeAsyncLike.run(body);
}

/// A tiny fake clock (timers fire only when [elapse] is called), so this file
/// needs no extra dependency.
class FakeAsyncLike {
  FakeAsyncLike._(this._zoneTimers);
  final List<_PendingTimer> _zoneTimers;
  Duration _now = Duration.zero;

  static void run(void Function(FakeAsyncLike) body) {
    final timers = <_PendingTimer>[];
    final fa = FakeAsyncLike._(timers);
    final zone = Zone.current.fork(
      specification: ZoneSpecification(
        createTimer: (self, parent, zone, d, f) {
          final t = _PendingTimer(fa._now + d, f);
          timers.add(t);
          return t;
        },
        scheduleMicrotask: (self, parent, zone, f) => fa._micro.add(f),
      ),
    );
    zone.run(() => body(fa));
    fa.flushMicrotasks();
  }

  final List<void Function()> _micro = [];

  void flushMicrotasks() {
    for (var i = 0; i < 1000 && _micro.isNotEmpty; i++) {
      _micro.removeAt(0)();
    }
  }

  void elapse(Duration d) {
    final end = _now + d;
    flushMicrotasks();
    while (true) {
      _zoneTimers.sort((a, b) => a.due.compareTo(b.due));
      final next = _zoneTimers.where((t) => t.isActive && t.due <= end).firstOrNull;
      if (next == null) break;
      _now = next.due;
      next.fire();
      flushMicrotasks();
    }
    _now = end;
  }
}

class _PendingTimer implements Timer {
  _PendingTimer(this.due, this._f);
  final Duration due;
  final void Function() _f;
  bool _active = true;
  void fire() {
    _active = false;
    _f();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}
