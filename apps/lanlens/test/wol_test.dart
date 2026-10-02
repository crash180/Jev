import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlens/features/wake_on_lan/wol.dart';

void main() {
  test('parses MAC formats', () {
    const expected = [0xaa, 0xbb, 0xcc, 0x01, 0x02, 0x03];
    for (final s in ['AA:BB:CC:01:02:03', 'aa-bb-cc-01-02-03', 'aabb.cc01.0203', 'aabbcc010203']) {
      expect(parseMac(s), expected);
    }
    expect(() => parseMac('aa:bb:cc'), throwsFormatException);
    expect(formatMac(Uint8List.fromList(expected)), 'AA:BB:CC:01:02:03');
  });

  test('magic packet layout', () {
    final mac = parseMac('11:22:33:44:55:66');
    final p = buildMagicPacket(mac);
    expect(p.length, 102);
    expect(p.sublist(0, 6), List.filled(6, 0xff));
    for (var i = 0; i < 16; i++) {
      expect(p.sublist(6 + i * 6, 12 + i * 6), mac);
    }
    final secure = buildMagicPacket(mac, secureOn: parseSecureOn('192.168.0.1'));
    expect(secure.length, 106);
    expect(secure.sublist(102), [192, 168, 0, 1]);
    expect(() => buildMagicPacket(mac, secureOn: Uint8List(5)), throwsArgumentError);
  });

  test('directed broadcast', () {
    expect(directedBroadcast('192.168.1.42', 24), '192.168.1.255');
    expect(directedBroadcast('10.0.5.9', 22), '10.0.7.255');
  });

  test('target JSON round-trip', () {
    const t = WolTarget(name: 'PC', mac: 'AA:BB:CC:DD:EE:FF', ip: '192.168.1.5', port: 7);
    final r = WolTarget.fromJson(t.toJson());
    expect([r.name, r.mac, r.ip, r.port], ['PC', 'AA:BB:CC:DD:EE:FF', '192.168.1.5', 7]);
  });

  test('packet is delivered over UDP', () async {
    final rx = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final got = Completer<Uint8List>();
    rx.listen((e) {
      if (e == RawSocketEvent.read) {
        final d = rx.receive();
        if (d != null && !got.isCompleted) got.complete(d.data);
      }
    });
    final tx = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    tx.send(buildMagicPacket(parseMac('01:02:03:04:05:06')), InternetAddress.loopbackIPv4, rx.port);
    final data = await got.future.timeout(const Duration(seconds: 2));
    tx.close();
    rx.close();
    expect(data.length, 102);
    expect(data.sublist(6, 12), [1, 2, 3, 4, 5, 6]);
  });
}
