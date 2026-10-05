import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/local_network.dart';
import '../../ui/widgets.dart';
import 'wifi_scan.dart';

class WifiScannerScreen extends StatefulWidget {
  const WifiScannerScreen({super.key});

  @override
  State<WifiScannerScreen> createState() => _WifiScannerScreenState();
}

class _WifiScannerScreenState extends State<WifiScannerScreen> {
  WifiScanResult? _result;
  bool _busy = false;
  String? _error;
  WifiBand? _band;

  @override
  void initState() {
    super.initState();
    if (WifiScanner.supported) _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final perm = await Permission.locationWhenInUse.request();
    if (!perm.isGranted) {
      setState(() {
        _busy = false;
        _error = 'Android only shares Wi-Fi scan results with apps that have location permission. '
            'LanLens does not record or upload your location.';
      });
      return;
    }
    try {
      final r = await WifiScanner.scan();
      if (mounted) setState(() => _result = r);
    } on WifiScanException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'PERMISSION'
            ? '${e.message}. Also make sure Location is switched on in quick settings.'
            : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!WifiScanner.supported) return const _IosUnsupported();
    final all = _result?.aps ?? const <WifiAp>[];
    final aps = _band == null ? all : all.where((a) => a.band == _band).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Scanner'),
        actions: [
          IconButton(
            tooltip: 'Rescan',
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _scan,
        child: ListView(children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(label: Text('All (${all.length})'), selected: _band == null,
                  onSelected: (_) => setState(() => _band = null)),
              for (final b in WifiBand.values)
                ChoiceChip(
                  label: Text('${_bandLabel(b)} (${all.where((a) => a.band == b).length})'),
                  selected: _band == b,
                  onSelected: (_) => setState(() => _band = b),
                ),
            ]),
          ),
          if (_result != null && !_result!.fresh)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Android limits apps to 4 scans per 2 minutes; showing the latest cached results.',
                  style: TextStyle(fontSize: 12)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_band != null && aps.isNotEmpty) ...[
            SectionHeader('Channel congestion — ${_bandLabel(_band!)}'),
            _ChannelChart(aps),
          ],
          const SectionHeader('Access points'),
          if (aps.isEmpty && !_busy)
            const EmptyState(icon: Icons.wifi_find, message: 'No networks found. Pull down to rescan.'),
          for (final ap in aps) _ApTile(ap),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

String _bandLabel(WifiBand b) => switch (b) {
      WifiBand.ghz24 => '2.4 GHz',
      WifiBand.ghz5 => '5 GHz',
      WifiBand.ghz6 => '6 GHz',
    };

Color securityColor(WifiSecurity s) => switch (s) {
      WifiSecurity.open || WifiSecurity.wep => Colors.red,
      WifiSecurity.wpa => Colors.orange,
      WifiSecurity.wpa2 => Colors.green,
      WifiSecurity.wpa3 || WifiSecurity.enterprise => Colors.teal,
    };

IconData _signalIcon(int quality) => switch (quality) {
      >= 75 => Icons.network_wifi,
      >= 50 => Icons.network_wifi_3_bar,
      >= 25 => Icons.network_wifi_2_bar,
      _ => Icons.network_wifi_1_bar,
    };

class _ApTile extends StatelessWidget {
  const _ApTile(this.ap);
  final WifiAp ap;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (ap.channel != null) 'Ch ${ap.channel}',
      if (ap.band != null) _bandLabel(ap.band!),
      if (ap.channelWidthMhz != null) '${ap.channelWidthMhz} MHz',
      '${ap.level} dBm',
    ].join(' • ');
    return ListTile(
      leading: Icon(_signalIcon(ap.quality), color: ap.connected ? Theme.of(context).colorScheme.primary : null),
      title: Row(children: [
        Flexible(
          child: Text(ap.hidden ? '(hidden network)' : ap.ssid,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontStyle: ap.hidden ? FontStyle.italic : null,
                  fontWeight: ap.connected ? FontWeight.bold : null)),
        ),
        if (ap.connected) ...[const SizedBox(width: 6), const Icon(Icons.check_circle, size: 16)],
      ]),
      subtitle: Text('${ap.bssid}\n$details'),
      isThreeLine: true,
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Pill(securityLabel(ap.security), securityColor(ap.security)),
        if (ap.wps) ...[const SizedBox(height: 4), const Pill('WPS', Colors.orange)],
      ]),
    );
  }
}

/// Number of access points per channel, with the strongest signal shading the bar.
class _ChannelChart extends StatelessWidget {
  const _ChannelChart(this.aps);
  final List<WifiAp> aps;

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{};
    for (final a in aps) {
      final c = a.channel;
      if (c != null) counts[c] = (counts[c] ?? 0) + 1;
    }
    final channels = counts.keys.toList()..sort();
    final peak = counts.values.fold<int>(1, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 140,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final ch in channels)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${counts[ch]}', style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 2),
                Container(
                  width: 22,
                  height: 90 * counts[ch]! / peak,
                  decoration: BoxDecoration(
                    color: counts[ch]! >= 4 ? Colors.orange : scheme.primary,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
                const SizedBox(height: 4),
                Text('$ch', style: const TextStyle(fontSize: 11)),
              ]),
            ),
        ],
      ),
    );
  }
}

class _IosUnsupported extends StatelessWidget {
  const _IosUnsupported();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Wi-Fi Scanner')),
        body: FutureBuilder<LocalNetwork>(
          future: LocalNetwork.read(),
          builder: (context, snap) => ListView(children: [
            const EmptyState(
              icon: Icons.phone_iphone,
              message: 'iOS does not allow apps to list nearby Wi-Fi networks. '
                  'Below is the network you are connected to. For a full scan, use the Android build.',
            ),
            if (snap.hasData) ...[
              ListTile(leading: const Icon(Icons.wifi), title: const Text('SSID'), subtitle: Text(snap.data!.ssid ?? 'unknown')),
              ListTile(leading: const Icon(Icons.router), title: const Text('BSSID'), subtitle: Text(snap.data!.bssid ?? 'unknown')),
              ListTile(leading: const Icon(Icons.lan), title: const Text('IP / Gateway'),
                  subtitle: Text('${snap.data!.ip ?? '?'} / ${snap.data!.gateway ?? '?'}')),
            ],
          ]),
        ),
      );
}
