import 'dart:async';
import 'dart:io';

/// Pure IPv4 / port helpers plus a single TCP probe primitive shared by
/// every scanner in the app.

final _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

bool isValidIPv4(String s) {
  final m = _ipv4.firstMatch(s.trim());
  if (m == null) return false;
  for (var i = 1; i <= 4; i++) {
    if (int.parse(m.group(i)!) > 255) return false;
  }
  return true;
}

int ipToInt(String ip) {
  if (!isValidIPv4(ip)) throw FormatException('Invalid IPv4 address: $ip');
  return ip
      .trim()
      .split('.')
      .map(int.parse)
      .fold(0, (acc, octet) => (acc << 8) | octet);
}

String intToIp(int v) =>
    [24, 16, 8, 0].map((s) => ((v >> s) & 0xff).toString()).join('.');

/// RFC 1918 + link-local + CGNAT. Used to warn before scanning public hosts.
bool isPrivateIPv4(String ip) {
  if (!isValidIPv4(ip)) return false;
  final v = ipToInt(ip);
  bool inRange(String base, int prefix) {
    final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
    return (v & mask) == (ipToInt(base) & mask);
  }

  return inRange('10.0.0.0', 8) ||
      inRange('172.16.0.0', 12) ||
      inRange('192.168.0.0', 16) ||
      inRange('169.254.0.0', 16) ||
      inRange('100.64.0.0', 10) ||
      inRange('127.0.0.0', 8);
}

/// Every usable host address in the subnet containing [ip], excluding the
/// network and broadcast addresses. Prefixes shorter than /22 are refused so
/// a phone never tries to sweep thousands of hosts.
List<String> subnetHosts(String ip, {int prefix = 24}) {
  if (prefix < 22 || prefix > 30) {
    throw ArgumentError.value(prefix, 'prefix', 'must be between 22 and 30');
  }
  final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
  final network = ipToInt(ip) & mask;
  final broadcast = network | (~mask & 0xffffffff);
  return [for (var v = network + 1; v < broadcast; v++) intToIp(v)];
}

/// Parses "22,80,443,8000-8010" into a sorted, de-duplicated port list.
List<int> parsePorts(String spec) {
  final out = <int>{};
  for (final raw in spec.split(',')) {
    final part = raw.trim();
    if (part.isEmpty) continue;
    final range = part.split('-');
    if (range.length == 1) {
      out.add(_port(range[0]));
    } else if (range.length == 2) {
      final a = _port(range[0]), b = _port(range[1]);
      if (a > b) throw FormatException('Bad port range: $part');
      for (var p = a; p <= b; p++) {
        out.add(p);
      }
    } else {
      throw FormatException('Bad port range: $part');
    }
  }
  return out.toList()..sort();
}

int _port(String s) {
  final p = int.tryParse(s.trim());
  if (p == null || p < 1 || p > 65535) {
    throw FormatException('Port out of range: $s');
  }
  return p;
}

enum ProbeState { open, closed, filtered }

class ProbeResult {
  const ProbeResult(this.host, this.port, this.state, this.latency,
      {this.banner});

  final String host;
  final int port;
  final ProbeState state;
  final Duration latency;
  final String? banner;

  /// A refused connection still proves the host is up.
  bool get hostAlive => state != ProbeState.filtered;
}

/// TCP connect probe. "Connection refused" means the host answered with RST
/// (closed port, live host); a timeout means filtered or no host.
/// When [grabBanner] is set, reads whatever the service volunteers on connect.
Future<ProbeResult> tcpProbe(
  String host,
  int port, {
  Duration timeout = const Duration(milliseconds: 800),
  bool grabBanner = false,
}) async {
  final sw = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: timeout);
    final latency = sw.elapsed;
    String? banner;
    if (grabBanner) banner = await _readBanner(socket);
    return ProbeResult(host, port, ProbeState.open, latency, banner: banner);
  } on SocketException catch (e) {
    final refused = _isRefused(e);
    return ProbeResult(
        host, port, refused ? ProbeState.closed : ProbeState.filtered, sw.elapsed);
  } on TimeoutException {
    return ProbeResult(host, port, ProbeState.filtered, sw.elapsed);
  } finally {
    socket?.destroy();
  }
}

bool _isRefused(SocketException e) {
  final code = e.osError?.errorCode;
  // ECONNREFUSED: 111 on Linux/Android, 61 on Darwin/iOS.
  if (code == 111 || code == 61) return true;
  return e.message.toLowerCase().contains('refused') ||
      (e.osError?.message.toLowerCase().contains('refused') ?? false);
}

Future<String?> _readBanner(Socket socket) async {
  final bytes = <int>[];
  try {
    await for (final chunk
        in socket.timeout(const Duration(milliseconds: 600))) {
      bytes.addAll(chunk);
      if (bytes.length >= 256) break;
    }
  } on TimeoutException {
    // Most services wait for the client to speak first; that's fine.
  } on SocketException {
    // Peer reset mid-read.
  }
  if (bytes.isEmpty) return null;
  return sanitizeBanner(bytes);
}

/// Printable-ASCII first line of a raw banner, max 120 chars.
String sanitizeBanner(List<int> bytes) {
  final text = String.fromCharCodes(
      bytes.map((b) => (b >= 0x20 && b < 0x7f) || b == 0x0a ? b : 0x2e));
  final line = text.split('\n').firstWhere((l) => l.trim().isNotEmpty,
      orElse: () => '');
  final t = line.trim();
  return t.length > 120 ? '${t.substring(0, 120)}…' : t;
}
