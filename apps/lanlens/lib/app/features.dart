import 'package:flutter/material.dart';

import '../features/port_scanner/port_scanner_screen.dart';

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
];
