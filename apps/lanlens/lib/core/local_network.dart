import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

import 'net.dart';

/// Snapshot of the phone's current Wi-Fi network.
class LocalNetwork {
  const LocalNetwork({this.ip, this.gateway, this.ssid, this.bssid, this.subnetMask});

  final String? ip;
  final String? gateway;
  final String? ssid;
  final String? bssid;
  final String? subnetMask;

  bool get connected => ip != null && isValidIPv4(ip!);

  /// Prefix length from the reported mask, clamped to what a phone may sweep.
  int get prefix {
    final mask = subnetMask;
    if (mask == null || !isValidIPv4(mask)) return 24;
    final bits = ipToInt(mask).toRadixString(2).replaceAll('0', '').length;
    return bits.clamp(22, 30);
  }

  static Future<LocalNetwork> read() async {
    final info = NetworkInfo();
    String? safe(String? v) {
      if (v == null) return null;
      final t = v.replaceAll('"', '').trim();
      return t.isEmpty || t == '<unknown ssid>' ? null : t;
    }

    try {
      final results = await Future.wait([
        info.getWifiIP(),
        info.getWifiGatewayIP(),
        info.getWifiName(),
        info.getWifiBSSID(),
        info.getWifiSubmask(),
      ]);
      var ip = safe(results[0]);
      ip ??= await _fallbackIp();
      return LocalNetwork(
        ip: ip,
        gateway: safe(results[1]) ?? _guessGateway(ip),
        ssid: safe(results[2]),
        bssid: safe(results[3]),
        subnetMask: safe(results[4]),
      );
    } catch (_) {
      final ip = await _fallbackIp();
      return LocalNetwork(ip: ip, gateway: _guessGateway(ip));
    }
  }

  static Future<String?> _fallbackIp() async {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final iface in ifaces) {
      for (final a in iface.addresses) {
        if (!a.isLoopback && isPrivateIPv4(a.address)) return a.address;
      }
    }
    return null;
  }

  /// Most home routers sit at .1 of the /24.
  static String? _guessGateway(String? ip) {
    if (ip == null || !isValidIPv4(ip)) return null;
    final parts = ip.split('.');
    return '${parts[0]}.${parts[1]}.${parts[2]}.1';
  }
}
