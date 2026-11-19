import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One line of the network check.
class DiagnosticResult {
  const DiagnosticResult(this.name, this.ok, this.millis, this.detail);
  final String name;
  final bool ok;
  final int millis;
  final String detail;

  @override
  String toString() => '${ok ? '✓' : '✗'} $name  ${millis}ms  $detail';
}

/// Hosts whose DNS the app depends on, with the reason.
const diagnosticHosts = <String, String>{
  'www.youtube.com': 'YouTube (search, video info)',
  'youtubei.googleapis.com': 'YouTube player API',
  'redirector.googlevideo.com': 'YouTube audio servers',
  'github.com': 'solver script download',
  'www.google.com': 'general internet',
};

typedef DnsLookup = Future<List<InternetAddress>> Function(String host);
typedef HttpStatus = Future<int> Function(Uri url);

Future<int> _defaultStatus(Uri url) async =>
    (await http.get(url).timeout(const Duration(seconds: 8))).statusCode;

/// Checks DNS for every host the app needs plus one real HTTPS request to
/// YouTube, all in parallel with short timeouts.
Future<List<DiagnosticResult>> runNetworkDiagnostics({
  DnsLookup lookup = InternetAddress.lookup,
  HttpStatus status = _defaultStatus,
}) async {
  Future<DiagnosticResult> dns(String host, String why) async {
    final t = Stopwatch()..start();
    try {
      final r = await lookup(host).timeout(const Duration(seconds: 8));
      return DiagnosticResult('DNS $host', r.isNotEmpty, t.elapsedMilliseconds,
          r.isNotEmpty ? why : 'resolved to nothing');
    } on TimeoutException {
      return DiagnosticResult('DNS $host', false, t.elapsedMilliseconds, 'timed out ($why)');
    } catch (_) {
      return DiagnosticResult('DNS $host', false, t.elapsedMilliseconds, 'lookup failed ($why)');
    }
  }

  Future<DiagnosticResult> https() async {
    final t = Stopwatch()..start();
    try {
      final code = await status(Uri.parse('https://www.youtube.com/robots.txt'));
      return DiagnosticResult('HTTPS youtube.com', code == 200, t.elapsedMilliseconds, 'HTTP $code');
    } on TimeoutException {
      return DiagnosticResult('HTTPS youtube.com', false, t.elapsedMilliseconds, 'timed out');
    } catch (e) {
      return DiagnosticResult(
          'HTTPS youtube.com', false, t.elapsedMilliseconds, e.runtimeType.toString());
    }
  }

  return Future.wait([
    for (final e in diagnosticHosts.entries) dns(e.key, e.value),
    https(),
  ]);
}

/// Plain-language conclusion for a list of results.
String adviceFor(List<DiagnosticResult> results) {
  DiagnosticResult? find(String name) {
    for (final r in results) {
      if (r.name == name) return r;
    }
    return null;
  }

  final google = find('DNS www.google.com');
  final youtube = find('DNS www.youtube.com');
  final api = find('DNS youtubei.googleapis.com');
  final media = find('DNS redirector.googlevideo.com');
  final github = find('DNS github.com');
  final http = find('HTTPS youtube.com');

  if (results.every((r) => !r.ok)) {
    return 'No internet connection. Check Wi-Fi or mobile data.';
  }
  final failedYoutubeDns = [youtube, api, media].any((r) => r != null && !r.ok);
  if (google != null && google.ok && failedYoutubeDns) {
    return 'Your network resolves general sites but NOT YouTube. This is a DNS '
        'problem on this Wi-Fi/ISP. Fix: Settings → Connections → More '
        'connection settings → Private DNS → "Private DNS provider hostname" → '
        'dns.google. Or switch to mobile data.';
  }
  if (github != null && !github.ok) {
    return 'github.com cannot be reached, so the JavaScript solver cannot '
        'download its script. Fix DNS (see Private DNS: dns.google).';
  }
  if (http != null && !http.ok) {
    if (http.detail.contains('429')) {
      return 'YouTube is rate limiting this network (HTTP 429). Wait an hour or '
          'switch to mobile data.';
    }
    if (http.detail.contains('403')) {
      return 'YouTube refuses requests from this network (HTTP 403). Try mobile '
          'data.';
    }
    return 'DNS works but YouTube does not answer over HTTPS (${http.detail}). '
        'Try mobile data.';
  }
  return 'The network looks fine. If songs still fail, YouTube is refusing the '
      'audio download for this IP (look for "403" or "unplayable" in the log).';
}
