import 'dart:collection';

import 'package:flutter/foundation.dart';

/// In-memory ring buffer of recent log lines, shown on the Playback Log screen
/// so problems can be diagnosed on a phone without a USB cable.
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  static const int capacity = 600;
  final ListQueue<String> _lines = ListQueue<String>();

  /// Bumped on every new line so the UI can rebuild.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<String> get lines => List.unmodifiable(_lines);

  void add(String message, {DateTime? now}) {
    final t = (now ?? DateTime.now());
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
    _lines.addLast('$stamp  $message');
    while (_lines.length > capacity) {
      _lines.removeFirst();
    }
    revision.value++;
  }

  void clear() {
    _lines.clear();
    revision.value++;
  }

  String dump() => _lines.join('\n');
}

/// Logs to the console and to the in-app log.
void nlog(String message) {
  debugPrint(message);
  AppLog.instance.add(message);
}
