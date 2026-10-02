import 'dart:io';

import '../../core/net.dart';
import '../../core/pool.dart';

/// TCP connect scanner. Connect scans need no root/raw sockets, so they work
/// unprivileged on both Android and iOS.
class PortScanner {
  PortScanner({
    this.timeout = const Duration(milliseconds: 700),
    this.concurrency = 96,
    this.grabBanners = true,
  });

  final Duration timeout;
  final int concurrency;
  final bool grabBanners;

  /// Resolves [target] (hostname or IPv4) to an IPv4 address.
  static Future<String> resolve(String target) async {
    final t = target.trim();
    if (isValidIPv4(t)) return t;
    final addrs = await InternetAddress.lookup(t, type: InternetAddressType.IPv4);
    if (addrs.isEmpty) throw SocketException('Could not resolve $t');
    return addrs.first.address;
  }

  /// Streams one [ProbeResult] per port as each probe finishes.
  Stream<ProbeResult> scan(String ip, List<int> ports, {CancelToken? cancel}) =>
      pooled<int, ProbeResult>(
        ports,
        (p) => tcpProbe(ip, p, timeout: timeout, grabBanner: grabBanners),
        concurrency: concurrency,
        cancel: cancel,
      );
}
