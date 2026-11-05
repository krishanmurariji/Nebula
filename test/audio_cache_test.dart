import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/audio_cache.dart';

Uint8List _bytes(int n) => Uint8List(n);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nebula_cache_test');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('put then lookup returns the file; unknown id returns null', () async {
    final c = AudioCache(dir);
    await c.init();
    await c.put('abc', _bytes(10000));
    expect(c.contains('abc'), isTrue);
    expect((await c.lookup('abc'))!.lengthSync(), 10000);
    expect(await c.lookup('nope'), isNull);
  });

  test('index survives a restart', () async {
    final c = AudioCache(dir);
    await c.init();
    await c.put('abc', _bytes(10000));
    await c.flush();

    final again = AudioCache(dir);
    await again.init();
    expect(again.contains('abc'), isTrue);
    expect(again.count, 1);
  });

  test('startup removes leftover .tmp files and orphan songs', () async {
    await File('${dir.path}/x.1.tmp').writeAsBytes(_bytes(10));
    await File('${dir.path}/orphan.mp4').writeAsBytes(_bytes(10000));
    final c = AudioCache(dir);
    await c.init();
    expect(File('${dir.path}/x.1.tmp').existsSync(), isFalse);
    expect(File('${dir.path}/orphan.mp4').existsSync(), isFalse);
    expect(c.count, 0);
  });

  test('a deleted file is dropped from the index on lookup', () async {
    final c = AudioCache(dir);
    await c.init();
    await c.put('abc', _bytes(10000));
    c.fileFor('abc').deleteSync();
    expect(await c.lookup('abc'), isNull);
    expect(c.contains('abc'), isFalse);
  });

  test('corrupt index does not crash startup', () async {
    await File('${dir.path}/index.json').writeAsString('{{ not json');
    final c = AudioCache(dir);
    await c.init();
    expect(c.count, 0);
  });

  test('evicts least recently used first and never the protected song', () async {
    final c = AudioCache(dir, maxBytes: 25000);
    await c.init();
    await c.put('a', _bytes(10000));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await c.put('b', _bytes(10000));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await c.lookup('a'); // 'a' is now newer than 'b'
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await c.put('c', _bytes(10000), protect: {'b'}); // over budget

    expect(c.contains('b'), isTrue, reason: 'protected (currently playing)');
    expect(c.contains('c'), isTrue, reason: 'just written');
    expect(c.contains('a'), isFalse, reason: 'oldest unprotected is evicted');
  });

  test('tiny payloads are not cached', () async {
    final c = AudioCache(dir);
    await c.init();
    await c.put('t', _bytes(100));
    expect(c.contains('t'), isFalse);
  });

  test('clear removes everything except protected ids', () async {
    final c = AudioCache(dir);
    await c.init();
    await c.put('a', _bytes(10000));
    await c.put('b', _bytes(10000));
    await c.clear(protect: {'b'});
    expect(c.contains('a'), isFalse);
    expect(c.contains('b'), isTrue);
  });
}
