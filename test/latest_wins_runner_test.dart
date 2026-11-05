import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/latest_wins_runner.dart';

void main() {
  test('50 rapid submissions: one in flight, 48 dropped, last one wins', () async {
    final started = <int>[];
    final finished = <int>[];
    var concurrent = 0;
    var maxConcurrent = 0;

    final runner = LatestWinsRunner<int>((n, ctx) async {
      concurrent++;
      if (concurrent > maxConcurrent) maxConcurrent = concurrent;
      started.add(n);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (ctx.isCurrent) finished.add(n);
      concurrent--;
    });

    for (var i = 0; i < 50; i++) {
      runner.submit(i);
    }
    await runner.idle;

    expect(maxConcurrent, 1, reason: 'loads must never overlap');
    // #0 was already running when the rest arrived; #1-#48 are dropped.
    expect(started, [0, 49], reason: 'only the newest queued request survives');
    expect(finished, [49], reason: '#0 was superseded while running');
    expect(runner.isBusy, isFalse);
  });

  test('a running request is told it was superseded', () async {
    final gate = Completer<void>();
    var firstWasCurrentAtEnd = true;
    var supersededFired = false;

    final runner = LatestWinsRunner<String>((name, ctx) async {
      if (name == 'a') {
        unawaited(ctx.superseded.then((_) => supersededFired = true));
        await gate.future;
        firstWasCurrentAtEnd = ctx.isCurrent;
      }
    });

    runner.submit('a');
    await Future<void>.delayed(Duration.zero);
    runner.submit('b');
    await Future<void>.delayed(Duration.zero);
    expect(supersededFired, isTrue);

    gate.complete();
    await runner.idle;
    expect(firstWasCurrentAtEnd, isFalse);
  });

  test('an exception in one run does not stop later runs', () async {
    final ran = <int>[];
    final runner = LatestWinsRunner<int>((n, ctx) async {
      ran.add(n);
      if (n == 1) throw StateError('boom');
    });

    runner.submit(1);
    await runner.idle;
    runner.submit(2);
    await runner.idle;

    expect(ran, [1, 2]);
  });

  test('cancel drops the queued request', () async {
    final ran = <int>[];
    final gate = Completer<void>();
    final runner = LatestWinsRunner<int>((n, ctx) async {
      ran.add(n);
      if (n == 1) await gate.future;
    });

    runner.submit(1);
    await Future<void>.delayed(Duration.zero);
    runner.submit(2);
    runner.cancel();
    gate.complete();
    await runner.idle;

    expect(ran, [1]);
  });
}
