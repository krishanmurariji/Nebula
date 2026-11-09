import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_music_player/services/network_diagnostics.dart';

final _addr = [InternetAddress('1.2.3.4')];

Future<List<DiagnosticResult>> run({
  Set<String> dnsFail = const {},
  Set<String> dnsHang = const {},
  int status = 200,
  bool httpThrows = false,
}) {
  return runNetworkDiagnostics(
    lookup: (host) async {
      if (dnsHang.contains(host)) {
        await Completer<void>().future; // never completes
      }
      if (dnsFail.contains(host)) throw const SocketException('Failed host lookup');
      return _addr;
    },
    status: (url) async {
      if (httpThrows) throw const SocketException('boom');
      return status;
    },
  );
}

void main() {
  test('healthy network → everything ok and a reassuring verdict', () async {
    final r = await run();
    expect(r.every((e) => e.ok), isTrue);
    expect(adviceFor(r), contains('looks fine'));
  });

  test('YouTube DNS fails while google resolves → points to Private DNS', () async {
    final r = await run(dnsFail: {'www.youtube.com', 'redirector.googlevideo.com'});
    expect(adviceFor(r), allOf(contains('DNS'), contains('dns.google')));
  });

  test('no connectivity at all → says so', () async {
    final r = await run(
      dnsFail: diagnosticHosts.keys.toSet(),
      httpThrows: true,
    );
    expect(adviceFor(r), contains('No internet'));
  });

  test('github unreachable → explains the solver needs it', () async {
    final r = await run(dnsFail: {'github.com'});
    expect(adviceFor(r), contains('JavaScript solver'));
  });

  test('HTTP 429 / 403 / other are told apart', () async {
    expect(adviceFor(await run(status: 429)), contains('rate limiting'));
    expect(adviceFor(await run(status: 403)), contains('refuses'));
    expect(adviceFor(await run(status: 500)), contains('does not answer'));
  });

  test('results never throw, even when everything misbehaves', () async {
    final r = await run(dnsFail: {'github.com'}, httpThrows: true);
    expect(r.length, diagnosticHosts.length + 1);
    expect(r.where((e) => !e.ok), isNotEmpty);
  });
}
