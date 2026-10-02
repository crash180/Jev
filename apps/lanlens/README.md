<p align="center"><img src="assets/images/logo.png" width="96" alt="LanLens logo"></p>

# LanLens

An open source, Android-first network toolkit for your own home or office LAN, built with Flutter.

| Tool | What it does | Android | iOS |
|------|--------------|---------|-----|
| **Port Scanner** | TCP connect scan of a host: common / 1–1024 / custom ranges, service names, banner grab | ✅ | ✅ |
| **Router Check** | Non-intrusive audit of the gateway: Telnet/FTP/TR-069/SMB/UPnP exposure, plain-HTTP admin, Basic auth, version disclosure; 0–100 score with fixes | ✅ | ✅ |
| **Speed Test** | Latency, jitter, multi-stream download and upload (Cloudflare endpoints by default, configurable) | ✅ | ✅ |
| **Wi-Fi Scanner** | Nearby access points: signal, channel, band, width, security (Open → WPA3), WPS, channel congestion | ✅ | ⚠️ connected network only (no public iOS API) |
| **Wake on LAN** | Saved devices, magic packets on UDP 9/7, SecureOn password, "did it wake?" check | ✅ | ✅ |

> **Use responsibly.** Only scan networks and devices you own or are authorized to test. LanLens asks for confirmation before probing any public address, and the router check never tries passwords or exploits.

## Run it

```bash
cd apps/lanlens
flutter pub get
flutter run            # device or emulator
flutter test           # unit tests (pure logic + loopback socket tests)
flutter build apk --release
```

Requires Flutter 3.47+ / Dart 3.13+. On iOS run `cd ios && pod install` once.

### Permissions

| Permission | Why |
|------------|-----|
| `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` | Sockets and current Wi-Fi info |
| `ACCESS_FINE_LOCATION`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES` | Android only returns Wi-Fi scan results to apps holding these. Location is never stored or uploaded. |
| iOS `NSLocationWhenInUseUsageDescription`, `NSLocalNetworkUsageDescription` | Reading the connected SSID; local network access prompt |

To have `permission_handler` request location on iOS, add `PERMISSION_LOCATION=1` to the `GCC_PREPROCESSOR_DEFINITIONS` in `ios/Podfile` (see the [permission_handler setup guide](https://pub.dev/packages/permission_handler)).

## Layout

```
lib/
  main.dart               App entry, light/dark theme
  app/                    Home grid + feature registry
  core/                   IPv4/port parsing, TCP probe, concurrency pool,
                          local network info, host discovery
  ui/                     Theme + shared widgets (authorized-use banner, pills…)
  features/
    port_scanner/         #1
    router_check/         #2
    speed_test/           #4
    wifi_scanner/         #7  (Dart side; native bridge in MainActivity.kt)
    wake_on_lan/          #8
android/app/src/main/kotlin/.../MainActivity.kt   WifiManager scan MethodChannel
assets/brand/logo.svg    Source artwork (launcher icons are rendered from it)
```

## Platform notes

- **No root needed.** All scans use ordinary TCP/UDP sockets. A host counts as alive when a probe gets either SYN-ACK or RST.
- **Android scan throttling.** Android allows 4 Wi-Fi scans per 2 minutes. When a scan is throttled, LanLens shows the most recent cached results and says so.
- **Speed test data use.** One run transfers roughly 50–500 MB, depending on your connection speed.

## License

Same as the parent repository.
