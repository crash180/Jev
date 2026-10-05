import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// HTTP throughput test. Defaults to Cloudflare's public speed endpoints
// (`/__down?bytes=N`, `/__up`), which need no API key; any server exposing
// the same two routes can be configured instead.

const kDefaultSpeedServer = 'https://speed.cloudflare.com';

enum SpeedPhase { latency, download, upload, done }

class SpeedProgress {
  const SpeedProgress(this.phase, {this.currentMbps, this.result, this.fraction = 0});
  final SpeedPhase phase;
  final double? currentMbps;
  final double fraction;
  final SpeedResult? result;
}

class SpeedResult {
  SpeedResult({this.latencyMs, this.jitterMs, this.downloadMbps, this.uploadMbps});
  double? latencyMs;
  double? jitterMs;
  double? downloadMbps;
  double? uploadMbps;
}

double mbps(int bytes, Duration elapsed) =>
    elapsed.inMicroseconds == 0 ? 0 : bytes * 8 / elapsed.inMicroseconds;

double median(List<double> xs) {
  if (xs.isEmpty) throw ArgumentError('empty');
  final s = [...xs]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Mean absolute difference between consecutive samples (RFC 3550 style).
double jitter(List<double> xs) {
  if (xs.length < 2) return 0;
  var sum = 0.0;
  for (var i = 1; i < xs.length; i++) {
    sum += (xs[i] - xs[i - 1]).abs();
  }
  return sum / (xs.length - 1);
}

class SpeedTester {
  SpeedTester({
    this.server = kDefaultSpeedServer,
    this.phaseDuration = const Duration(seconds: 8),
    this.streams = 4,
    this.latencySamples = 10,
  });

  final String server;
  final Duration phaseDuration;
  final int streams;
  final int latencySamples;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Uri _uri(String path, [Map<String, String>? q]) {
    final base = Uri.parse(server);
    return base.replace(path: '${base.path}$path', queryParameters: q);
  }

  Stream<SpeedProgress> run() async* {
    final result = SpeedResult();

    // 1. Latency: tiny requests over a kept-alive connection.
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final samples = <double>[];
    try {
      for (var i = 0; i < latencySamples && !_cancelled; i++) {
        final sw = Stopwatch()..start();
        final res = await (await client.getUrl(_uri('/__down', {'bytes': '0'}))).close();
        await res.drain<void>();
        // First request includes TCP+TLS setup; discard it.
        if (i > 0) samples.add(sw.elapsedMicroseconds / 1000);
        yield SpeedProgress(SpeedPhase.latency, fraction: (i + 1) / latencySamples);
      }
    } finally {
      client.close(force: true);
    }
    if (samples.isNotEmpty) {
      result.latencyMs = median(samples);
      result.jitterMs = jitter(samples);
    }

    // 2. Download, 3. Upload.
    yield* _throughput(SpeedPhase.download, result, _downloadWorker);
    yield* _throughput(SpeedPhase.upload, result, _uploadWorker);
    yield SpeedProgress(SpeedPhase.done, result: result, fraction: 1);
  }

  Stream<SpeedProgress> _throughput(
    SpeedPhase phase,
    SpeedResult result,
    Future<void> Function(HttpClient, Stopwatch, void Function(int)) worker,
  ) async* {
    if (_cancelled) return;
    var bytes = 0;
    final clock = Stopwatch()..start();
    final clients = List.generate(streams, (_) => HttpClient()..connectionTimeout = const Duration(seconds: 5));
    final workers = Future.wait([
      for (final c in clients) worker(c, clock, (n) => bytes += n).catchError((Object _) {}),
    ]);

    // Sample the running total a few times a second for the live gauge.
    while (clock.elapsed < phaseDuration && !_cancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      yield SpeedProgress(phase,
          currentMbps: mbps(bytes, clock.elapsed),
          fraction: (clock.elapsed.inMilliseconds / phaseDuration.inMilliseconds).clamp(0, 1));
    }
    final total = mbps(bytes, clock.elapsed);
    for (final c in clients) {
      c.close(force: true);
    }
    await workers;
    if (phase == SpeedPhase.download) {
      result.downloadMbps = total;
    } else {
      result.uploadMbps = total;
    }
  }

  Future<void> _downloadWorker(HttpClient c, Stopwatch clock, void Function(int) add) async {
    while (clock.elapsed < phaseDuration && !_cancelled) {
      final res = await (await c.getUrl(_uri('/__down', {'bytes': '25000000'}))).close();
      await for (final chunk in res) {
        add(chunk.length);
        if (clock.elapsed >= phaseDuration || _cancelled) return;
      }
    }
  }

  static final Uint8List _payload = Uint8List(256 * 1024);

  Future<void> _uploadWorker(HttpClient c, Stopwatch clock, void Function(int) add) async {
    const perRequest = 8; // chunks of 256 KiB = 2 MiB per POST
    while (clock.elapsed < phaseDuration && !_cancelled) {
      final req = await c.postUrl(_uri('/__up'));
      req.headers.contentType = ContentType.binary;
      req.contentLength = _payload.length * perRequest;
      for (var i = 0; i < perRequest; i++) {
        req.add(_payload);
        await req.flush();
        add(_payload.length);
        if (clock.elapsed >= phaseDuration || _cancelled) return;
      }
      await (await req.close()).drain<void>();
    }
  }
}
