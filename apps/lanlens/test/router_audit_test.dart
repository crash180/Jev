import 'package:flutter_test/flutter_test.dart';
import 'package:lanlens/features/router_check/router_audit.dart';

RouterObservations obs(Set<int> ports, {HttpObservation? http, UpnpObservation? upnp}) =>
    RouterObservations(gateway: '192.168.1.1', reachable: true, openPorts: ports, http: http, upnp: upnp);

void main() {
  test('telnet + http-only admin + UPnP grades poorly', () {
    final r = RouterReport(
      obs({23, 80, 1900}),
      evaluate(obs({23, 80, 1900},
          http: const HttpObservation(status: 200, server: 'mini_httpd/1.19', basicAuth: true))),
    );
    final titles = r.findings.map((f) => f.title).toList();
    expect(titles, contains('Telnet is enabled'));
    expect(titles, contains('UPnP is enabled'));
    expect(titles, contains('Admin page served over plain HTTP'));
    expect(titles, contains('HTTP Basic authentication over clear text'));
    expect(titles, contains('Web server discloses its version'));
    expect(r.findings.first.severity, Severity.high);
    expect(r.grade, 'F');
  });

  test('HTTPS-redirecting router with nothing extra grades A', () {
    final o = obs({80, 443},
        http: const HttpObservation(status: 302, location: 'https://192.168.1.1/'));
    final r = RouterReport(o, evaluate(o));
    expect(r.findings.where((f) => f.severity != Severity.info), isEmpty);
    expect(r.grade, 'A');
  });

  test('unreachable gateway yields single info finding', () {
    const o = RouterObservations(gateway: '10.0.0.1', reachable: false, openPorts: {});
    expect(evaluate(o).single.severity, Severity.info);
  });

  test('parses SSDP headers and device XML', () {
    final h = parseSsdpHeaders('HTTP/1.1 200 OK\r\nLOCATION: http://192.168.1.1:5000/rootDesc.xml\r\n'
        'SERVER: Linux/3.4 UPnP/1.0 MiniUPnPd/2.1\r\n\r\n');
    expect(h['location'], 'http://192.168.1.1:5000/rootDesc.xml');
    expect(h['server'], contains('MiniUPnPd'));
    final d = parseDeviceDescription(
        '<root><device><friendlyName>Home Router</friendlyName><manufacturer>ACME</manufacturer>'
        '<modelName>AX-3000</modelName></device></root>');
    expect(d, {'friendlyName': 'Home Router', 'manufacturer': 'ACME', 'modelName': 'AX-3000'});
  });
}
