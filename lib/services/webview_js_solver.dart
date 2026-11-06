import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';
// BaseEJSSolver / EJSBuilder are the library's own "run this JavaScript"
// plug-in point; they are simply not re-exported from the package root.
// ignore: implementation_imports
import 'package:youtube_explode_dart/src/reverse_engineering/challenges/ejs/base_ejs_solver.dart';
// ignore: implementation_imports
import 'package:youtube_explode_dart/src/reverse_engineering/challenges/ejs/ejs.dart';

/// Turns whatever `runJavaScriptReturningResult` gives back into the plain
/// string the solver produced.
///
/// Android returns the result JSON-encoded, so a JavaScript string arrives as
/// `"{\"type\":...}"` (wrapped in quotes and escaped); iOS returns it as is.
String unwrapJsResult(Object? raw) {
  final s = raw?.toString() ?? '';
  if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is String) return decoded;
    } catch (_) {/* not JSON: use as is */}
  }
  return s;
}

/// Where JavaScript actually runs. Abstracted so the solver logic can be
/// tested without a phone.
abstract class JsHost {
  /// Prepares the engine and runs [bootstrap] once (defines the solver).
  Future<void> start(String bootstrap);

  /// Runs [code] and returns its result as a string.
  Future<String> run(String code);

  void dispose();
}

/// Runs JavaScript in an invisible WebView: Android's own Chrome engine (V8).
/// It is fast, maintained by the platform, needs no native library of ours,
/// and does not block the app's UI thread.
class WebViewJsHost implements JsHost {
  WebViewController? _controller;

  @override
  Future<void> start(String bootstrap) async {
    final loaded = Completer<void>();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
        // The page is blank and local: never let it navigate anywhere.
        onNavigationRequest: (req) =>
            req.url.startsWith('about:') || req.url.startsWith('data:')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
      ));
    await controller
        .loadHtmlString('<!doctype html><html><body></body></html>');
    await loaded.future.timeout(const Duration(seconds: 20));
    await controller.runJavaScript(bootstrap);
    _controller = controller;
  }

  @override
  Future<String> run(String code) async {
    final c = _controller;
    if (c == null) throw StateError('JavaScript host not started');
    return unwrapJsResult(await c.runJavaScriptReturningResult(code));
  }

  @override
  void dispose() {
    _controller = null;
  }
}

/// Solves YouTube's "n" and signature challenges on the device.
///
/// Without this, streams from most YouTube clients are throttled to zero or
/// refused with 403, because the library's built-in solver needs the Deno
/// program, which does not exist on a phone.
class WebViewEJSSolver extends BaseEJSSolver {
  WebViewEJSSolver({
    JsHost? host,
    Future<String> Function()? loadModules,
    this.callTimeout = const Duration(seconds: 60),
    this.log,
  })  : _host = host ?? WebViewJsHost(),
        _loadModules = loadModules ?? EJSBuilder.getJSModules;

  final JsHost _host;
  final Future<String> Function() _loadModules;
  final Duration callTimeout;
  final void Function(String message)? log;

  Future<void>? _ready;

  /// Loads the solver and starts the engine so the first song does not pay
  /// for it. Safe to call any number of times; a failure can be retried.
  Future<void> warmUp() => _ensure();

  Future<void> _ensure() {
    final existing = _ready;
    if (existing != null) return existing;
    final f = _start();
    _ready = f;
    // A failed start must not be cached forever: allow the next call to retry.
    f.catchError((Object _) {
      if (identical(_ready, f)) _ready = null;
    });
    return f;
  }

  Future<void> _start() async {
    final t = Stopwatch()..start();
    final modules = await _loadModules();
    await _host.start(modules);
    log?.call('JS solver ready in ${t.elapsedMilliseconds} ms');
  }

  @override
  Future<String> executeJavaScript(String jsCode) async {
    await _ensure();
    final t = Stopwatch()..start();
    final result = await _host.run(jsCode).timeout(callTimeout);
    log?.call('JS solver ran in ${t.elapsedMilliseconds} ms');
    return result;
  }

  @override
  void dispose() {
    _host.dispose();
    _ready = null;
  }
}
