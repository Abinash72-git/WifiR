package com.tabsquare.Wifir

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkInfo
import android.net.wifi.WifiManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

class WifiReceiver : BroadcastReceiver() {

    companion object {
        private const val PREFS_NAME = "wifi_history"
        private const val LAST_CONNECTED_SSID = "last_connected_ssid"
        private const val LAST_DISCONNECT_TIME = "last_disconnect_time"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        Log.d("WifiReceiver", "Intent received: ${intent.action}")

        when (intent.action) {
            WifiManager.NETWORK_STATE_CHANGED_ACTION -> {
                handleWifiStateChange(context, intent)
            }
            ConnectivityManager.CONNECTIVITY_ACTION -> {
                handleConnectivityChange(context)
            }
        }
    }

    private fun handleWifiStateChange(context: Context, intent: Intent) {
        val networkInfo = intent.getParcelableExtra<NetworkInfo>(WifiManager.EXTRA_NETWORK_INFO)
        if (networkInfo == null) return

        when (networkInfo.state) {
            NetworkInfo.State.CONNECTED -> {
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    handleWifiConnected(context)
                }, 1000)
            }
            NetworkInfo.State.DISCONNECTED -> {
                handleWifiDisconnected(context)
            }
            else -> {}
        }
    }

    private fun handleConnectivityChange(context: Context) {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val networkInfo = connectivityManager.activeNetworkInfo

        if (networkInfo != null && networkInfo.type == ConnectivityManager.TYPE_WIFI && networkInfo.isConnected) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                handleWifiConnected(context)
            }, 1500)
        }
    }

    private fun handleWifiConnected(context: Context) {
    try {
        val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val connectionInfo = wifiManager.connectionInfo ?: return
        val ssid = connectionInfo.ssid?.replace("\"", "") ?: return

        if (isValidSSID(ssid)) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val lastConnectedSSID = prefs.getString(LAST_CONNECTED_SSID, "")
            var statusToSave = "Connected (Auto)"  // default label

            // Calculate break duration on reconnect
            val disconnectTime = prefs.getLong(LAST_DISCONNECT_TIME, -1L)
            if (disconnectTime > 0 && ssid == lastConnectedSSID) {
                val now = System.currentTimeMillis()
                val durationMin = TimeUnit.MILLISECONDS.toMinutes(now - disconnectTime)
                prefs.edit().remove(LAST_DISCONNECT_TIME).apply()

                val breakLabel = when {
                    durationMin < 1 -> "Short Break ($durationMin min)"
                    durationMin < 30 -> "Tea Break ($durationMin min)"
                    else -> "Lunch Break ($durationMin min)"
                }

                Log.d("WifiReceiver", "Reconnected after break: $breakLabel")
                statusToSave = breakLabel

                // ✅ NEW: Show native break notification
                showBreakNotification(context, ssid, breakLabel)

                // Notify Flutter app about the break
                notifyFlutterAppBreak(context, durationMin.toInt(), breakLabel)
            }

            if (ssid != lastConnectedSSID || disconnectTime > 0) {
                Log.d("WifiReceiver", "Wi-Fi connection detected: $ssid")
                prefs.edit().putString(LAST_CONNECTED_SSID, ssid).apply()

                val now = System.currentTimeMillis()
                saveWifiEvent(context, ssid, statusToSave, now)

                showWifiNotification(context, ssid, "Connected")
                notifyFlutterApp(context, ssid)
            }
        }
    } catch (e: Exception) {
        Log.e("WifiReceiver", "Error handling Wi-Fi connection: ${e.message}")
    }
}

private fun handleWifiDisconnected(context: Context) {
    try {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val lastConnectedSSID = prefs.getString(LAST_CONNECTED_SSID, "")

        if (!lastConnectedSSID.isNullOrEmpty()) {
            val now = System.currentTimeMillis()

            // Save the disconnect event into history ✅
            saveWifiEvent(context, lastConnectedSSID, "Disconnected (Auto)", now)

            // Show notification
            showWifiNotification(context, lastConnectedSSID, "Disconnected")

            // Clear last connected SSID
            prefs.edit().putString(LAST_CONNECTED_SSID, "").apply()

            // Notify Flutter app about disconnection
            notifyFlutterAppDisconnect(context, lastConnectedSSID)

            android.util.Log.d("WifiReceiver", "📴 Wi-Fi auto-disconnected from: $lastConnectedSSID at $now")
        }
    } catch (e: Exception) {
        android.util.Log.e("WifiReceiver", "⚠️ Error handling auto Wi-Fi disconnection: ${e.message}")
    }
}



    private fun isValidSSID(ssid: String?): Boolean {
        return !ssid.isNullOrEmpty() && ssid != "<unknown ssid>" && ssid != "0x" && ssid.trim().isNotEmpty()
    }

    private fun showWifiNotification(context: Context, ssid: String, status: String) {
        try {
            val serviceIntent = Intent(context, WifiForegroundService::class.java)
            serviceIntent.putExtra("ssid", ssid)
            serviceIntent.putExtra("status", status)

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (e: Exception) {
            Log.e("WifiReceiver", "Error showing notification: ${e.message}")
        }
    }

    private fun showBreakNotification(context: Context, ssid: String, breakLabel: String) {
    try {
        val channelId = "wifi_break_channel"
        val channelName = "Break Notifications"

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                channelName,
                android.app.NotificationManager.IMPORTANCE_HIGH
            )
            notificationManager.createNotificationChannel(channel)
        }

        val notification = androidx.core.app.NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.wifir_launcher) // you can change this
            .setContentTitle("Wi-Fi Breaks Chat")
            .setContentText("$breakLabel on $ssid")
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(System.currentTimeMillis().toInt(), notification)
    } catch (e: Exception) {
        Log.e("WifiReceiver", "Error showing break notification: ${e.message}")
    }
}


    private fun notifyFlutterApp(context: Context, ssid: String) {
        try {
            val intent = Intent("com.tabsquare.wifir.WIFI_CONNECTED")
            intent.putExtra("ssid", ssid)
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e("WifiReceiver", "Error notifying Flutter app: ${e.message}")
        }
    }

    private fun notifyFlutterAppDisconnect(context: Context, ssid: String) {
        try {
            val intent = Intent("com.tabsquare.wifir.WIFI_DISCONNECTED")
            intent.putExtra("ssid", ssid)
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e("WifiReceiver", "Error notifying Flutter app about disconnect: ${e.message}")
        }
    }

    private fun notifyFlutterAppBreak(context: Context, minutes: Int, label: String) {
        try {
            val intent = Intent("com.tabsquare.wifir.BREAK_DETECTED")
            intent.putExtra("minutes", minutes)
            intent.putExtra("label", label)
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e("WifiReceiver", "Error notifying Flutter app about break: ${e.message}")
        }
    }

    private fun saveWifiEvent(context: Context, ssid: String, status: String, eventTime: Long) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val historyJson = prefs.getString("history", "[]")
            val historyArray = JSONArray(historyJson ?: "[]")

            val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.getDefault())
    .format(Date(eventTime))

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
            Log.d("WifiReceiver", "Saved Wi-Fi event: $ssid - $status")
        } catch (e: Exception) {
            Log.e("WifiReceiver", "Error saving Wi-Fi event: ${e.message}")
        }
    }
}