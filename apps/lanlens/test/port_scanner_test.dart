import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlens/core/net.dart';
import 'package:lanlens/core/pool.dart';
import 'package:lanlens/features/port_scanner/port_scanner.dart';

void main() {
  test('finds an open loopback port and reads its banner', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) {
      s.write('HELLO-LANLENS\r\n');
      s.flush().then((_) => s.close());
    });
    // A port we just released is very likely closed.
    final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final closedPort = tmp.port;
    await tmp.close();

    final results = await PortScanner()
        .scan('127.0.0.1', [server.port, closedPort])
        .toList();
    await server.close();

    final open = results.firstWhere((r) => r.port == server.port);
    expect(open.state, ProbeState.open);
    expect(open.banner, 'HELLO-LANLENS.');
    expect(results.firstWhere((r) => r.port == closedPort).state, ProbeState.closed);
  });

  test('pool respects concurrency and cancellation', () async {
    var inFlight = 0, peak = 0;
    final cancel = CancelToken();
    final out = await pooled<int, int>(List.generate(50, (i) => i), (i) async {
      inFlight++;
      peak = inFlight > peak ? inFlight : peak;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inFlight--;
      if (i == 10) cancel.cancel();
      return i;
    }, concurrency: 4, cancel: cancel).toList();
    expect(peak, lessThanOrEqualTo(4));
    expect(out.length, lessThan(50));
  });
}
