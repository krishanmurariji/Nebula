import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/progressive_download.dart';

Uint8List _data(int n) => Uint8List.fromList(List.generate(n, (i) => i % 251));

Future<List<int>> _collect(Stream<List<int>> s) async =>
    [for (final c in await s.toList()) ...c];

void main() {
  test('reader gets bytes while the download is still running', () async {
    final src = StreamController<List<int>>();
    final dl = ProgressiveDownload(open: () => src.stream, totalBytes: 100);
    final data = _data(100);

    final got = _collect(dl.read(0));
    src.add(data.sublist(0, 30));
    await Future<void>.delayed(Duration.zero);
    expect(dl.receivedBytes, 30);
    src.add(data.sublist(30, 100));
    await src.close();

    expect(await got, data);
    expect(await dl.completed, data);
  });

  test('seeking: a range can be read at any time, even mid-download', () async {
    final src = StreamController<List<int>>();
    final dl = ProgressiveDownload(open: () => src.stream, totalBytes: 100);
    final data = _data(100);

    final tail = _collect(dl.read(70, 90)); // asked before it exists
    src.add(data.sublist(0, 50));
    src.add(data.sublist(50, 100));
    await src.close();

    expect(await tail, data.sublist(70, 90));
    expect(await _collect(dl.read(10, 20)), data.sublist(10, 20));
  });

  test('two readers share one network open', () async {
    var opens = 0;
    final data = _data(64);
    final dl = ProgressiveDownload(
        open: () {
          opens++;
          return Stream.value(data);
        },
        totalBytes: 64);
    final results = await Future.wait([_collect(dl.read(0)), _collect(dl.read(0))]);
    expect(opens, 1);
    expect(results[0], data);
    expect(results[1], data);
  });

  test('cancel stops the transfer and wakes waiting readers with an error', () async {
    var cancelled = false;
    final src = StreamController<List<int>>(onCancel: () => cancelled = true);
    final dl = ProgressiveDownload(open: () => src.stream, totalBytes: 100);

    final reader = _collect(dl.read(0));
    await Future<void>.delayed(Duration.zero);
    dl.cancel();

    await expectLater(reader, throwsA(isA<StateError>()));
    expect(cancelled, isTrue);
    await expectLater(dl.completed, throwsA(isA<StateError>()));
  });

  test('a network error reaches readers and completed', () async {
    final src = StreamController<List<int>>();
    final dl = ProgressiveDownload(open: () => src.stream, totalBytes: 100);
    final reader = _collect(dl.read(0));
    src.add(_data(10));
    src.addError(Exception('socket closed'));

    await expectLater(reader, throwsException);
    await expectLater(dl.completed, throwsException);
    expect(dl.isFailed, isTrue);
  });

  test('a short download is an error, not a silently truncated song', () async {
    final dl = ProgressiveDownload(
        open: () => Stream.value(_data(40)), totalBytes: 100);
    dl.start();
    await expectLater(dl.completed, throwsStateError);
  });
}
