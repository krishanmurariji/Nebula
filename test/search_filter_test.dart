import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/models/song.dart';
import 'package:nebula_music_player/providers/library_provider.dart';
import 'package:nebula_music_player/providers/player_provider.dart';
import 'package:nebula_music_player/providers/search_provider.dart';
import 'package:nebula_music_player/screens/search_screen.dart';
import 'package:nebula_music_player/widgets/search_filter_bar.dart';
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

    test('defaults to official only', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(searchFilterProvider);
      await settle();
      expect(c.read(searchFilterProvider), SearchFilter.officialOnly);
    });

    test('a changed choice (best match) survives a restart', () async {
      final a = ProviderContainer();
      await a.read(searchFilterProvider.notifier).set(SearchFilter.bestMatch);
      a.dispose();
      final b = ProviderContainer();
      addTearDown(b.dispose);
      b.read(searchFilterProvider);
      await settle();
      expect(b.read(searchFilterProvider), SearchFilter.bestMatch);
    });

    test('a corrupt saved value falls back to official only', () async {
      SharedPreferences.setMockInitialValues({'search_filter': 'zzz-not-a-filter'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(searchFilterProvider);
      await settle();
      expect(c.read(searchFilterProvider), SearchFilter.officialOnly);
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
      expect(find.text('20'), findsOneWidget);
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

    Future<void> open(WidgetTester t, {required List<Song> results}) async {
      t.view.physicalSize = const Size(411, 915);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      player = FakePlayer();
      await t.pumpWidget(ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => player),
          searchProvider.overrideWith((ref) => StubSearch(
              ref, SearchState(results: results, status: SearchStatus.loaded, query: 'q'))),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ));
      await t.pump(const Duration(milliseconds: 100));
    }

    Future<void> chooseFilter(WidgetTester t, String option) async {
      await t.tap(find.byIcon(Icons.tune_rounded));
      await t.pump(); // the route appears
      await t.pump(const Duration(milliseconds: 500)); // it slides down
      await t.tap(find.text(option));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Apply'));
      await t.pump(); // it starts closing
      await t.pump(const Duration(milliseconds: 500));
    }

    testWidgets('official only is the default: fan uploads are hidden', (t) async {
      await open(t, results: sample);
      expect(find.text('Official uploads'), findsOneWidget);
      expect(find.text('Fan upload (Lyrics)'), findsNothing);
      expect(find.text('Fan upload 8D'), findsNothing);
      expect(find.text('Real Song (Official Audio)'), findsOneWidget);
      expect(find.text('Real Song - Topic'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('official songs carry the OFFICIAL badge on the border', (t) async {
      await open(t, results: sample);
      expect(find.text('OFFICIAL'), findsNWidgets(2));
    });

    testWidgets('the filter pop-up switches to Best match and remembers it', (t) async {
      await open(t, results: sample);
      await chooseFilter(t, 'Best match');
      expect(find.text('Fan upload (Lyrics)'), findsOneWidget);
      expect(find.text('Top Results'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getString('search_filter'), 'bestMatch');
      expect(t.takeException(), isNull);
    });

    testWidgets('with no official result the screen explains it and offers "Show all results"', (t) async {
      await open(t, results: [song('a', 'Only fans'), song('b', 'More fans')]);
      expect(find.text('No official upload found for this search'), findsOneWidget);
      expect(find.text('2 other results are available.'), findsOneWidget);
      await t.tap(find.text('Show all results'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Only fans'), findsOneWidget);
      expect(find.text('No official upload found for this search'), findsNothing);
    });

    testWidgets('the queue handed to the player is the filtered list', (t) async {
      await open(t, results: sample);
      await t.tap(find.text('Real Song (Official Audio)'));
      await t.pump(const Duration(milliseconds: 400)); // a tap waits out a possible double tap
      expect(player.queues.single.map((s) => s.title),
          ['Real Song (Official Audio)', 'Real Song - Topic']);
    });

    testWidgets('double-tapping a song likes it, again unlikes it', (t) async {
      await open(t, results: sample);
      final container = ProviderScope.containerOf(t.element(find.byType(SearchScreen)));
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

    testWidgets('nothing searched yet: the empty page invites a search', (t) async {
      await open(t, results: const []);
      expect(find.text('No results found'), findsOneWidget);
    });
  });
}
