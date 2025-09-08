package com.tabsquare.Wifir

import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkRequest
import android.net.NetworkCapabilities
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wifi.connect.channel"
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connectToWifi" -> {
                    val ssid = call.argument<String>("ssid") ?: ""
                    val password = call.argument<String>("password") ?: ""

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val specifier = WifiNetworkSpecifier.Builder()
                            .setSsid(ssid)
                            .setWpa2Passphrase(password)
                            .build()

                        val request = NetworkRequest.Builder()
                            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                            .setNetworkSpecifier(specifier)
                            .build()

                        connectivityManager = getSystemService(ConnectivityManager::class.java)

                        networkCallback?.let {
                            connectivityManager?.unregisterNetworkCallback(it)
                        }

                        networkCallback = object : ConnectivityManager.NetworkCallback() {
                            override fun onAvailable(network: Network) {
                                connectivityManager?.bindProcessToNetwork(network)
                                result.success(true)
                            }

                            override fun onUnavailable() {
                                result.success(false)
                            }
                        }

                        connectivityManager?.requestNetwork(request, networkCallback!!)
                    } else {
                        result.success(false)
                    }
                }

                "disconnectWifi" -> {
                    try {
                        networkCallback?.let {
                            connectivityManager?.unregisterNetworkCallback(it)
                        }
                        connectivityManager?.bindProcessToNetwork(null)
                        networkCallback = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                // NEW: open Wi-Fi settings UI
                "openWifiSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            // Quick settings panel (Android 10+)
                            val intent = Intent(Settings.Panel.ACTION_WIFI)
                            startActivity(intent)
                        } else {
                            // Classic Wi-Fi settings (pre-Android 10)
                            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_WIFI_SETTINGS_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
