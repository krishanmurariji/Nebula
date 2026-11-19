import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nebula_music_player/services/webview_js_solver.dart';
import 'package:youtube_explode_dart/src/reverse_engineering/challenges/js_challenge.dart';

class FakeHost implements JsHost {
  int starts = 0;
  final List<String> bootstraps = [];
  final List<String> codes = [];
  Object? startError;
  Duration runDelay = Duration.zero;
  String Function(String code) respond = (c) => '{}';
  bool disposed = false;

  @override
  Future<void> start(String bootstrap) async {
    starts++;
    bootstraps.add(bootstrap);
    final e = startError;
    if (e != null) throw e;
  }

  @override
  Future<String> run(String code) async {
    codes.add(code);
    if (runDelay > Duration.zero) await Future<void>.delayed(runDelay);
    return respond(code);
  }

  @override
  void dispose() => disposed = true;
}

String ejsReply(Map<String, String?> solved, {String? preprocessed}) => jsonEncode({
      'type': 'result',
      'responses': [
        {'type': 'result', 'data': solved}
      ],
      if (preprocessed != null) 'preprocessed_player': preprocessed,
    });

void main() {
  group('unwrapJsResult', () {
    test('Android: JSON-encoded string result is unwrapped', () {
      final inner = '{"type":"result","a":"b"}';
      expect(unwrapJsResult(jsonEncode(inner)), inner);
    });

    test('iOS: plain string result is left alone', () {
      expect(unwrapJsResult('{"type":"result"}'), '{"type":"result"}');
    });

    test('odd input never throws', () {
      expect(unwrapJsResult(null), '');
      expect(unwrapJsResult(''), '');
      expect(unwrapJsResult('"'), '"');
      expect(unwrapJsResult('"unterminated'), '"unterminated');
      expect(unwrapJsResult(42), '42');
      expect(unwrapJsResult('"not \\ valid json"'), '"not \\ valid json"');
    });

    test('a number or object wrapped in quotes that is not a string stays as is', () {
      expect(unwrapJsResult('"123"'), '123');
    });
  });

  group('WebViewEJSSolver engine lifecycle', () {
    test('starts the engine once, even for concurrent first calls', () async {
      final host = FakeHost();
      final s = WebViewEJSSolver(host: host, loadModules: () async => 'MODULES');
      await Future.wait([s.executeJavaScript('1'), s.executeJavaScript('2'), s.executeJavaScript('3')]);
      expect(host.starts, 1);
      expect(host.bootstraps.single, 'MODULES');
      expect(host.codes, ['1', '2', '3']);
    });

    test('warmUp prepares the engine ahead of the first call', () async {
      final host = FakeHost();
      final s = WebViewEJSSolver(host: host, loadModules: () async => 'M');
      await s.warmUp();
      expect(host.starts, 1);
      await s.executeJavaScript('x');
      expect(host.starts, 1);
    });

    test('a failed start is retried on the next call, not cached forever', () async {
      final host = FakeHost()..startError = StateError('webview unavailable');
      var loads = 0;
      final s = WebViewEJSSolver(host: host, loadModules: () async {
        loads++;
        return 'M';
      });
      await expectLater(s.executeJavaScript('x'), throwsStateError);
      host.startError = null;
      expect(await s.executeJavaScript('ok'), '{}');
      expect(loads, 2);
      expect(host.starts, 2);
    });

    test('modules that cannot be downloaded (offline) surface as an error, then recover', () async {
      final host = FakeHost();
      var offline = true;
      final s = WebViewEJSSolver(host: host, loadModules: () async {
        if (offline) throw const FormatException('no network');
        return 'M';
      });
      await expectLater(s.warmUp(), throwsFormatException);
      offline = false;
      await s.warmUp();
      expect(host.starts, 1);
    });

    test('a hung JavaScript call times out instead of blocking forever', () async {
      final host = FakeHost()..runDelay = const Duration(seconds: 5);
      final s = WebViewEJSSolver(
          host: host, loadModules: () async => 'M', callTimeout: const Duration(milliseconds: 100));
      await expectLater(s.executeJavaScript('slow'), throwsA(isA<TimeoutException>()));
    });

    test('dispose releases the host and allows a later restart', () async {
      final host = FakeHost();
      final s = WebViewEJSSolver(host: host, loadModules: () async => 'M');
      await s.warmUp();
      s.dispose();
      expect(host.disposed, isTrue);
      await s.warmUp();
      expect(host.starts, 2);
    });
  });

  group("end to end through the library's own challenge handling", () {
    test('solves an n challenge, caches it, and reuses the preprocessed player', () async {
      final host = FakeHost();
      host.respond = (code) => ejsReply({'abc': 'SOLVED'}, preprocessed: 'PREPROCESSED');
      final s = WebViewEJSSolver(host: host, loadModules: () async => 'M');
      final playerFetches = <Uri>[];

      await http.runWithClient(() async {
        final a = await s.solve('https://yt.example/player.js', JSChallengeType.n, 'abc');
        expect(a, 'SOLVED');
        // Same challenge again: answered from the cache, no JavaScript at all.
        final again = await s.solve('https://yt.example/player.js', JSChallengeType.n, 'abc');
        expect(again, 'SOLVED');
        expect(host.codes.length, 1);

        // A new challenge for the same player must reuse the preprocessed player
        host.respond = (code) => ejsReply({'xyz': 'SOLVED2'});
        final b = await s.solve('https://yt.example/player.js', JSChallengeType.n, 'xyz');
        expect(b, 'SOLVED2');
      }, () => MockClient((req) async {
            playerFetches.add(req.url);
            return http.Response('/* player script */', 200);
          }));

      expect(host.codes.length, 2);
      expect(host.codes.first, contains('"type":"player"'));
      expect(host.codes.last, contains('"type":"preprocessed"'));
      expect(host.codes.last, contains('PREPROCESSED'));
      expect(playerFetches.length, 1, reason: 'the 2 MB player is downloaded once');
    });

    test('an unsolvable challenge is reported as an error, not silently ignored', () async {
      final host = FakeHost()..respond = (code) => ejsReply({'abc': null});
      final s = WebViewEJSSolver(host: host, loadModules: () async => 'M');
      await http.runWithClient(() async {
        await expectLater(
            s.solve('https://yt.example/p.js', JSChallengeType.n, 'abc'), throwsException);
      }, () => MockClient((req) async => http.Response('x', 200)));
    });

    test('garbage from the JavaScript side raises an error instead of hanging', () async {
      final host = FakeHost()..respond = (code) => 'not json at all';
      final s = WebViewEJSSolver(host: host, loadModules: () async => 'M');
      await http.runWithClient(() async {
        await expectLater(
            s.solve('https://yt.example/p.js', JSChallengeType.n, 'abc'), throwsA(anything));
      }, () => MockClient((req) async => http.Response('x', 200)));
    });
  });
}
