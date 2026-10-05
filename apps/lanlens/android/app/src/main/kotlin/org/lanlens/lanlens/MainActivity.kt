package org.lanlens.lanlens

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "org.lanlens/wifi"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scan" -> scanAccessPoints(result)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Requests a fresh scan and returns results when the system broadcasts
     * them. Android throttles foreground apps to 4 scans per 2 minutes; when
     * a scan is refused or slow, the most recent cached results are returned.
     */
    @Suppress("DEPRECATION")
    private fun scanAccessPoints(result: MethodChannel.Result) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) {
            result.error("WIFI_DISABLED", "Wi-Fi is turned off", null)
            return
        }
        val handler = Handler(Looper.getMainLooper())
        var replied = false

        fun reply(fresh: Boolean) {
            if (replied) return
            replied = true
            try {
                result.success(mapOf("fresh" to fresh, "results" to collect(wifi)))
            } catch (e: SecurityException) {
                result.error("PERMISSION", "Location permission is required to list networks", null)
            }
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                runCatching { applicationContext.unregisterReceiver(this) }
                reply(intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false))
            }
        }
        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= 33) {
            applicationContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            applicationContext.registerReceiver(receiver, filter)
        }

        val started = wifi.startScan()
        handler.postDelayed({
            runCatching { applicationContext.unregisterReceiver(receiver) }
            reply(false)
        }, if (started) 8000L else 0L)
    }

    @Suppress("DEPRECATION")
    private fun collect(wifi: WifiManager): List<Map<String, Any?>> {
        val connectedBssid = wifi.connectionInfo?.bssid
        return wifi.scanResults.map { r ->
            val ssid = if (Build.VERSION.SDK_INT >= 33) {
                r.wifiSsid?.toString()?.removeSurrounding("\"")
            } else {
                r.SSID
            }
            mapOf(
                "ssid" to (ssid ?: ""),
                "bssid" to r.BSSID,
                "level" to r.level,
                "frequency" to r.frequency,
                "capabilities" to r.capabilities,
                "channelWidth" to if (Build.VERSION.SDK_INT >= 23) r.channelWidth else null,
                "connected" to (r.BSSID == connectedBssid),
            )
        }
    }
}
