import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noor/models/song.dart';
import 'package:noor/providers/connection_provider.dart';
import 'package:noor/providers/search_provider.dart';
import 'package:noor/providers/search_suggestions_provider.dart';
import 'package:noor/screens/home_screen.dart';
import 'package:noor/services/youtube_search_service.dart';
import 'package:noor/theme/noor_search_button.dart';
import 'package:noor/widgets/search_suggestions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'search_filter_test.dart' show FakePlayer;
import 'package:noor/providers/player_provider.dart';

class _Service implements YoutubeSearchService {
  final searched = <String>[];
  @override
  Future<SongSearchResult> searchAll(String query) async {
    searched.add(query);
    return SongSearchResult([
      Song(videoId: 'result00001', title: 'Result for $query', artist: 'A', thumbnailUrl: ''),
    ], const []);
  }

  @override
  Future<List<Song>> searchSongs(String query) async => (await searchAll(query)).ranked;

  @override
  Future<List<String>> suggestions(String query) async => const [];
}

void main() {
  group('merging', () {
    test('with nothing typed: the recent searches', () {
      final m = mergeSuggestions('', ['a', 'b'], ['x']);
      expect(m.map((s) => (s.text, s.recent)), [('a', true), ('b', true)]);
    });

    test('typed: matching recent first (at most 3), then YouTube without repeats', () {
      final m = mergeSuggestions('kes', [
        'Kesariya arijit',
        'tum hi ho',
        'kesariya lofi',
        'Kesariya 8d',
        'kesariya slowed',
      ], [
        'kesariya',
        'KESARIYA LOFI',
        'kesariya song',
      ]);
      expect(m.map((s) => s.text), [
        'Kesariya arijit',
        'kesariya lofi',
        'Kesariya 8d',
        'kesariya',
        'kesariya song',
      ]);
      expect(m.take(3).every((s) => s.recent), isTrue);
    });

    test('never more than twelve lines', () {
      final m = mergeSuggestions('a', [], [for (var i = 0; i < 30; i++) 'a $i']);
      expect(m, hasLength(12));
    });
  });

  group('search history', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('newest first, once whatever the case, and kept on the phone', () async {
      final h = SearchHistoryNotifier();
      await h.add('Kesariya');
      await h.add('tum hi ho');
      await h.add('  kesariya ');
      expect(h.state, ['kesariya', 'tum hi ho']);
      final again = SearchHistoryNotifier();
      await again.loaded;
      expect(again.state, ['kesariya', 'tum hi ho']);
    });

    test('keeps the last 30', () async {
      final h = SearchHistoryNotifier();
      for (var i = 0; i < 40; i++) {
        await h.add('q$i');
      }
      expect(h.state, hasLength(30));
      expect(h.state.first, 'q39');
    });

    test('remove and clear', () async {
      final h = SearchHistoryNotifier();
      await h.add('a');
      await h.add('b');
      await h.remove('a');
      expect(h.state, ['b']);
      await h.clear();
      expect(h.state, isEmpty);
    });

    test('a corrupt saved list starts empty instead of failing', () async {
      SharedPreferences.setMockInitialValues({SearchHistoryNotifier.key: '{oops'});
      final h = SearchHistoryNotifier();
      await h.loaded;
      expect(h.state, isEmpty);
    });

    test('every search is remembered', () async {
      final c = ProviderContainer(overrides: [
        searchServiceProvider.overrideWithValue(_Service()),
      ]);
      addTearDown(c.dispose);
      await c.read(searchProvider.notifier).search('  Kesariya  ');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(searchHistoryProvider), ['Kesariya']);
    });
  });

  group('on Home', () {
    late _Service service;
    late List<String> asked;
    late ProviderContainer container;

    Future<void> openSearch(WidgetTester t, {List<String> recent = const []}) async {
      SharedPreferences.setMockInitialValues({
        SearchHistoryNotifier.key: jsonEncode(recent),
      });
      t.view.physicalSize = const Size(411, 891);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      service = _Service();
      asked = [];
      await t.pumpWidget(ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => FakePlayer()),
          searchServiceProvider.overrideWithValue(service),
          suggestionFetcherProvider.overrideWithValue((q) async {
            asked.add(q);
            return ['$q song', '$q lyrics', '$q arijit singh'];
          }),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ));
      container = ProviderScope.containerOf(t.element(find.byType(HomeScreen)));
      await settle(t);
      await t.tap(find.byType(NoorSearchButton));
      await settle(t);
    }

    testWidgets('opening search shows the recent searches', (t) async {
      await openSearch(t, recent: ['tum hi ho', 'kesariya']);
      expect(find.byType(SearchSuggestions), findsOneWidget);
      expect(find.text('tum hi ho'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsWidgets);
    });

    testWidgets('typing shows YouTube suggestions, asking once for fast typing', (t) async {
      await openSearch(t);
      // A letter every 80 ms, with real 16 ms frames in between.
      Future<void> frames(int n) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 16));
        }
      }

      await t.enterText(find.byType(TextField), 'k');
      await frames(5);
      await t.enterText(find.byType(TextField), 'ke');
      await frames(5);
      await t.enterText(find.byType(TextField), 'kes');
      await frames(5);
      await settle(t);
      expect(asked, ['kes']);
      expect(find.text('kes song', findRichText: true), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsNWidgets(3));
    });

    testWidgets('tapping a suggestion searches it and the list goes away', (t) async {
      await openSearch(t);
      await t.enterText(find.byType(TextField), 'kes');
      await settle(t);
      await t.tap(find.text('kes lyrics', findRichText: true));
      await settle(t);
      expect(service.searched, ['kes lyrics']);
      expect(find.text('Result for kes lyrics'), findsOneWidget);
      expect(find.byIcon(Icons.north_west_rounded), findsNothing);
      expect(container.read(searchHistoryProvider).first, 'kes lyrics');
    });

    testWidgets('the arrow puts a suggestion in the box to keep typing', (t) async {
      await openSearch(t);
      await t.enterText(find.byType(TextField), 'kes');
      await settle(t);
      await t.tap(find.byIcon(Icons.north_west_rounded).at(2));
      await settle(t);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'kes arijit singh ');
      expect(service.searched, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);
    });

    testWidgets('swiping a recent search away forgets it', (t) async {
      await openSearch(t, recent: ['tum hi ho', 'kesariya']);
      await t.drag(find.text('tum hi ho'), const Offset(-400, 0));
      await settle(t);
      expect(find.text('tum hi ho'), findsNothing);
      expect(container.read(searchHistoryProvider), ['kesariya']);
      final saved = (await SharedPreferences.getInstance())
          .getString(SearchHistoryNotifier.key);
      expect(jsonDecode(saved!), ['kesariya']);
    });

    testWidgets('offline: only the recent searches, YouTube is not asked', (t) async {
      await openSearch(t, recent: ['kesariya lofi']);
      container.read(connectionProvider.notifier).reportFailure();
      await t.enterText(find.byType(TextField), 'kes');
      await settle(t);
      expect(asked, isEmpty);
      expect(find.text('kesariya lofi', findRichText: true), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsNothing);
    });

    testWidgets('nothing to suggest: the panel underneath stays visible', (t) async {
      await openSearch(t);
      expect(find.byType(ListView).hitTestable(), findsNothing);
      expect(find.byIcon(Icons.history_rounded), findsNothing);
    });

    testWidgets('back over the results hides the suggestions first', (t) async {
      await openSearch(t);
      await t.enterText(find.byType(TextField), 'kes');
      await t.testTextInput.receiveAction(TextInputAction.search);
      await settle(t);
      await t.tap(find.byType(TextField));
      await settle(t);
      expect(find.byIcon(Icons.north_west_rounded), findsWidgets);
      await t.binding.handlePopRoute();
      await settle(t);
      expect(find.byIcon(Icons.north_west_rounded), findsNothing);
      expect(find.text('Result for kes'), findsOneWidget); // still searching
    });
  });
}

Future<void> settle(WidgetTester t, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
