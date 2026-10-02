import 'package:flutter_test/flutter_test.dart';
import 'package:lanlens/core/net.dart';

void main() {
  group('IPv4', () {
    test('validates', () {
      expect(isValidIPv4('192.168.1.1'), isTrue);
      expect(isValidIPv4('256.1.1.1'), isFalse);
      expect(isValidIPv4('1.2.3'), isFalse);
    });
    test('round-trips int', () {
      expect(intToIp(ipToInt('10.20.30.40')), '10.20.30.40');
    });
    test('private ranges', () {
      expect(isPrivateIPv4('192.168.0.5'), isTrue);
      expect(isPrivateIPv4('172.31.255.1'), isTrue);
      expect(isPrivateIPv4('172.32.0.1'), isFalse);
      expect(isPrivateIPv4('8.8.8.8'), isFalse);
    });
    test('subnet hosts /24 excludes network and broadcast', () {
      final h = subnetHosts('192.168.1.77');
      expect(h.length, 254);
      expect(h.first, '192.168.1.1');
      expect(h.last, '192.168.1.254');
    });
    test('refuses huge sweeps', () {
      expect(() => subnetHosts('10.0.0.1', prefix: 16), throwsArgumentError);
    });
  });

  group('parsePorts', () {
    test('lists and ranges, dedup + sort', () {
      expect(parsePorts('80, 22,20-23'), [20, 21, 22, 23, 80]);
    });
    test('rejects bad input', () {
      expect(() => parsePorts('0'), throwsFormatException);
      expect(() => parsePorts('90-80'), throwsFormatException);
      expect(() => parsePorts('abc'), throwsFormatException);
    });
  });

  test('sanitizeBanner keeps first printable line', () {
    expect(sanitizeBanner('SSH-2.0-OpenSSH_9.6\r\nxx'.codeUnits), 'SSH-2.0-OpenSSH_9.6.');
  });
}
