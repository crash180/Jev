import 'package:flutter_test/flutter_test.dart';
import 'package:lanlens/features/wifi_scanner/wifi_scan.dart';

void main() {
  test('frequency to channel and band', () {
    expect(channelForFrequency(2412), 1);
    expect(channelForFrequency(2437), 6);
    expect(channelForFrequency(2484), 14);
    expect(channelForFrequency(5180), 36);
    expect(channelForFrequency(5745), 149);
    expect(channelForFrequency(5955), 1);
    expect(bandForFrequency(2462), WifiBand.ghz24);
    expect(bandForFrequency(5500), WifiBand.ghz5);
    expect(bandForFrequency(6115), WifiBand.ghz6);
  });

  test('security parsing', () {
    expect(securityFromCapabilities('[ESS]'), WifiSecurity.open);
    expect(securityFromCapabilities('[WEP][ESS]'), WifiSecurity.wep);
    expect(securityFromCapabilities('[WPA-PSK-TKIP][ESS]'), WifiSecurity.wpa);
    expect(securityFromCapabilities('[WPA2-PSK-CCMP][RSN-PSK-CCMP][ESS]'), WifiSecurity.wpa2);
    expect(securityFromCapabilities('[RSN-PSK+SAE-CCMP][ESS]'), WifiSecurity.wpa3);
    expect(securityFromCapabilities('[WPA2-EAP-CCMP][ESS]'), WifiSecurity.enterprise);
  });

  test('signal quality and map parsing', () {
    expect(signalQuality(-50), 100);
    expect(signalQuality(-75), 50);
    expect(signalQuality(-110), 0);
    final ap = WifiAp.fromMap({
      'ssid': '',
      'bssid': 'aa:bb:cc:dd:ee:ff',
      'level': -60,
      'frequency': 5180,
      'capabilities': '[WPA2-PSK-CCMP][WPS][ESS]',
      'channelWidth': 2,
      'connected': true,
    });
    expect(ap.hidden, isTrue);
    expect(ap.channel, 36);
    expect(ap.channelWidthMhz, 80);
    expect(ap.wps, isTrue);
    expect(ap.quality, 80);
  });
}
