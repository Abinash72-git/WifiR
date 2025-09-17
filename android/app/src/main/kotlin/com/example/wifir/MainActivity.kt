package com.tabsquare.Wifir

import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import android.os.Bundle
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkRequest
import android.net.NetworkCapabilities
import android.net.NetworkInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.IntentFilter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity() {
    private val WIFI_CONNECT_CHANNEL = "wifi.connect.channel"
    private val WIFI_HISTORY_CHANNEL = "wifi.history.channel"
    private val RECONNECT_DURATION_CHANNEL = "com.tabsquare.wifir.RECONNECT_DURATION"

    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private var wifiReceiver: BroadcastReceiver? = null
    private var wifiChannel: MethodChannel? = null

    private var lastConnectedSSID: String? = null
    private var isConnected = false
    private var isManualDisconnectRequested = false

    private val handler = Handler(Looper.getMainLooper())
    private var disconnectCheckRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            val serviceIntent = Intent(this, WifiForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
        } else {
            Log.e("MainActivity", "Location permission not granted. Skipping FGS start.")
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        wifiChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CONNECT_CHANNEL)

        // EventChannel for RECONNECT_DURATION
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, RECONNECT_DURATION_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var eventSink: EventChannel.EventSink? = null
                private var handler: Handler? = null
                private var runnable: Runnable? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    handler = Handler(Looper.getMainLooper())
                    runnable = object : Runnable {
                        override fun run() {
                            eventSink?.success("Some duration data")
                            handler?.postDelayed(this, 1000)
                        }
                    }
                    handler?.post(runnable!!)
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    handler?.removeCallbacks(runnable!!)
                }
            })

        wifiChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "connectToWifi" -> {
                    val ssid = call.argument<String>("ssid") ?: ""
                    val password = call.argument<String>("password") ?: ""

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val specifier = android.net.wifi.WifiNetworkSpecifier.Builder()
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

                                lastConnectedSSID = ssid
                                isConnected = true
                                isManualDisconnectRequested = false
                            }

                            override fun onUnavailable() {
                                result.success(false)
                            }

                            override fun onLost(network: Network) {
                                super.onLost(network)
                                if (!isManualDisconnectRequested) {
                                    handleWifiDisconnection()
                                }
                            }
                        }

                        connectivityManager?.requestNetwork(request, networkCallback!!)
                    } else {
                        result.success(false)
                    }
                }

                "disconnectWifi" -> {
                    try {
                        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager

                        val currentSSID = getCurrentSSID()
                        if (currentSSID.isNotEmpty()) {
                            lastConnectedSSID = currentSSID
                        }

                        isManualDisconnectRequested = true

                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            wifiManager.disconnect()
                            startDisconnectMonitoring()
                            result.success(true)
                        } else {
                            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            connectivityManager?.bindProcessToNetwork(null)

                            startDisconnectMonitoring()
                            result.success(false)
                        }

                        networkCallback?.let {
                            connectivityManager?.unregisterNetworkCallback(it)
                        }
                        networkCallback = null
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error during Wi-Fi disconnect: ${e.message}")
                        isManualDisconnectRequested = false
                        result.success(false)
                    }
                }

                "openWifiSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val intent = Intent(Settings.Panel.ACTION_WIFI)
                            startActivity(intent)
                        } else {
                            val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_WIFI_SETTINGS_FAILED", e.message, null)
                    }
                }

                "getCurrentSSID" -> {
                    try {
                        val currentSSID = getCurrentSSID()
                        if (currentSSID.isNotEmpty()) {
                            result.success(currentSSID)
                        } else {
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.success(null)
                    }
                }

                "getAndroidVersion" -> {
                    result.success(Build.VERSION.SDK_INT)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_HISTORY_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getWifiHistory") {
                    val prefs: SharedPreferences = getSharedPreferences("wifi_history", MODE_PRIVATE)
                    val history = prefs.getString("history", "[]")
                    result.success(history)
                } else {
                    result.notImplemented()
                }
            }

        registerWifiReceiver()
    }

    private fun startDisconnectMonitoring() {
        disconnectCheckRunnable?.let { handler.removeCallbacks(it) }

        var checkCount = 0
        val maxChecks = 15

        disconnectCheckRunnable = object : Runnable {
            override fun run() {
                val currentSSID = getCurrentSSID()
                Log.d("DisconnectMonitor", "Check $checkCount: Current SSID = '$currentSSID', Last connected = '$lastConnectedSSID'")

                checkCount++

                if (isConnected && currentSSID.isEmpty() && !lastConnectedSSID.isNullOrEmpty()) {
                    Log.d("DisconnectMonitor", "Disconnect detected! Triggering notification.")
                    handleWifiDisconnection()
                    isManualDisconnectRequested = false
                    return
                }

                if (checkCount >= maxChecks || (currentSSID.isNotEmpty() && currentSSID != lastConnectedSSID)) {
                    Log.d("DisconnectMonitor", "Stopping disconnect monitoring")
                    isManualDisconnectRequested = false
                    return
                }

                handler.postDelayed(this, 2000)
            }
        }

        handler.postDelayed(disconnectCheckRunnable!!, 1000)
    }

    private fun getCurrentSSID(): String {
        return try {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val ssid = wifiManager.connectionInfo?.ssid?.replace("\"", "") ?: ""
            if (isValidSSID(ssid)) ssid else ""
        } catch (e: Exception) {
            ""
        }
    }

    private fun handleWifiDisconnection() {
        if (isConnected && !lastConnectedSSID.isNullOrEmpty()) {
            Log.d("WiFiDisconnect", "Handling disconnection for: $lastConnectedSSID")

            val serviceIntent = Intent(this, WifiForegroundService::class.java)
            serviceIntent.putExtra("ssid", lastConnectedSSID)
            serviceIntent.putExtra("status", "Disconnected")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            }

            isConnected = false
            lastConnectedSSID = null
        }
    }

    private fun registerWifiReceiver() {
        val filter = IntentFilter()
        filter.addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION)
        filter.addAction(ConnectivityManager.CONNECTIVITY_ACTION)

        wifiReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    WifiManager.NETWORK_STATE_CHANGED_ACTION -> {
                        val networkInfo = intent.getParcelableExtra<NetworkInfo>(WifiManager.EXTRA_NETWORK_INFO)
                        Log.d("WiFiReceiver", "Network state changed: ${networkInfo?.state}")

                        if (networkInfo != null && networkInfo.type == ConnectivityManager.TYPE_WIFI) {
                            when (networkInfo.state) {
                                NetworkInfo.State.CONNECTED -> {
                                    val currentSSID = getCurrentSSID()
                                    Log.d("WiFiReceiver", "Connected to: $currentSSID")

                                    if (currentSSID.isNotEmpty()) {
                                        if (currentSSID != lastConnectedSSID || !isConnected) {
                                            // Only update state, no history/notification here
                                            lastConnectedSSID = currentSSID
                                            isConnected = true
                                            isManualDisconnectRequested = false
                                        }
                                    }
                                }

                                NetworkInfo.State.DISCONNECTED, NetworkInfo.State.DISCONNECTING -> {
                                    Log.d("WiFiReceiver", "Disconnected state detected")

                                    if (isConnected && !lastConnectedSSID.isNullOrEmpty() && !isManualDisconnectRequested) {
                                        Log.d("WiFiReceiver", "Handling automatic disconnect for: $lastConnectedSSID")
                                        handleWifiDisconnection()
                                    }
                                }

                                else -> {
                                    Log.d("WiFiReceiver", "Other network state: ${networkInfo.state}")
                                }
                            }
                        }
                    }
                }
            }
        }

        registerReceiver(wifiReceiver, filter)
    }

    override fun onResume() {
        super.onResume()
        if (isManualDisconnectRequested) {
            val currentSSID = getCurrentSSID()
            if (currentSSID.isEmpty() && isConnected) {
                handleWifiDisconnection()
            }
            isManualDisconnectRequested = false
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        wifiReceiver?.let { unregisterReceiver(it) }

        networkCallback?.let {
            connectivityManager?.unregisterNetworkCallback(it)
        }

        disconnectCheckRunnable?.let { handler.removeCallbacks(it) }
        disconnectCheckRunnable = null
    }

    private fun isValidSSID(ssid: String?): Boolean {
        return !ssid.isNullOrEmpty() &&
                ssid != "<unknown ssid>" &&
                ssid != "0x" &&
                ssid.trim().isNotEmpty()
    }
}
