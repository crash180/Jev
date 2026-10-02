import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/net.dart';

// Wake-on-LAN magic packets: 6 × 0xFF followed by the target MAC repeated
// 16 times, optionally followed by a 4- or 6-byte SecureOn password, sent
// as a UDP broadcast (port 9 by convention, 7 as an alternative).

final _hex = RegExp(r'^[0-9a-fA-F]{12}$');

/// Accepts aa:bb:cc:dd:ee:ff, aa-bb-..., aabb.ccdd.eeff or aabbccddeeff.
Uint8List parseMac(String input) {
  final cleaned = input.trim().replaceAll(RegExp(r'[:\-\.\s]'), '');
  if (!_hex.hasMatch(cleaned)) throw FormatException('Invalid MAC address: $input');
  return Uint8List.fromList([
    for (var i = 0; i < 12; i += 2) int.parse(cleaned.substring(i, i + 2), radix: 16),
  ]);
}

String formatMac(Uint8List mac) =>
    mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();

Uint8List buildMagicPacket(Uint8List mac, {Uint8List? secureOn}) {
  if (mac.length != 6) throw ArgumentError('MAC must be 6 bytes');
  if (secureOn != null && secureOn.length != 4 && secureOn.length != 6) {
    throw ArgumentError('SecureOn password must be 4 or 6 bytes');
  }
  final b = BytesBuilder(copy: false)..add(List.filled(6, 0xff));
  for (var i = 0; i < 16; i++) {
    b.add(mac);
  }
  if (secureOn != null) b.add(secureOn);
  return b.toBytes();
}

/// SecureOn passwords are usually written like a MAC (6 bytes) or as an IPv4
/// address (4 bytes).
Uint8List? parseSecureOn(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  if (isValidIPv4(t)) return Uint8List.fromList(t.split('.').map(int.parse).toList());
  return parseMac(t);
}

/// Directed broadcast address for [ip]/[prefix], e.g. 192.168.1.255.
String directedBroadcast(String ip, int prefix) {
  final mask = prefix == 0 ? 0 : (0xffffffff << (32 - prefix)) & 0xffffffff;
  return intToIp((ipToInt(ip) & mask) | (~mask & 0xffffffff));
}

class WolTarget {
  const WolTarget({required this.name, required this.mac, this.ip, this.port = 9, this.secureOn});

  factory WolTarget.fromJson(Map<String, dynamic> j) => WolTarget(
        name: j['name'] as String,
        mac: j['mac'] as String,
        ip: j['ip'] as String?,
        port: (j['port'] as int?) ?? 9,
        secureOn: j['secureOn'] as String?,
      );

  final String name;
  final String mac;

  /// Optional: used for a directed broadcast and to verify the device woke.
  final String? ip;
  final int port;
  final String? secureOn;

  Map<String, dynamic> toJson() =>
      {'name': name, 'mac': mac, 'ip': ip, 'port': port, 'secureOn': secureOn};
}

class WakeOnLan {
  /// Sends the packet [repeat] times to each broadcast destination and returns
  /// the destinations used.
  static Future<List<String>> send(
    WolTarget t, {
    String? localIp,
    int prefix = 24,
    int repeat = 3,
  }) async {
    final packet = buildMagicPacket(parseMac(t.mac),
        secureOn: t.secureOn == null ? null : parseSecureOn(t.secureOn!));
    final destinations = <String>{
      '255.255.255.255',
      if (localIp != null && isValidIPv4(localIp)) directedBroadcast(localIp, prefix),
      if (t.ip != null && isValidIPv4(t.ip!)) directedBroadcast(t.ip!, prefix),
    }.toList();

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.broadcastEnabled = true;
      for (var i = 0; i < repeat; i++) {
        for (final d in destinations) {
          socket.send(packet, InternetAddress(d), t.port);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      socket.close();
    }
    return destinations;
  }

  /// Polls [ip] until any common port answers (open or refused) or [timeout].
  static Future<bool> waitUntilAwake(String ip,
      {Duration timeout = const Duration(seconds: 90), bool Function()? cancelled}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline) && !(cancelled?.call() ?? false)) {
      for (final port in const [445, 22, 3389, 80, 5900, 139]) {
        final r = await tcpProbe(ip, port, timeout: const Duration(milliseconds: 600));
        if (r.hostAlive) return true;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }
}

class WolStore {
  static const _key = 'wol_targets_v1';

  static Future<List<WolTarget>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List) WolTarget.fromJson(j as Map<String, dynamic>)
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<WolTarget> targets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final t in targets) t.toJson()]));
  }
}
