import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/models/song.dart';
import 'package:noor/providers/library_provider.dart';
import 'package:noor/providers/player_provider.dart';
import 'package:noor/providers/search_provider.dart';
import 'package:noor/screens/search_screen.dart';
import 'package:noor/services/song_details.dart';
import 'package:noor/theme/noor_play_pause.dart';
import 'package:noor/widgets/song_details_panel.dart';
import 'package:noor/widgets/song_row.dart';
import 'package:noor/widgets/search_filter_bar.dart';
import 'package:noor/widgets/search_filter_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song song(String id, String title, {bool official = false}) => Song(
    videoId: id.padRight(11, 'x'), title: title, artist: 'A', thumbnailUrl: '', isOfficial: official);

final sample = [
  song('fan1', 'Fan upload (Lyrics)'),
  song('real', 'Real Song (Official Audio)', official: true),
  song('fan2', 'Fan upload 8D'),
  song('topic', 'Real Song - Topic', official: true),
];

/// A player that does nothing: the search screen only reads it.
class FakePlayer extends StateNotifier<NebulaPlayerState> implements PlayerNotifier {
  FakePlayer() : super(const NebulaPlayerState());
  final List<List<Song>> queues = [];
  @override
  Future<void> playSong(Song song, {List<Song>? queue}) async => queues.add(queue ?? []);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class StubSearch extends SearchNotifier {
  StubSearch(Ref ref, SearchState initial) : super(ref) {
    state = initial;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('applySearchFilter', () {
    test('best match keeps everything in order', () {
      expect(applySearchFilter(sample, SearchFilter.bestMatch), sample);
    });

    test('official only keeps just the official ones, in order', () {
      final r = applySearchFilter(sample, SearchFilter.officialOnly);
      expect(r.map((s) => s.title), ['Real Song (Official Audio)', 'Real Song - Topic']);
    });

    test('no official results → empty list (never throws)', () {
      expect(applySearchFilter([song('a', 'x')], SearchFilter.officialOnly), isEmpty);
      expect(applySearchFilter(const [], SearchFilter.officialOnly), isEmpty);
    });
  });

  group('the chosen filter is remembered', () {
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

    test('defaults to best match', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(searchFilterProvider);
      await settle();
      expect(c.read(searchFilterProvider), SearchFilter.bestMatch);
    });

    test('a changed choice (official only) survives a restart', () async {
      final a = ProviderContainer();
      await a.read(searchFilterProvider.notifier).set(SearchFilter.officialOnly);
      a.dispose();
      final b = ProviderContainer();
      addTearDown(b.dispose);
      b.read(searchFilterProvider);
      await settle();
      expect(b.read(searchFilterProvider), SearchFilter.officialOnly);
    });

    test('a corrupt saved value falls back to best match', () async {
      SharedPreferences.setMockInitialValues({'search_filter': 'zzz-not-a-filter'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(searchFilterProvider);
      await settle();
      expect(c.read(searchFilterProvider), SearchFilter.bestMatch);
    });
  });

  group('SearchFilterBar', () {
    Widget bar({
      SearchFilter filter = SearchFilter.bestMatch,
      ValueChanged<SearchFilter>? onChanged,
      int total = 20,
      int official = 3,
      bool dark = false,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: SearchFilterBar(
              filter: filter,
              onChanged: onChanged ?? (_) {},
              totalCount: total,
              officialCount: official,
              isDark: dark,
            ),
          ),
        );

    testWidgets('shows both chips with their counts', (t) async {
      await t.pumpWidget(bar());
      expect(find.text('Best match'), findsOneWidget);
      expect(find.text('Official only'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('20'), findsNWidgets(2)); // All and Best match
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('tapping a chip reports it', (t) async {
      final picked = <SearchFilter>[];
      await t.pumpWidget(bar(onChanged: picked.add));
      await t.tap(find.text('Official only'));
      await t.tap(find.text('Best match'));
      expect(picked, [SearchFilter.officialOnly, SearchFilter.bestMatch]);
    });

    testWidgets('the selected chip is announced as selected to screen readers', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(bar(filter: SearchFilter.officialOnly));
      final official = t.getSemantics(find.bySemanticsLabel('Official only, 3 results'));
      expect(official, containsSemantics(isSelected: true, isButton: true));
      final best = t.getSemantics(find.bySemanticsLabel('Best match, 20 results'));
      expect(best, isNot(containsSemantics(isSelected: true)));
      handle.dispose();
    });

    for (final size in const [Size(280, 600), Size(320, 480), Size(411, 915), Size(800, 1280)]) {
      for (final scale in const [1.0, 1.35, 2.0, 3.0]) {
        for (final dark in const [false, true]) {
          testWidgets('no overflow at $size, text ${scale}x, dark=$dark', (t) async {
            t.view.physicalSize = size;
            t.view.devicePixelRatio = 1.0;
            addTearDown(t.view.reset);
            await t.pumpWidget(MaterialApp(
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: SearchFilterBar(
                  filter: SearchFilter.officialOnly,
                  onChanged: (_) {},
                  totalCount: 123456,
                  officialCount: 99999,
                  isDark: dark,
                ),
              ),
            ));
            expect(t.takeException(), isNull);
          });
        }
      }
    }
  });

  group('the whole search screen', () {
    late FakePlayer player;
    late _Details details;

    /// The play button on the card showing [title].
    Finder playOf(String title) => find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(NoorSongRow)),
        matching: find.byType(NoorPlayPauseButton));

    Future<void> open(WidgetTester t, {required List<Song> results}) async {
      t.view.physicalSize = const Size(411, 915);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      player = FakePlayer();
      details = _Details();
      await t.pumpWidget(ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          songDetailsSourceProvider.overrideWithValue(details),
          searchProvider.overrideWith((ref) => StubSearch(
              ref, SearchState(results: results, status: SearchStatus.loaded, query: 'q'))),
        ],
        child: MaterialApp(home: Scaffold(body: SearchPanel(onRetry: () {}))),
      ));
      await t.pump(const Duration(milliseconds: 100));
    }

    /// Opens the filter pop-up (the settings button's, while searching)
    /// and picks [option].
    Future<void> chooseFilter(WidgetTester t, String option) async {
      showSearchFilters(t.element(find.byType(SearchPanel)));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text(option));
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('best match is the default: everything, ranked', (t) async {
      await open(t, results: sample);
      expect(find.text('Top Results'), findsOneWidget);
      expect(find.text('Fan upload (Lyrics)'), findsOneWidget);
    });

    testWidgets('official only hides fan uploads', (t) async {
      await open(t, results: sample);
      await chooseFilter(t, 'Official only');
      expect(find.text('Official uploads'), findsOneWidget);
      expect(find.text('Fan upload (Lyrics)'), findsNothing);
      expect(find.text('Fan upload 8D'), findsNothing);
      expect(find.text('Real Song (Official Audio)'), findsOneWidget);
      expect(find.text('Real Song - Topic'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('official songs say so after the artist', (t) async {
      await open(t, results: sample);
      expect(find.textContaining('·  Official'), findsNWidgets(2));
    });

    testWidgets('the Best match chip switches the list and remembers it', (t) async {
      await open(t, results: sample);
      await chooseFilter(t, 'Official only');
      await chooseFilter(t, 'Best match');
      expect(find.text('Fan upload (Lyrics)'), findsOneWidget);
      expect(find.text('Top Results'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getString('search_filter'), 'bestMatch');
      expect(t.takeException(), isNull);
    });

    testWidgets('with no official result the screen explains it and offers "Show all results"', (t) async {
      await open(t, results: [song('a', 'Only fans'), song('b', 'More fans')]);
      await chooseFilter(t, 'Official only');
      expect(find.text('No official upload found for this search'), findsOneWidget);
      expect(find.text('2 other results are available.'), findsOneWidget);
      await t.tap(find.text('Show all results'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Only fans'), findsOneWidget);
      expect(find.text('No official upload found for this search'), findsNothing);
    });

    testWidgets('up next after a search is what was played recently, not the results', (t) async {
      final recent = [
        {'videoId': 'recentAxxxx', 'title': 'Played Before 1', 'artist': 'x', 'thumbnailUrl': ''},
        {'videoId': 'recentBxxxx', 'title': 'Played Before 2', 'artist': 'x', 'thumbnailUrl': ''},
      ];
      SharedPreferences.setMockInitialValues({'nebula_history': jsonEncode(recent)});
      await open(t, results: sample);
      await t.pump(const Duration(milliseconds: 100)); // the saved history loads
      await t.tap(playOf('Real Song (Official Audio)'));
      await t.pump(const Duration(milliseconds: 400)); // a tap waits out a possible double tap
      expect(player.queues.single.map((s) => s.title),
          ['Real Song (Official Audio)', 'Played Before 1', 'Played Before 2']);
    });

    testWidgets('with no history the queue is just the chosen song', (t) async {
      await open(t, results: sample);
      await t.tap(playOf('Real Song (Official Audio)'));
      await t.pump(const Duration(milliseconds: 400));
      expect(player.queues.single.map((s) => s.title), ['Real Song (Official Audio)']);
    });

    testWidgets('double-tapping a song likes it, again unlikes it', (t) async {
      await open(t, results: sample);
      final container = ProviderScope.containerOf(t.element(find.byType(SearchPanel)));
      final tile = find.text('Real Song (Official Audio)');
      await t.tap(tile);
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(tile);
      await t.pump(const Duration(milliseconds: 100));
      expect(container.read(likedProvider).map((s) => s.title), ['Real Song (Official Audio)']);
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(tile);
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(tile);
      await t.pump(const Duration(milliseconds: 100));
      expect(container.read(likedProvider), isEmpty);
    });

    testWidgets('All shows every result in YouTube order', (t) async {
      t.view.physicalSize = const Size(411, 915);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => FakePlayer()),
          searchProvider.overrideWith((ref) => StubSearch(
              ref,
              SearchState(
                  results: [song('a', 'Ranked')],
                  all: [song('b', 'Extra'), song('a', 'Ranked')],
                  status: SearchStatus.loaded,
                  query: 'q'))),
        ],
        child: MaterialApp(home: Scaffold(body: SearchPanel(onRetry: () {}))),
      ));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Extra'), findsNothing);
      await chooseFilter(t, 'All');
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('All results'), findsOneWidget);
      expect(t.getTopLeft(find.text('Extra')).dy,
          lessThan(t.getTopLeft(find.text('Ranked')).dy));
    });

    testWidgets('a search with no results says so', (t) async {
      await open(t, results: const []);
      expect(find.text('No results found'), findsOneWidget);
    });

    testWidgets('the play button plays a result without leaving the page', (t) async {
      await open(t, results: sample);
      await t.tap(playOf('Real Song (Official Audio)'));
      await t.pump(const Duration(milliseconds: 400));
      expect(player.queues, hasLength(1));
      expect(find.byType(SearchPanel), findsOneWidget);
      expect(find.byType(SongDetailsPanel), findsNothing);
    });

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('tapping the card grows it with the details; it does not play', (t) async {
      await open(t, results: sample);
      await t.tap(find.text('Real Song (Official Audio)'));
      await settle(t);
      expect(player.queues, isEmpty);
      expect(find.byType(SongDetailsPanel), findsOneWidget);
      expect(find.text('Label Channel'), findsOneWidget);
      expect(find.text('12M views'), findsOneWidget);
      expect(find.text('340K likes'), findsOneWidget);
      expect(find.text('Arijit Singh'), findsOneWidget); // Singer
      expect(find.text('Amitabh Bhattacharya'), findsOneWidget); // Lyrics
      expect(find.text('Pritam'), findsOneWidget); // Music
      expect(details.calls, 1);
      expect(t.takeException(), isNull);
    });

    testWidgets('a tap on the details folds the card back', (t) async {
      await open(t, results: sample);
      await t.tap(find.text('Real Song (Official Audio)'));
      await settle(t);
      await t.tap(find.text('Label Channel'));
      await settle(t);
      expect(find.byType(SongDetailsPanel), findsNothing);
      expect(player.queues, isEmpty);
    });

    testWidgets('only one card is open at a time', (t) async {
      await open(t, results: sample);
      await t.tap(find.text('Real Song (Official Audio)'));
      await settle(t);
      await t.tap(find.text('Fan upload (Lyrics)'));
      await settle(t);
      expect(find.byType(SongDetailsPanel), findsOneWidget);
      expect(find.text('Fan upload (Lyrics)'), findsOneWidget);
    });

    testWidgets('the play button inside the open card plays it', (t) async {
      await open(t, results: sample);
      await t.tap(find.text('Real Song (Official Audio)'));
      await settle(t);
      await t.tap(find.descendant(
          of: find.byType(SongDetailsPanel), matching: find.byType(NoorPlayPauseButton)));
      await t.pump(const Duration(milliseconds: 100));
      expect(player.queues.single.first.title, 'Real Song (Official Audio)');
    });

    testWidgets('details that cannot be loaded say so and offer to try again', (t) async {
      await open(t, results: sample);
      details.fail = true;
      await t.tap(find.text('Real Song (Official Audio)'));
      await settle(t);
      expect(find.text('The details could not be loaded right now.'), findsOneWidget);
      details.fail = false;
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.text('12M views'), findsOneWidget);
    });
  });
}

class _Details implements SongDetailsSource {
  int calls = 0;
  bool fail = false;
  @override
  Future<SongDetails?> fetch(String videoId) async {
    calls++;
    if (fail) return null;
    return SongDetails(
      videoId: videoId,
      channel: 'Label Channel',
      views: 12000000,
      likes: 340000,
      description: 'Singer: Arijit Singh\nLyrics: Amitabh Bhattacharya\nMusic: Pritam',
    );
  }
}
