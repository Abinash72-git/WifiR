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
import org.json.JSONArray
import org.json.JSONObject

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

        // Delay service startup to avoid blocking the app initialization
        handler.postDelayed({
            if (ContextCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                val serviceIntent = Intent(this, WifiForegroundService::class.java)
                serviceIntent.putExtra("status", "Welcome")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
            } else {
                Log.e("MainActivity", "Location permission not granted. Skipping FGS start.")
            }
        }, 1000)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
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
                try {
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
                                        
                                        // Save connection to history
                                        handler.post {
                                            saveWifiEvent(ssid, "Connected")
                                        }
                                    }

                                    override fun onUnavailable() {
                                        result.success(false)
                                    }

                                    override fun onLost(network: Network) {
                                        super.onLost(network)
                                        if (!isManualDisconnectRequested) {
                                            handler.post {
                                                handleWifiDisconnection()
                                            }
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
                                    
                                    // Save disconnection to history
                                    handler.post {
                                        saveWifiEvent(currentSSID, "Disconnected")
                                    }
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
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error in method call: ${e.message}")
                    result.error("RUNTIME_ERROR", "An error occurred: ${e.message}", null)
                }
            }

            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_HISTORY_CHANNEL)
                .setMethodCallHandler { call, result ->
                    try {
                        if (call.method == "getWifiHistory") {
                            val prefs: SharedPreferences = getSharedPreferences("wifi_history", MODE_PRIVATE)
                            val history = prefs.getString("history", "[]")
                            result.success(history)
                        } else {
                            result.notImplemented()
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error in history method call: ${e.message}")
                        result.error("RUNTIME_ERROR", "An error occurred: ${e.message}", null)
                    }
                }

            // Register receiver with delay to avoid startup issues
            handler.postDelayed({
                registerWifiReceiver()
            }, 1000)
            
        } catch (e: Exception) {
            Log.e("MainActivity", "Error configuring Flutter engine: ${e.message}")
        }
    }

        private fun saveWifiEvent(ssid: String, status: String) {
            try {
                val prefs = getSharedPreferences("wifi_history", MODE_PRIVATE)
                val historyJson = prefs.getString("history", "[]")
                val historyArray = JSONArray(historyJson ?: "[]")
                val now = System.currentTimeMillis()
                
                // Check for duplicates in the last minute
                var isDuplicate = false
                val oneMinuteAgo = now - 60000 // 60 seconds
                
                for (i in 0 until historyArray.length()) {
                    val item = historyArray.getJSONObject(i)
                    val itemSSID = item.getString("ssid")
                    val itemStatus = item.getString("status")
                    val itemTimestamp = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", java.util.Locale.getDefault())
                        .parse(item.getString("timestamp"))?.time ?: 0L
                        
                    if (itemSSID == ssid && itemStatus == status && (now - itemTimestamp) < 60000) {
                        isDuplicate = true
                        break
                    }
                }
                
                if (!isDuplicate) {
                    val timestamp = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", java.util.Locale.getDefault())
                        .format(java.util.Date(now))

                    val event = JSONObject().apply {
                        put("ssid", ssid)
                        put("status", status)
                        put("timestamp", timestamp)
                    }

                    historyArray.put(event)

                    val trimmedArray = JSONArray().apply {
                        for (i in maxOf(0, historyArray.length() - 100) until historyArray.length()) {
                            put(historyArray.get(i))
                        }
                    }

                    prefs.edit().putString("history", trimmedArray.toString()).apply()
                    Log.d("MainActivity", "Saved Wi-Fi event: $ssid - $status")
                    
                    // Also notify Flutter
                    handler.post {
                        if (status == "Connected") {
                            wifiChannel?.invokeMethod("wifiConnected", ssid)
                        } else {
                            wifiChannel?.invokeMethod("wifiDisconnected", ssid)
                        }
                    }
                } else {
                    Log.d("MainActivity", "Skipped duplicate Wi-Fi event: $ssid - $status (within 60 seconds)")
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Error saving Wi-Fi event: ${e.message}")
            }
        }

    private fun startDisconnectMonitoring() {
        disconnectCheckRunnable?.let { handler.removeCallbacks(it) }

        var checkCount = 0
        val maxChecks = 15

        disconnectCheckRunnable = object : Runnable {
            override fun run() {
                try {
                    val currentSSID = getCurrentSSID()
                    Log.d("DisconnectMonitor", "Check $checkCount: Current SSID = '$currentSSID', Last connected = '$lastConnectedSSID'")

                    checkCount++

                    if (isConnected && currentSSID.isEmpty() && !lastConnectedSSID.isNullOrEmpty()) {
                        Log.d("DisconnectMonitor", "Disconnect detected! Triggering notification.")
                        handleWifiDisconnection()
                        isManualDisconnectRequested = false
                        return
                    } else if (!isConnected && currentSSID.isNotEmpty()) {
                        // External connection detected
                        Log.d("DisconnectMonitor", "External connection detected: $currentSSID")
                        lastConnectedSSID = currentSSID
                        isConnected = true
                        
                        // Save connection to history
                        saveWifiEvent(currentSSID, "Connected")
                    }

                    if (checkCount >= maxChecks || (currentSSID.isNotEmpty() && currentSSID != lastConnectedSSID)) {
                        Log.d("DisconnectMonitor", "Stopping disconnect monitoring")
                        isManualDisconnectRequested = false
                        return
                    }

                    handler.postDelayed(this, 2000)
                } catch (e: Exception) {
                    Log.e("DisconnectMonitor", "Error in monitor: ${e.message}")
                }
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
            } else {
                startService(serviceIntent)
            }
            
            // Save to history
            saveWifiEvent(lastConnectedSSID!!, "Disconnected")

            isConnected = false
            lastConnectedSSID = null
        }
    }

    private fun registerWifiReceiver() {
        try {
            val filter = IntentFilter()
            filter.addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION)
            filter.addAction(ConnectivityManager.CONNECTIVITY_ACTION)

            wifiReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    try {
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
                                                    // Update state
                                                    lastConnectedSSID = currentSSID
                                                    isConnected = true
                                                    isManualDisconnectRequested = false
                                                    
                                                    // Save to history
                                                    handler.post {
                                                        saveWifiEvent(currentSSID, "Connected")
                                                    }
                                                }
                                            }
                                        }

                                        NetworkInfo.State.DISCONNECTED, NetworkInfo.State.DISCONNECTING -> {
                                            Log.d("WiFiReceiver", "Disconnected state detected")

                                            if (isConnected && !lastConnectedSSID.isNullOrEmpty() && !isManualDisconnectRequested) {
                                                Log.d("WiFiReceiver", "Handling automatic disconnect for: $lastConnectedSSID")
                                                handler.post {
                                                    handleWifiDisconnection()
                                                }
                                            }
                                        }

                                        else -> {
                                            Log.d("WiFiReceiver", "Other network state: ${networkInfo.state}")
                                        }
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("WiFiReceiver", "Error in broadcast receiver: ${e.message}")
                    }
                }
            }

            registerReceiver(wifiReceiver, filter)
            Log.d("MainActivity", "WiFi receiver registered")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error registering WiFi receiver: ${e.message}")
        }
    }

    override fun onResume() {
        super.onResume()
        try {
            // Check for WiFi state changes
            handler.postDelayed({
                checkWifiStateChanged()
            }, 500)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in onResume: ${e.message}")
        }
    }
    
    private fun checkWifiStateChanged() {
        try {
            val currentSSID = getCurrentSSID()
            val prefs = getSharedPreferences("last_wifi_state", MODE_PRIVATE)
            val lastSSID = prefs.getString("last_ssid", "")
            val wasConnected = prefs.getBoolean("was_connected", false)
            
            if (currentSSID.isNotEmpty() && (currentSSID != lastSSID || !wasConnected)) {
                // Connected to a new network while app was paused
                Log.d("MainActivity", "Detected connection change on resume: $currentSSID")
                lastConnectedSSID = currentSSID
                isConnected = true
                
                // Save to history
                saveWifiEvent(currentSSID, "Connected")
            } else if (currentSSID.isEmpty() && wasConnected && !lastSSID.isNullOrEmpty()) {
                // Disconnected while app was paused
                Log.d("MainActivity", "Detected disconnection on resume from: $lastSSID")
                
                // Save to history
                saveWifiEvent(lastSSID, "Disconnected")
            }
            
            // Update last known state
            prefs.edit()
                .putString("last_ssid", currentSSID)
                .putBoolean("was_connected", currentSSID.isNotEmpty())
                .apply()
        } catch (e: Exception) {
            Log.e("MainActivity", "Error checking WiFi state changes: ${e.message}")
        }
    }

    override fun onPause() {
        super.onPause()
        try {
            // Save current WiFi state
            val currentSSID = getCurrentSSID()
            getSharedPreferences("last_wifi_state", MODE_PRIVATE)
                .edit()
                .putString("last_ssid", currentSSID)
                .putBoolean("was_connected", currentSSID.isNotEmpty())
                .apply()
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in onPause: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            wifiReceiver?.let { 
                try {
                    unregisterReceiver(it) 
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error unregistering receiver: ${e.message}")
                }
            }

            networkCallback?.let {
                try {
                    connectivityManager?.unregisterNetworkCallback(it)
                } catch (e: Exception) {
                    Log.e("MainActivity", "Error unregistering network callback: ${e.message}")
                }
            }

            disconnectCheckRunnable?.let { handler.removeCallbacks(it) }
            disconnectCheckRunnable = null
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in onDestroy: ${e.message}")
        }
    }

    private fun isValidSSID(ssid: String?): Boolean {
        return !ssid.isNullOrEmpty() &&
                ssid != "<unknown ssid>" &&
                ssid != "0x" &&
                ssid.trim().isNotEmpty()
    }
}
