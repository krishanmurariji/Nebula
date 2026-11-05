import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/app_log.dart';
import 'package:nebula_music_player/services/connectivity_probe.dart';

void main() {
  group('ConnectivityProbe', () {
    test('isOnline reflects the check and swallows errors', () async {
      expect(await ConnectivityProbe(check: () async => true).isOnline(), isTrue);
      expect(await ConnectivityProbe(check: () async => false).isOnline(), isFalse);
      expect(
          await ConnectivityProbe(check: () async => throw Exception('x'))
              .isOnline(),
          isFalse);
    });

    test('waitUntilOnline polls until the network returns', () async {
      var checks = 0;
      var waited = 0;
      final p = ConnectivityProbe(
        check: () async => ++checks >= 4,
        delay: (_) async => waited++,
      );
      expect(await p.waitUntilOnline(isCancelled: () => false), isTrue);
      expect(checks, 4);
      expect(waited, 3);
    });

    test('waitUntilOnline stops when cancelled (user moved on)', () async {
      var cancelled = false;
      var checks = 0;
      final p = ConnectivityProbe(
        check: () async {
          checks++;
          return false;
        },
        delay: (_) async {
          if (checks >= 2) cancelled = true;
        },
      );
      expect(await p.waitUntilOnline(isCancelled: () => cancelled), isFalse);
    });
  });

  group('AppLog', () {
    setUp(AppLog.instance.clear);

    test('keeps only the most recent lines', () {
      for (var i = 0; i < AppLog.capacity + 50; i++) {
        AppLog.instance.add('line $i');
      }
      final lines = AppLog.instance.lines;
      expect(lines.length, AppLog.capacity);
      expect(lines.first.endsWith('line 50'), isTrue);
      expect(lines.last.endsWith('line ${AppLog.capacity + 49}'), isTrue);
    });

    test('lines are timestamped and the revision changes', () {
      final before = AppLog.instance.revision.value;
      AppLog.instance.add('hello', now: DateTime(2026, 1, 1, 9, 5, 7, 42));
      expect(AppLog.instance.lines.single, '09:05:07.042  hello');
      expect(AppLog.instance.revision.value, greaterThan(before));
    });
  });
}
