import 'package:flutter/material.dart';

import '../features/port_scanner/port_scanner_screen.dart';
import '../features/router_check/router_check_screen.dart';
import '../features/speed_test/speed_test_screen.dart';
import '../features/wifi_scanner/wifi_scanner_screen.dart';

/// Registry of the tools shown on the home grid.
class Feature {
  const Feature(this.title, this.subtitle, this.icon, this.builder);
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function() builder;
}

final List<Feature> kFeatures = [
  Feature('Port Scanner', 'Find open TCP ports on a host', Icons.lan_outlined,
      () => const PortScannerScreen()),
  Feature('Router Check', 'Audit your router for risky settings', Icons.router_outlined,
      () => const RouterCheckScreen()),
  Feature('Speed Test', 'Ping, jitter, download and upload', Icons.speed,
      () => const SpeedTestScreen()),
  Feature('Wi-Fi Scanner', 'Nearby access points, channels, security', Icons.wifi_find,
      () => const WifiScannerScreen()),
];
