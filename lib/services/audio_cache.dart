import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class _Entry {
  final String id;
  final int size;
  int lastUsed;

  /// 'mp4' (AAC) or 'webm' (Opus). The extension must match the contents so the
  /// player picks the right decoder instead of having to guess.
  final String ext;
  _Entry(this.id, this.size, this.lastUsed, [this.ext = 'mp4']);

  Map<String, dynamic> toJson() => {'id': id, 'sz': size, 'ts': lastUsed, 'ext': ext};

  static _Entry? tryParse(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final sz = j['sz'];
    final ts = j['ts'];
    if (id is! String || sz is! int || ts is! int) return null;
    final ext = j['ext'] == 'webm' ? 'webm' : 'mp4';
    return _Entry(id, sz, ts, ext);
  }
}

/// On-disk LRU cache of fully downloaded songs.
///
/// Everything is asynchronous (the old cache did blocking file I/O on the UI
/// isolate), files are written to a temp name and renamed so a crash can never
/// leave a half-written song that looks complete, and the song that is
/// currently playing is never evicted.
class AudioCache {
  AudioCache(this.dir, {this.maxBytes = 500 * 1024 * 1024});

  final Directory dir;
  final int maxBytes;

  final Map<String, _Entry> _index = {};
  Timer? _saveTimer;
  int _seq = 0;
  bool _ready = false;

  File get _indexFile => File('${dir.path}/index.json');
  /// The file for [id] (its extension comes from the index; `.mp4` if unknown).
  File fileFor(String id) =>
      File('${dir.path}/$id.${_index[id]?.ext ?? 'mp4'}');

  File _fileWith(String id, String ext) => File('${dir.path}/$id.$ext');

  /// Picks the container from the first bytes: EBML header = webm/opus,
  /// anything else is treated as mp4/m4a.
  static String extensionFor(List<int> bytes) =>
      bytes.length >= 4 &&
              bytes[0] == 0x1A &&
              bytes[1] == 0x45 &&
              bytes[2] == 0xDF &&
              bytes[3] == 0xA3
          ? 'webm'
          : 'mp4';

  /// The id becomes part of a file name, so only plain YouTube-style ids are
  /// allowed. Anything else (e.g. "../../x") is never read, written or deleted.
  static bool isSafeId(String id) => RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id);

  int get count => _index.length;
  int get totalBytes => _index.values.fold(0, (s, e) => s + e.size);

  /// Cheap in-memory check. Use [lookup] before actually playing the file.
  bool contains(String id) => isSafeId(id) && _index.containsKey(id);

  Future<void> init() async {
    await dir.create(recursive: true);

    try {
      if (await _indexFile.exists()) {
        final raw = jsonDecode(await _indexFile.readAsString());
        if (raw is List) {
          for (final item in raw) {
            final e = _Entry.tryParse(item);
            if (e != null &&
                isSafeId(e.id) &&
                await _fileWith(e.id, e.ext).exists()) {
              _index[e.id] = e;
            }
          }
        }
      }
    } catch (_) {
      // Corrupt index: start empty. Orphan files are removed below.
      _index.clear();
    }

    // Remove leftovers: temp files and songs that are not in the index.
    try {
      await for (final f in dir.list()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        final isTmp = name.endsWith('.tmp');
        final dot = name.lastIndexOf('.');
        final ext = dot < 0 ? '' : name.substring(dot + 1);
        final isOrphanSong = (ext == 'mp4' || ext == 'webm') &&
            _index[name.substring(0, dot)]?.ext != ext;
        if (isTmp || isOrphanSong) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}

    _ready = true;
  }

  /// The cached file for [id], or null. Verifies the file really is there and
  /// repairs the index if it is not.
  Future<File?> lookup(String id) async {
    final e = isSafeId(id) ? _index[id] : null;
    if (!_ready || e == null) return null;
    final f = fileFor(id);
    try {
      if (await f.exists() && await f.length() > 4096) {
        e.lastUsed = DateTime.now().millisecondsSinceEpoch;
        _scheduleSave();
        return f;
      }
    } catch (_) {}
    _index.remove(id);
    _scheduleSave();
    return null;
  }

  /// Stores a finished song. Never throws: a failed cache write must not
  /// affect playback.
  Future<void> put(String id, Uint8List bytes,
      {Set<String> protect = const {}}) async {
    if (!_ready || !isSafeId(id) || bytes.length < 4096) return;
    final tmp = File('${dir.path}/$id.${_seq++}.tmp');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      final ext = extensionFor(bytes);
      final old = _index[id];
      await tmp.rename(_fileWith(id, ext).path);
      if (old != null && old.ext != ext) {
        try {
          await _fileWith(id, old.ext).delete();
        } catch (_) {}
      }
      _index[id] =
          _Entry(id, bytes.length, DateTime.now().millisecondsSinceEpoch, ext);
      _scheduleSave();
      await _evict(protect: {id, ...protect});
    } catch (_) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  Future<void> remove(String id) async {
    if (!isSafeId(id)) return;
    _index.remove(id);
    // Delete whichever container the song was stored in (and any stray twin).
    for (final ext in const ['mp4', 'webm']) {
      try {
        await _fileWith(id, ext).delete();
      } catch (_) {}
    }
    _scheduleSave();
  }

  Future<void> clear({Set<String> protect = const {}}) async {
    for (final id in _index.keys.toList()) {
      if (protect.contains(id)) continue;
      await remove(id);
    }
    await flush();
  }

  Future<void> _evict({required Set<String> protect}) async {
    var total = totalBytes;
    if (total <= maxBytes) return;
    final oldestFirst = _index.values.toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    for (final e in oldestFirst) {
      if (total <= maxBytes * 0.8) break;
      if (protect.contains(e.id)) continue;
      total -= e.size;
      await remove(e.id);
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => unawaited(flush()));
  }

  /// Writes the index now (atomically).
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_ready) return;
    try {
      final tmp = File('${dir.path}/index.${_seq++}.tmp');
      await tmp.writeAsString(
          jsonEncode(_index.values.map((e) => e.toJson()).toList()),
          flush: true);
      await tmp.rename(_indexFile.path);
    } catch (_) {}
  }
}
