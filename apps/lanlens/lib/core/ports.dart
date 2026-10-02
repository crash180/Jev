// Well-known TCP ports and the presets the port scanner offers.

const Map<int, String> kServiceNames = {
  20: 'FTP data',
  21: 'FTP',
  22: 'SSH',
  23: 'Telnet',
  25: 'SMTP',
  53: 'DNS',
  67: 'DHCP',
  80: 'HTTP',
  81: 'HTTP alt',
  110: 'POP3',
  111: 'RPCbind',
  135: 'MS RPC',
  137: 'NetBIOS',
  139: 'NetBIOS/SMB',
  143: 'IMAP',
  161: 'SNMP',
  389: 'LDAP',
  443: 'HTTPS',
  445: 'SMB',
  465: 'SMTPS',
  515: 'LPD printer',
  548: 'AFP',
  554: 'RTSP',
  587: 'SMTP submission',
  631: 'IPP printer',
  873: 'rsync',
  993: 'IMAPS',
  995: 'POP3S',
  1080: 'SOCKS',
  1194: 'OpenVPN',
  1433: 'MS SQL',
  1723: 'PPTP',
  1883: 'MQTT',
  1900: 'UPnP',
  2049: 'NFS',
  3000: 'Dev HTTP',
  3306: 'MySQL',
  3389: 'RDP',
  3702: 'WS-Discovery',
  5000: 'UPnP / HTTP',
  5060: 'SIP',
  5353: 'mDNS',
  5432: 'PostgreSQL',
  5900: 'VNC',
  6379: 'Redis',
  7547: 'TR-069 (CWMP)',
  8000: 'HTTP alt',
  8008: 'HTTP alt',
  8009: 'Chromecast',
  8080: 'HTTP proxy',
  8081: 'HTTP alt',
  8443: 'HTTPS alt',
  8554: 'RTSP alt',
  8888: 'HTTP alt',
  8899: 'ONVIF',
  9000: 'HTTP alt',
  9100: 'Printer (JetDirect)',
  27017: 'MongoDB',
  32400: 'Plex',
  34567: 'DVR (XMEye)',
  37777: 'DVR (Dahua)',
  49152: 'UPnP',
  62078: 'iOS lockdown',
};

String serviceName(int port) => kServiceNames[port] ?? 'unknown';

/// Ports most commonly found open on home/SOHO devices.
const List<int> kCommonPorts = [
  21, 22, 23, 25, 53, 80, 81, 110, 135, 139, 143, 443, 445, 515, 548, 554,
  631, 993, 1883, 1900, 3306, 3389, 5000, 5060, 5353, 5900, 7547, 8000, 8008,
  8009, 8080, 8081, 8443, 8554, 8888, 8899, 9000, 9100, 32400, 34567, 37777,
  49152, 62078,
];

enum PortPreset {
  common('Common (43)'),
  wellKnown('Well-known 1–1024'),
  custom('Custom');

  const PortPreset(this.label);
  final String label;
}

List<int> portsForPreset(PortPreset preset) => switch (preset) {
      PortPreset.common => kCommonPorts,
      PortPreset.wellKnown => [for (var p = 1; p <= 1024; p++) p],
      PortPreset.custom => const [],
    };
