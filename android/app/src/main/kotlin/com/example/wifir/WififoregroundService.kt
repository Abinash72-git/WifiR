
package com.tabsquare.Wifir

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class WifiForegroundService : Service() {
    private val CHANNEL_ID = "wifi_channel"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

   override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val ssid = intent?.getStringExtra("ssid") ?: "Unknown"
        val status = intent?.getStringExtra("status") ?: "Idle"

        // 🔹 Choose text based on real status
        val (title, text) = when (status) {
            "Connected" -> "Wi-Fi Connected" to "Login to: $ssid"
            "Disconnected" -> "Wi-Fi Disconnected" to "Logout from: $ssid"
            else -> "DTIT" to "Welcome To DTIT"
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.wifir_launcher) // ✅ Ensure icon exists in mipmap
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true) // 🟢 Prevents swipe-away
            .build()

        // 🔹 Must call within 5s of startForegroundService()
        startForeground(1, notification)

        return START_STICKY // Keeps service alive if killed
    }
override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Wi-Fi Notifications",
                NotificationManager.IMPORTANCE_HIGH
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }
}
