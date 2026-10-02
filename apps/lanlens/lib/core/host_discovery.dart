import 'dart:async';
import 'dart:io';

import 'net.dart';
import 'pool.dart';

// Finds live hosts on the local subnet with unprivileged TCP connects.
// Android 10+ and iOS block ARP-table access, so a host counts as alive if
// any probe port answers either SYN-ACK (open) or RST (closed).

class DiscoveredHost {
  DiscoveredHost(this.ip, this.latency, this.openPorts);
  final String ip;
  final Duration latency;
  final Set<int> openPorts;
  String? hostname;
}

/// Ports chosen so that nearly every OS/device class answers at least one.
const kDiscoveryPorts = [80, 443, 22, 554, 8080, 62078, 445, 139, 5353, 7000, 9100];

Stream<DiscoveredHost> discoverHosts(
  List<String> hosts, {
  CancelToken? cancel,
  Duration timeout = const Duration(milliseconds: 500),
  void Function(int done)? onProgress,
}) {
  var done = 0;
  return pooled<String, DiscoveredHost?>(hosts, (ip) async {
    DiscoveredHost? found;
    for (final port in kDiscoveryPorts) {
      if (cancel?.isCancelled ?? false) break;
      final r = await tcpProbe(ip, port, timeout: timeout);
      if (r.hostAlive) {
        found ??= DiscoveredHost(ip, r.latency, {});
        if (r.state == ProbeState.open) found.openPorts.add(port);
        // One answer proves liveness; keep going only to record open ports
        // on the first few cheap probes.
        if (found.openPorts.isNotEmpty || port == kDiscoveryPorts[3]) break;
      }
    }
    done++;
    onProgress?.call(done);
    return found;
  }, concurrency: 48, cancel: cancel)
      .where((h) => h != null)
      .cast<DiscoveredHost>();
}

/// Best-effort reverse DNS (works on routers that register DHCP names).
Future<String?> reverseLookup(String ip) async {
  try {
    final r = await InternetAddress(ip).reverse().timeout(const Duration(seconds: 2));
    return r.host == ip ? null : r.host;
  } catch (_) {
    return null;
  }
}
