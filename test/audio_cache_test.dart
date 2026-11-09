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

  group('container-correct file names', () {
    Uint8List webm(int n) {
      final b = Uint8List(n);
      b.setRange(0, 4, [0x1A, 0x45, 0xDF, 0xA3]);
      return b;
    }

    Uint8List mp4(int n) {
      final b = Uint8List(n);
      b.setRange(4, 8, [0x66, 0x74, 0x79, 0x70]);
      return b;
    }

    test('extensionFor picks webm from the EBML header, mp4 otherwise', () {
      expect(AudioCache.extensionFor(webm(100)), 'webm');
      expect(AudioCache.extensionFor(mp4(100)), 'mp4');
      expect(AudioCache.extensionFor(const []), 'mp4');
      expect(AudioCache.extensionFor([0x1A, 0x45]), 'mp4');
    });

    test('a webm song is stored as .webm and an mp4 song as .mp4', () async {
      final c = AudioCache(dir);
      await c.init();
      await c.put('webmsong01', webm(10000));
      await c.put('mp4song0001', mp4(10000));
      expect((await c.lookup('webmsong01'))!.path, endsWith('.webm'));
      expect((await c.lookup('mp4song0001'))!.path, endsWith('.mp4'));
    });

    test('the extension survives a restart', () async {
      final c = AudioCache(dir);
      await c.init();
      await c.put('webmsong01', webm(10000));
      await c.flush();
      final again = AudioCache(dir);
      await again.init();
      expect(again.contains('webmsong01'), isTrue);
      expect((await again.lookup('webmsong01'))!.path, endsWith('.webm'));
    });

    test('remove deletes the webm file too, and re-storing as another container leaves no twin', () async {
      final c = AudioCache(dir);
      await c.init();
      await c.put('song000001', webm(10000));
      await c.remove('song000001');
      expect(File('${dir.path}/song000001.webm').existsSync(), isFalse);

      await c.put('song000002', webm(10000));
      await c.put('song000002', mp4(12000)); // same id, other container
      expect(File('${dir.path}/song000002.webm').existsSync(), isFalse);
      expect(File('${dir.path}/song000002.mp4').existsSync(), isTrue);
      expect((await c.lookup('song000002'))!.path, endsWith('.mp4'));
    });

    test('index entries from the old version (no ext) still load as mp4', () async {
      await dir.create(recursive: true);
      File('${dir.path}/oldsong0001.mp4').writeAsBytesSync(mp4(10000));
      File('${dir.path}/index.json')
          .writeAsStringSync('[{"id":"oldsong0001","sz":10000,"ts":1}]');
      final c = AudioCache(dir);
      await c.init();
      expect((await c.lookup('oldsong0001'))!.path, endsWith('.mp4'));
    });

    test('startup removes orphan webm files too', () async {
      await dir.create(recursive: true);
      File('${dir.path}/orphan0001.webm').writeAsBytesSync(webm(10000));
      final c = AudioCache(dir);
      await c.init();
      expect(File('${dir.path}/orphan0001.webm').existsSync(), isFalse);
    });

    test('eviction removes a webm song completely', () async {
      final c = AudioCache(dir, maxBytes: 15000);
      await c.init();
      await c.put('older00001', webm(10000));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await c.put('newer00001', mp4(10000));
      expect(c.contains('older00001'), isFalse);
      expect(File('${dir.path}/older00001.webm').existsSync(), isFalse);
    });
  });
}
