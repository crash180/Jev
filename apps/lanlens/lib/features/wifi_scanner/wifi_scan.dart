import 'dart:io';

import 'package:flutter/services.dart';

// Nearby Wi-Fi access points. Android exposes scan results to apps holding
// location permission; iOS offers no public API for this, so the scanner
// reports itself unsupported there.

enum WifiBand { ghz24, ghz5, ghz6 }

enum WifiSecurity { open, wep, wpa, wpa2, wpa3, enterprise }

class WifiAp {
  const WifiAp({
    required this.ssid,
    required this.bssid,
    required this.level,
    required this.frequency,
    required this.capabilities,
    this.channelWidthMhz,
    this.connected = false,
  });

  factory WifiAp.fromMap(Map<Object?, Object?> m) => WifiAp(
        ssid: (m['ssid'] as String?) ?? '',
        bssid: (m['bssid'] as String?) ?? '',
        level: (m['level'] as int?) ?? -100,
        frequency: (m['frequency'] as int?) ?? 0,
        capabilities: (m['capabilities'] as String?) ?? '',
        channelWidthMhz: _widthMhz(m['channelWidth'] as int?),
        connected: (m['connected'] as bool?) ?? false,
      );

  final String ssid;
  final String bssid;

  /// RSSI in dBm.
  final int level;
  final int frequency;
  final String capabilities;
  final int? channelWidthMhz;
  final bool connected;

  bool get hidden => ssid.isEmpty;
  int? get channel => channelForFrequency(frequency);
  WifiBand? get band => bandForFrequency(frequency);
  WifiSecurity get security => securityFromCapabilities(capabilities);
  bool get wps => capabilities.contains('WPS');
  int get quality => signalQuality(level);
}

/// Android ScanResult.CHANNEL_WIDTH_* constants → MHz.
int? _widthMhz(int? code) => switch (code) {
      0 => 20,
      1 => 40,
      2 => 80,
      3 => 160,
      4 => 80, // 80+80
      5 => 320,
      _ => null,
    };

WifiBand? bandForFrequency(int mhz) {
  if (mhz >= 2400 && mhz < 2500) return WifiBand.ghz24;
  if (mhz >= 4900 && mhz < 5900) return WifiBand.ghz5;
  if (mhz >= 5925 && mhz <= 7125) return WifiBand.ghz6;
  return null;
}

int? channelForFrequency(int mhz) {
  if (mhz == 2484) return 14;
  if (mhz >= 2412 && mhz < 2484) return (mhz - 2407) ~/ 5;
  if (mhz >= 4910 && mhz <= 5885) return (mhz - 5000) ~/ 5;
  if (mhz == 5935) return 2;
  if (mhz >= 5950 && mhz <= 7115) return (mhz - 5950) ~/ 5;
  return null;
}

/// Parses Android's capability string, e.g. "[WPA2-PSK-CCMP][RSN-SAE-CCMP][WPS][ESS]".
WifiSecurity securityFromCapabilities(String caps) {
  final c = caps.toUpperCase();
  if (c.contains('EAP')) return WifiSecurity.enterprise;
  if (c.contains('SAE') || c.contains('OWE')) return WifiSecurity.wpa3;
  if (c.contains('WPA2') || c.contains('RSN')) return WifiSecurity.wpa2;
  if (c.contains('WPA')) return WifiSecurity.wpa;
  if (c.contains('WEP')) return WifiSecurity.wep;
  return WifiSecurity.open;
}

/// RSSI → 0–100 using the common -100 dBm (0%) to -50 dBm (100%) mapping.
int signalQuality(int dbm) => ((dbm + 100) * 2).clamp(0, 100);

String securityLabel(WifiSecurity s) => switch (s) {
      WifiSecurity.open => 'Open',
      WifiSecurity.wep => 'WEP',
      WifiSecurity.wpa => 'WPA',
      WifiSecurity.wpa2 => 'WPA2',
      WifiSecurity.wpa3 => 'WPA3',
      WifiSecurity.enterprise => 'Enterprise',
    };

class WifiScanResult {
  const WifiScanResult(this.aps, {required this.fresh});
  final List<WifiAp> aps;

  /// False when Android throttled the scan and cached results were returned.
  final bool fresh;
}

class WifiScanException implements Exception {
  const WifiScanException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class WifiScanner {
  static const _channel = MethodChannel('org.lanlens/wifi');

  static bool get supported => Platform.isAndroid;

  static Future<WifiScanResult> scan() async {
    if (!supported) {
      throw const WifiScanException('UNSUPPORTED', 'iOS does not allow apps to list nearby Wi-Fi networks.');
    }
    try {
      final res = await _channel.invokeMapMethod<String, Object?>('scan');
      final list = (res?['results'] as List?) ?? const [];
      final aps = [for (final m in list) WifiAp.fromMap(m as Map<Object?, Object?>)]
        ..sort((a, b) => b.level.compareTo(a.level));
      return WifiScanResult(aps, fresh: res?['fresh'] == true);
    } on PlatformException catch (e) {
      throw WifiScanException(e.code, e.message ?? 'Scan failed');
    }
  }
}
