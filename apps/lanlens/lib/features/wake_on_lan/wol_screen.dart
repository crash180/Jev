import 'package:flutter/material.dart';

import '../../core/local_network.dart';
import '../../core/net.dart';
import '../../ui/widgets.dart';
import 'wol.dart';

class WakeOnLanScreen extends StatefulWidget {
  const WakeOnLanScreen({super.key});

  @override
  State<WakeOnLanScreen> createState() => _WakeOnLanScreenState();
}

class _WakeOnLanScreenState extends State<WakeOnLanScreen> {
  List<WolTarget> _targets = [];
  LocalNetwork? _net;
  final Map<String, String> _status = {}; // mac -> status text
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WolStore.load().then((t) {
      if (mounted) setState(() => _targets = t);
    });
    LocalNetwork.read().then((n) {
      if (mounted) setState(() => _net = n);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _wake(WolTarget t) async {
    setState(() => _status[t.mac] = 'Sending magic packet…');
    try {
      final dests = await WakeOnLan.send(t, localIp: _net?.ip, prefix: _net?.prefix ?? 24);
      if (!mounted) return;
      if (t.ip == null) {
        setState(() => _status[t.mac] = 'Sent to ${dests.join(', ')} on UDP ${t.port}');
        return;
      }
      setState(() => _status[t.mac] = 'Sent. Waiting for ${t.ip} to come online…');
      final awake = await WakeOnLan.waitUntilAwake(t.ip!, cancelled: () => _disposed);
      if (mounted) {
        setState(() => _status[t.mac] = awake
            ? '${t.ip} is online'
            : 'No response from ${t.ip} after 90 s. Check WoL is enabled in BIOS/NIC settings.');
      }
    } catch (e) {
      if (mounted) setState(() => _status[t.mac] = 'Failed: $e');
    }
  }

  Future<void> _edit([WolTarget? existing]) async {
    final result = await showModalBottomSheet<WolTarget>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TargetForm(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        _targets[_targets.indexOf(existing)] = result;
      } else {
        _targets.add(result);
      }
    });
    await WolStore.save(_targets);
  }

  Future<void> _delete(WolTarget t) async {
    setState(() => _targets.remove(t));
    await WolStore.save(_targets);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wake on LAN')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add device'),
      ),
      body: ListView(children: [
        if (_targets.isEmpty)
          const EmptyState(
            icon: Icons.power_settings_new,
            message: 'Add a computer by its MAC address to wake it remotely.\n'
                'The target must have Wake-on-LAN enabled in its BIOS/UEFI and network adapter settings.',
          ),
        for (final t in _targets)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.computer)),
                title: Text(t.name),
                subtitle: Text('${t.mac}${t.ip != null ? '  •  ${t.ip}' : ''}  •  UDP ${t.port}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => v == 'edit' ? _edit(t) : _delete(t),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
              if (_status[t.mac] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_status[t.mac]!, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _wake(t),
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Wake'),
                  ),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 96),
      ]),
    );
  }
}

class _TargetForm extends StatefulWidget {
  const _TargetForm({this.existing});
  final WolTarget? existing;

  @override
  State<_TargetForm> createState() => _TargetFormState();
}

class _TargetFormState extends State<_TargetForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _mac = TextEditingController(text: widget.existing?.mac);
  late final _ip = TextEditingController(text: widget.existing?.ip);
  late final _secure = TextEditingController(text: widget.existing?.secureOn);
  late int _port = widget.existing?.port ?? 9;

  @override
  void dispose() {
    for (final c in [_name, _mac, _ip, _secure]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validMac(String? v) {
    try {
      parseMac(v ?? '');
      return null;
    } on FormatException {
      return 'Enter a MAC like AA:BB:CC:DD:EE:FF';
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      WolTarget(
        name: _name.text.trim(),
        mac: formatMac(parseMac(_mac.text)),
        ip: _ip.text.trim().isEmpty ? null : _ip.text.trim(),
        port: _port,
        secureOn: _secure.text.trim().isEmpty ? null : _secure.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.existing == null ? 'Add device' : 'Edit device',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Office PC'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mac,
              decoration: const InputDecoration(labelText: 'MAC address'),
              validator: _validMac,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ip,
              decoration: const InputDecoration(
                  labelText: 'IP address (optional)', helperText: 'Lets LanLens confirm the device woke up'),
              validator: (v) => (v == null || v.trim().isEmpty || isValidIPv4(v)) ? null : 'Invalid IPv4',
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('UDP port'),
              const SizedBox(width: 12),
              SegmentedButton<int>(
                segments: const [ButtonSegment(value: 9, label: Text('9')), ButtonSegment(value: 7, label: Text('7'))],
                selected: {_port},
                onSelectionChanged: (s) => setState(() => _port = s.first),
              ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _secure,
              decoration: const InputDecoration(
                  labelText: 'SecureOn password (optional)', helperText: 'xx:xx:xx:xx:xx:xx or a.b.c.d'),
              validator: (v) {
                try {
                  parseSecureOn(v ?? '');
                  return null;
                } on FormatException {
                  return 'Use 6 hex bytes or a dotted 4-byte value';
                }
              },
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _submit, child: const Text('Save'))),
          ]),
        ),
      );
}
