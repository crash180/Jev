import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlens/features/speed_test/speed_tester.dart';

void main() {
  test('stats helpers', () {
    expect(median([5, 1, 3]), 3);
    expect(median([4, 1, 3, 2]), 2.5);
    expect(jitter([10, 12, 11, 15]), closeTo((2 + 1 + 4) / 3, 1e-9));
    expect(mbps(1250000, const Duration(seconds: 1)), closeTo(10, 1e-9));
  });

  test('runs all phases against a local Cloudflare-compatible server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/__down') {
        final n = int.parse(req.uri.queryParameters['bytes'] ?? '0');
        req.response.contentLength = n;
        const chunk = 64 * 1024;
        try {
          for (var sent = 0; sent < n; sent += chunk) {
            req.response.add(List.filled(chunk < n - sent ? chunk : n - sent, 0));
            await req.response.flush();
          }
        } catch (_) {}
        await req.response.close().catchError((_) => null);
      } else {
        await req.drain<void>().catchError((_) => null);
        await req.response.close().catchError((_) => null);
      }
    });

    final tester = SpeedTester(
      server: 'http://127.0.0.1:${server.port}',
      phaseDuration: const Duration(milliseconds: 600),
      streams: 2,
      latencySamples: 4,
    );
    final events = await tester.run().toList();
    await server.close(force: true);

    final r = events.last.result!;
    expect(events.last.phase, SpeedPhase.done);
    expect(r.latencyMs, isNotNull);
    expect(r.downloadMbps, greaterThan(0));
    expect(r.uploadMbps, greaterThan(0));
  });
}
