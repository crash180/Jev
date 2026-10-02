import 'package:flutter/material.dart';

import '../../core/local_network.dart';
import '../../core/net.dart';
import '../../ui/widgets.dart';
import 'router_audit.dart';

class RouterCheckScreen extends StatefulWidget {
  const RouterCheckScreen({super.key});

  @override
  State<RouterCheckScreen> createState() => _RouterCheckScreenState();
}

class _RouterCheckScreenState extends State<RouterCheckScreen> {
  final _gateway = TextEditingController();
  RouterReport? _report;
  String? _step;
  String? _error;

  @override
  void initState() {
    super.initState();
    LocalNetwork.read().then((n) {
      if (mounted && n.gateway != null) _gateway.text = n.gateway!;
    });
  }

  @override
  void dispose() {
    _gateway.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final gw = _gateway.text.trim();
    if (!isValidIPv4(gw)) {
      setState(() => _error = 'Enter the router\'s IPv4 address');
      return;
    }
    if (!isPrivateIPv4(gw)) {
      setState(() => _error = 'The router check only runs against a private (LAN) gateway address.');
      return;
    }
    setState(() {
      _error = null;
      _report = null;
      _step = 'Starting…';
    });
    final report = await RouterAuditor().run(gw, onStep: (s) {
      if (mounted) setState(() => _step = s);
    });
    if (mounted) {
      setState(() {
        _report = report;
        _step = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Router Check')),
      body: ListView(children: [
        const AuthorizedUseBanner(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
              controller: _gateway,
              enabled: _step == null,
              decoration: const InputDecoration(
                labelText: 'Router (gateway) IP',
                prefixIcon: Icon(Icons.router_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _step == null ? _run : null,
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Run check'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
        if (_step != null) ...[
          const LinearProgressIndicator(),
          Padding(padding: const EdgeInsets.all(16), child: Text(_step!)),
        ],
        if (r == null && _step == null)
          const EmptyState(
            icon: Icons.router,
            message: 'Checks the router\'s exposed services, admin page and UPnP. '
                'No passwords are tried and nothing is changed.',
          ),
        if (r != null) ...[
          _ScoreCard(r),
          const SectionHeader('Findings'),
          for (final f in r.findings) _FindingTile(f),
          const SizedBox(height: 24),
        ],
      ]),
    );
  }
}

Color severityColor(Severity s) => switch (s) {
      Severity.high => Colors.red,
      Severity.medium => Colors.orange,
      Severity.low => Colors.amber.shade700,
      Severity.info => Colors.blueGrey,
    };

class _ScoreCard extends StatelessWidget {
  const _ScoreCard(this.r);
  final RouterReport r;

  @override
  Widget build(BuildContext context) {
    final color = r.score >= 75 ? Colors.green : (r.score >= 50 ? Colors.orange : Colors.red);
    final u = r.observations.upnp;
    final counts = {
      for (final s in Severity.values) s: r.findings.where((f) => f.severity == s).length
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: r.score / 100,
                  strokeWidth: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(r.grade, style: Theme.of(context).textTheme.headlineSmall),
                Text('${r.score}', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u?.friendlyName ?? u?.model ?? r.observations.gateway,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Open: ${r.observations.openPorts.isEmpty ? 'none' : (r.observations.openPorts.toList()..sort()).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final s in [Severity.high, Severity.medium, Severity.low])
                  if (counts[s]! > 0) Pill('${counts[s]} ${s.name}', severityColor(s)),
                if (counts[Severity.high]! + counts[Severity.medium]! + counts[Severity.low]! == 0)
                  const Pill('no issues', Colors.green),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile(this.f);
  final Finding f;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        leading: Icon(
          f.severity == Severity.info ? Icons.info_outline : Icons.warning_amber_rounded,
          color: severityColor(f.severity),
        ),
        title: Text(f.title),
        subtitle: Text(f.severity.name.toUpperCase(),
            style: TextStyle(color: severityColor(f.severity), fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.detail),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.build_outlined, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(f.fix, style: const TextStyle(fontWeight: FontWeight.w500))),
          ]),
        ],
      );
}
