import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/net.dart';
import '../../core/pool.dart';

// Non-intrusive router configuration audit. It only observes what the
// router volunteers to any LAN client: which management ports answer, how
// the admin page is served, and whether UPnP advertises itself. It never
// submits credentials, fuzzes input, or sends exploit payloads.

enum Severity { high, medium, low, info }

class Finding {
  const Finding(this.severity, this.title, this.detail, this.fix);
  final Severity severity;
  final String title;
  final String detail;
  final String fix;
}

class HttpObservation {
  const HttpObservation({
    required this.status,
    this.server,
    this.location,
    this.basicAuth = false,
    this.title,
  });
  final int status;
  final String? server;
  final String? location;
  final bool basicAuth;
  final String? title;

  bool get redirectsToHttps =>
      status >= 300 && status < 400 && (location?.toLowerCase().startsWith('https://') ?? false);
}

class UpnpObservation {
  const UpnpObservation({
    required this.isGateway,
    this.server,
    this.manufacturer,
    this.model,
    this.modelNumber,
    this.friendlyName,
  });
  final bool isGateway;
  final String? server;
  final String? manufacturer;
  final String? model;
  final String? modelNumber;
  final String? friendlyName;
}

/// Raw facts gathered from the network; [evaluate] turns them into findings.
class RouterObservations {
  const RouterObservations({
    required this.gateway,
    required this.reachable,
    required this.openPorts,
    this.http,
    this.upnp,
  });
  final String gateway;
  final bool reachable;
  final Set<int> openPorts;
  final HttpObservation? http;
  final UpnpObservation? upnp;
}

class RouterReport {
  const RouterReport(this.observations, this.findings);
  final RouterObservations observations;
  final List<Finding> findings;

  /// 100 minus weighted penalties, floored at 0.
  int get score {
    const weight = {Severity.high: 30, Severity.medium: 12, Severity.low: 4, Severity.info: 0};
    final penalty = findings.fold<int>(0, (s, f) => s + weight[f.severity]!);
    return (100 - penalty).clamp(0, 100);
  }

  String get grade => switch (score) {
        >= 90 => 'A',
        >= 75 => 'B',
        >= 60 => 'C',
        >= 40 => 'D',
        _ => 'F',
      };
}

/// Ports worth checking on a home router, by what they reveal.
const kRouterPorts = [21, 22, 23, 53, 80, 443, 445, 1900, 5000, 7547, 8080, 8443, 49152];

/// Pure rules engine — no I/O, unit-tested.
List<Finding> evaluate(RouterObservations o) {
  final f = <Finding>[];
  if (!o.reachable) {
    return const [
      Finding(Severity.info, 'Gateway not reachable',
          'No management port answered on the gateway address.',
          'Confirm you are on the router\'s Wi-Fi and that the gateway IP is correct.'),
    ];
  }
  final p = o.openPorts;

  if (p.contains(23)) {
    f.add(const Finding(Severity.high, 'Telnet is enabled',
        'Port 23 answers. Telnet sends passwords in clear text and is a favourite target of IoT botnets such as Mirai.',
        'Disable Telnet in the router admin page; use the web UI over HTTPS or SSH instead.'));
  }
  if (p.contains(21)) {
    f.add(const Finding(Severity.medium, 'FTP service exposed',
        'Port 21 answers. FTP (often a USB-storage share) transmits credentials unencrypted.',
        'Turn off FTP/USB file sharing if unused, or switch to SFTP/SMB3 with a strong password.'));
  }
  if (p.contains(7547)) {
    f.add(const Finding(Severity.medium, 'TR-069 management port reachable',
        'Port 7547 (CWMP) answers on the LAN. It is meant only for your ISP and has a history of remote exploits.',
        'Ask your ISP whether remote management is required; update firmware and disable it if possible.'));
  }
  if (p.contains(445)) {
    f.add(const Finding(Severity.medium, 'SMB file sharing on router',
        'Port 445 answers. Router-hosted SMB shares are frequently outdated (SMBv1).',
        'Disable USB/SMB sharing if unused or make sure SMBv1 is turned off.'));
  }

  final upnpOpen = o.upnp?.isGateway == true || p.contains(1900) || p.contains(5000) || p.contains(49152);
  if (upnpOpen) {
    f.add(const Finding(Severity.medium, 'UPnP is enabled',
        'The router advertises UPnP. Any device or malware on your LAN can silently open inbound ports to the internet.',
        'Disable UPnP unless a game console or app truly needs it; forward specific ports manually instead.'));
  }

  final http = o.http;
  final httpsUi = p.contains(443) || p.contains(8443);
  if (http != null) {
    if (!http.redirectsToHttps) {
      f.add(Finding(
          httpsUi ? Severity.low : Severity.medium,
          'Admin page served over plain HTTP',
          httpsUi
              ? 'HTTPS is available but http:// does not redirect to it, so logins may happen unencrypted.'
              : 'The admin interface is only available over HTTP; anyone sniffing Wi-Fi traffic can capture the password.',
          'Enable HTTPS-only management if your firmware supports it, and always log in via https://.'));
    }
    if (http.basicAuth && !http.redirectsToHttps) {
      f.add(const Finding(Severity.medium, 'HTTP Basic authentication over clear text',
          'The admin page asks for Basic auth on an unencrypted connection; credentials are only base64-encoded.',
          'Use HTTPS for management or upgrade to firmware with a form login over TLS.'));
    }
    if (http.server != null && RegExp(r'\d').hasMatch(http.server!)) {
      f.add(Finding(Severity.low, 'Web server discloses its version',
          'Server header: "${http.server}". Version strings help attackers match known CVEs.',
          'Keep firmware current; check the vendor site for updates for this model.'));
    }
  }

  if (p.contains(22)) {
    f.add(const Finding(Severity.info, 'SSH is enabled',
        'Port 22 answers. Fine if you use it — make sure it uses a strong, non-default password or keys.',
        'Disable SSH if you never use it.'));
  }

  final u = o.upnp;
  if (u != null && (u.model != null || u.manufacturer != null)) {
    f.add(Finding(Severity.info, 'Router identified',
        '${[u.manufacturer, u.model, u.modelNumber].whereType<String>().join(' ')}'
            '${u.server != null ? ' — ${u.server}' : ''}',
        'Look up this model on the manufacturer\'s support site and install the latest firmware.'));
  }
  f.add(const Finding(Severity.info, 'Change default admin password',
      'LanLens never tests passwords. If the admin password is still the one printed on the router label, change it.',
      'Set a unique admin password of 12+ characters and disable remote (WAN) administration.'));

  f.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return f;
}

class RouterAuditor {
  Future<RouterReport> run(String gateway, {void Function(String step)? onStep}) async {
    onStep?.call('Probing management ports…');
    final probes = await pooled<int, ProbeResult>(
      kRouterPorts,
      (port) => tcpProbe(gateway, port, timeout: const Duration(milliseconds: 1200)),
      concurrency: 16,
    ).toList();
    final open = {for (final r in probes) if (r.state == ProbeState.open) r.port};
    final reachable = probes.any((r) => r.hostAlive);

    HttpObservation? http;
    if (open.contains(80) || open.contains(8080)) {
      onStep?.call('Inspecting admin web page…');
      http = await _probeHttp(gateway, open.contains(80) ? 80 : 8080);
    }

    onStep?.call('Listening for UPnP announcements…');
    final upnp = await _probeUpnp(gateway);

    final obs = RouterObservations(
        gateway: gateway, reachable: reachable, openPorts: open, http: http, upnp: upnp);
    return RouterReport(obs, evaluate(obs));
  }

  Future<HttpObservation?> _probeHttp(String host, int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(Uri.parse('http://$host:$port/'));
      req.followRedirects = false;
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .take(8)
          .join()
          .timeout(const Duration(seconds: 3), onTimeout: () => '');
      final title = RegExp(r'<title[^>]*>([^<]{1,80})', caseSensitive: false)
          .firstMatch(body)
          ?.group(1)
          ?.trim();
      return HttpObservation(
        status: res.statusCode,
        server: res.headers.value(HttpHeaders.serverHeader),
        location: res.headers.value(HttpHeaders.locationHeader),
        basicAuth: (res.headers.value(HttpHeaders.wwwAuthenticateHeader) ?? '')
            .toLowerCase()
            .startsWith('basic'),
        title: title,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// SSDP M-SEARCH for an Internet Gateway Device; only answers from the
  /// gateway address count.
  Future<UpnpObservation?> _probeUpnp(String gateway) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      const msg = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 2\r\n'
          'ST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n';
      final data = utf8.encode(msg);
      final dest = InternetAddress('239.255.255.250');
      socket.send(data, dest, 1900);
      socket.send(data, InternetAddress(gateway), 1900);

      final headers = await socket
          .where((e) => e == RawSocketEvent.read)
          .map((_) => socket!.receive())
          .where((d) => d != null && d.address.address == gateway)
          .map((d) => parseSsdpHeaders(utf8.decode(d!.data, allowMalformed: true)))
          .first
          .timeout(const Duration(seconds: 3));

      final location = headers['location'];
      final desc = location == null ? null : await _fetchDescription(location, gateway);
      return UpnpObservation(
        isGateway: true,
        server: headers['server'],
        manufacturer: desc?['manufacturer'],
        model: desc?['modelName'],
        modelNumber: desc?['modelNumber'],
        friendlyName: desc?['friendlyName'],
      );
    } on TimeoutException {
      return null;
    } on StateError {
      return null;
    } on SocketException {
      return null;
    } finally {
      socket?.close();
    }
  }

  Future<Map<String, String>?> _fetchDescription(String location, String gateway) async {
    final uri = Uri.tryParse(location);
    // Only follow description URLs that point back at the gateway itself.
    if (uri == null || uri.host != gateway) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final res = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 4));
      final xml = await res.transform(const Utf8Decoder(allowMalformed: true)).join()
          .timeout(const Duration(seconds: 3));
      return parseDeviceDescription(xml);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// Lower-cased header map from an SSDP/HTTP-over-UDP response.
Map<String, String> parseSsdpHeaders(String raw) {
  final out = <String, String>{};
  for (final line in raw.split(RegExp(r'\r?\n')).skip(1)) {
    final i = line.indexOf(':');
    if (i > 0) out[line.substring(0, i).trim().toLowerCase()] = line.substring(i + 1).trim();
  }
  return out;
}

/// Extracts the first device's identity fields from a UPnP description XML.
Map<String, String> parseDeviceDescription(String xml) {
  final out = <String, String>{};
  for (final tag in ['friendlyName', 'manufacturer', 'modelName', 'modelNumber']) {
    final m = RegExp('<$tag>([^<]{1,100})</$tag>').firstMatch(xml);
    if (m != null) out[tag] = m.group(1)!.trim();
  }
  return out;
}
