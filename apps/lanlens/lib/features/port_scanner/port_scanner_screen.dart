import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/local_network.dart';
import '../../core/net.dart';
import '../../core/pool.dart';
import '../../core/ports.dart';
import '../../ui/widgets.dart';
import 'port_scanner.dart';

class PortScannerScreen extends StatefulWidget {
  const PortScannerScreen({super.key, this.initialHost});
  final String? initialHost;

  @override
  State<PortScannerScreen> createState() => _PortScannerScreenState();
}

class _PortScannerScreenState extends State<PortScannerScreen> {
  final _host = TextEditingController();
  final _custom = TextEditingController(text: '1-1024,3389,5900,8080');
  PortPreset _preset = PortPreset.common;

  CancelToken? _cancel;
  StreamSubscription<ProbeResult>? _sub;
  final List<ProbeResult> _open = [];
  int _done = 0, _total = 0, _closed = 0;
  String? _error;
  DateTime? _started;
  Duration? _elapsed;

  bool get _running => _sub != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialHost != null) {
      _host.text = widget.initialHost!;
    } else {
      LocalNetwork.read().then((n) {
        if (mounted && _host.text.isEmpty && n.gateway != null) {
          _host.text = n.gateway!;
        }
      });
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _sub?.cancel();
    _host.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    List<int> ports;
    try {
      ports = _preset == PortPreset.custom ? parsePorts(_custom.text) : portsForPreset(_preset);
      if (ports.isEmpty) throw const FormatException('No ports selected');
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }

    String ip;
    try {
      ip = await PortScanner.resolve(_host.text);
    } catch (e) {
      setState(() => _error = 'Could not resolve "${_host.text.trim()}"');
      return;
    }
    if (!mounted || !await confirmPublicTarget(context, ip)) return;

    final cancel = CancelToken();
    setState(() {
      _cancel = cancel;
      _open.clear();
      _done = 0;
      _closed = 0;
      _total = ports.length;
      _started = DateTime.now();
      _elapsed = null;
    });

    _sub = PortScanner().scan(ip, ports, cancel: cancel).listen(
      (r) => setState(() {
        _done++;
        if (r.state == ProbeState.open) {
          _open
            ..add(r)
            ..sort((a, b) => a.port.compareTo(b.port));
        } else if (r.state == ProbeState.closed) {
          _closed++;
        }
      }),
      onDone: _finish,
      onError: (Object e) => setState(() => _error = '$e'),
    );
  }

  void _finish() {
    if (!mounted) return;
    setState(() {
      _elapsed = DateTime.now().difference(_started!);
      _sub = null;
      _cancel = null;
    });
  }

  void _stop() {
    _cancel?.cancel();
    _sub?.cancel();
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Port Scanner')),
      body: ListView(children: [
        const AuthorizedUseBanner(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
              controller: _host,
              enabled: !_running,
              decoration: const InputDecoration(
                labelText: 'Host or IP',
                hintText: '192.168.1.1',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            SegmentedButton<PortPreset>(
              segments: [
                for (final p in PortPreset.values)
                  ButtonSegment(value: p, label: Text(p.label, style: const TextStyle(fontSize: 12))),
              ],
              selected: {_preset},
              onSelectionChanged: _running ? null : (s) => setState(() => _preset = s.first),
            ),
            if (_preset == PortPreset.custom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _custom,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: 'Ports',
                  helperText: 'Comma-separated, ranges allowed (e.g. 22,80,8000-8100)',
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _running
                  ? OutlinedButton.icon(
                      onPressed: _stop, icon: const Icon(Icons.stop), label: const Text('Stop'))
                  : FilledButton.icon(
                      onPressed: _start, icon: const Icon(Icons.radar), label: const Text('Scan')),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
        if (_total > 0) ...[
          LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '$_done / $_total probed  •  ${_open.length} open  •  $_closed closed  •  '
              '${_done - _open.length - _closed} filtered'
              '${_elapsed != null ? '  •  ${(_elapsed!.inMilliseconds / 1000).toStringAsFixed(1)} s' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        const SectionHeader('Open ports'),
        if (_open.isEmpty)
          EmptyState(
            icon: Icons.lock_outline,
            message: _total == 0
                ? 'Enter a host and tap Scan.'
                : _running
                    ? 'Scanning…'
                    : 'No open ports found.',
          ),
        for (final r in _open) _OpenPortTile(r),
      ]),
    );
  }
}

class _OpenPortTile extends StatelessWidget {
  const _OpenPortTile(this.r);
  final ProbeResult r;

  @override
  Widget build(BuildContext context) {
    final risky = const {21, 23, 135, 139, 445, 1900, 3389, 5900, 7547}.contains(r.port);
    return ListTile(
      leading: CircleAvatar(child: Text('${r.port}', style: const TextStyle(fontSize: 11))),
      title: Row(children: [
        Text(serviceName(r.port)),
        const SizedBox(width: 8),
        if (risky) const Pill('review', Colors.orange),
      ]),
      subtitle: Text(r.banner ?? '${r.latency.inMilliseconds} ms'),
      trailing: IconButton(
        tooltip: 'Copy',
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () => Clipboard.setData(ClipboardData(text: '${r.host}:${r.port}')),
      ),
    );
  }
}
