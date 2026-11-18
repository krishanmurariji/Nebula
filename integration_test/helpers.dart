import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Pumps real frames until [finder] finds something or [timeout] passes.
/// Returns whether it was found. Never uses pumpAndSettle: the app has
/// endless animations (spinning records, the timeline).
Future<bool> waitFor(WidgetTester t, Finder finder,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

/// Lets the app run for [d] of real time.
Future<void> idle(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

bool _surfaceReady = false;

/// Saves a screenshot through the driver (build/emulator_shots/<name>.png).
Future<void> shot(IntegrationTestWidgetsFlutterBinding b, WidgetTester t,
    String name) async {
  if (!_surfaceReady) {
    await b.convertFlutterSurfaceToImage();
    _surfaceReady = true;
  }
  await t.pump();
  await b.takeScreenshot(name);
}

/// Prints a line the workflow log shows clearly.
void report(String line) => debugPrint('NOOR-E2E: $line');
