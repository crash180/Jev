import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'speed_tester.dart';

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> {
  final _server = TextEditingController(text: kDefaultSpeedServer);
  SpeedTester? _tester;
  StreamSubscription<SpeedProgress>? _sub;
  SpeedPhase? _phase;
  double _gauge = 0, _fraction = 0;
  final _result = SpeedResult();
  String? _error;

  bool get _running => _sub != null;

  @override
  void dispose() {
    _tester?.cancel();
    _sub?.cancel();
    _server.dispose();
    super.dispose();
  }

  void _start() {
    final tester = SpeedTester(server: _server.text.trim());
    setState(() {
      _tester = tester;
      _error = null;
      _gauge = 0;
      _result
        ..latencyMs = null
        ..jitterMs = null
        ..downloadMbps = null
        ..uploadMbps = null;
    });
    _sub = tester.run().listen((p) {
      setState(() {
        if (p.phase != _phase) _gauge = 0;
        _phase = p.phase;
        _fraction = p.fraction;
        if (p.currentMbps != null) {
          _gauge = p.currentMbps!;
          if (p.phase == SpeedPhase.download) _result.downloadMbps = p.currentMbps;
          if (p.phase == SpeedPhase.upload) _result.uploadMbps = p.currentMbps;
        }
        final r = p.result;
        if (r != null) {
          _result
            ..latencyMs = r.latencyMs
            ..jitterMs = r.jitterMs
            ..downloadMbps = r.downloadMbps
            ..uploadMbps = r.uploadMbps;
        }
      });
    }, onError: (Object e) {
      setState(() => _error = 'Test failed: $e');
      _stop();
    }, onDone: _stop);
  }

  void _stop() {
    _tester?.cancel();
    _sub?.cancel();
    if (mounted) setState(() => _sub = null);
  }

  String _phaseLabel() => switch (_phase) {
        SpeedPhase.latency => 'Measuring latency…',
        SpeedPhase.download => 'Download',
        SpeedPhase.upload => 'Upload',
        SpeedPhase.done => 'Complete',
        null => 'Ready',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Speed Test')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AspectRatio(
          aspectRatio: 1.4,
          child: CustomPaint(
            painter: _GaugePainter(_gauge, scheme.primary, scheme.surfaceContainerHighest),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 30),
                Text(_gauge.toStringAsFixed(_gauge < 10 ? 1 : 0),
                    style: Theme.of(context).textTheme.displayMedium),
                Text('Mbps  •  ${_phaseLabel()}'),
              ]),
            ),
          ),
        ),
        if (_running) LinearProgressIndicator(value: _fraction),
        const SizedBox(height: 16),
        Row(children: [
          _Metric('Ping', _result.latencyMs, 'ms', Icons.timer_outlined),
          _Metric('Jitter', _result.jitterMs, 'ms', Icons.stacked_line_chart),
        ]),
        Row(children: [
          _Metric('Download', _result.downloadMbps, 'Mbps', Icons.download),
          _Metric('Upload', _result.uploadMbps, 'Mbps', Icons.upload),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _running
              ? OutlinedButton.icon(onPressed: _stop, icon: const Icon(Icons.stop), label: const Text('Stop'))
              : FilledButton.icon(
                  onPressed: _start, icon: const Icon(Icons.speed), label: const Text('Start test')),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Server'),
          subtitle: Text(_server.text, maxLines: 1, overflow: TextOverflow.ellipsis),
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _server,
                enabled: !_running,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  helperText: 'Must serve /__down?bytes=N and /__up (Cloudflare-compatible)',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('A test transfers roughly 50–500 MB depending on your speed. '
              'Use Wi-Fi to avoid mobile data charges.',
              style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.unit, this.icon);
  final String label;
  final double? value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(label, style: Theme.of(context).textTheme.bodySmall),
            subtitle: Text(
              value == null ? '—' : '${value!.toStringAsFixed(value! < 10 ? 1 : 0)} $unit',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      );
}

/// 240° arc on a log scale from 1 to 1000 Mbps.
class _GaugePainter extends CustomPainter {
  _GaugePainter(this.mbps, this.color, this.track);
  final double mbps;
  final Color color;
  final Color track;

  static const _start = math.pi * 5 / 6, _sweep = math.pi * 4 / 3;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height * 1.3) / 2 - 12;
    final center = Offset(size.width / 2, size.height * 0.58);
    final rect = Rect.fromCircle(center: center, radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, base..color = track);
    final t = mbps <= 1 ? 0.0 : (math.log(mbps) / math.log(1000)).clamp(0.0, 1.0);
    if (t > 0) canvas.drawArc(rect, _start, _sweep * t, false, base..color = color);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final (label, v) in [('1', 0.0), ('10', 1 / 3), ('100', 2 / 3), ('1G', 1.0)]) {
      final a = _start + _sweep * v;
      final p = center + Offset(math.cos(a), math.sin(a)) * (r - 30);
      tp
        ..text = TextSpan(text: label, style: TextStyle(color: track.computeLuminance() > 0.5 ? Colors.black54 : Colors.white70, fontSize: 11))
        ..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.mbps != mbps || old.color != color;
}
