import 'package:flutter/material.dart';

import '../core/local_network.dart';
import 'features.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<LocalNetwork> _network = LocalNetwork.read();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('assets/images/logo.png', height: 28),
          const SizedBox(width: 10),
          const Text('LanLens'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Refresh network info',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _network = LocalNetwork.read()),
          ),
        ],
      ),
      body: ListView(children: [
        FutureBuilder<LocalNetwork>(
          future: _network,
          builder: (context, snap) => _NetworkCard(snap.data),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: [for (final f in kFeatures) _FeatureTile(f)],
          ),
        ),
      ]),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard(this.net);
  final LocalNetwork? net;

  @override
  Widget build(BuildContext context) {
    final n = net;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.wifi, color: scheme.onPrimaryContainer),
        title: Text(n == null ? 'Reading network…' : (n.ssid ?? 'Wi-Fi network'),
            style: TextStyle(color: scheme.onPrimaryContainer)),
        subtitle: Text(
          n == null
              ? ''
              : n.connected
                  ? 'IP ${n.ip}  •  Gateway ${n.gateway ?? '?'}'
                  : 'Not connected to Wi-Fi',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile(this.feature);
  final Feature feature;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => feature.builder())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary,
                child: Icon(feature.icon, color: scheme.onPrimary),
              ),
              const Spacer(),
              Text(feature.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(feature.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
