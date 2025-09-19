import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifir/splashscreen.dart';
import 'package:workmanager/workmanager.dart';
import 'package:wifi_iot/wifi_iot.dart';

import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == "wifiCheckTask") {
      try {
        // Get current WiFi status
        final ssid = await WiFiForIoTPlugin.getSSID();
        final isConnected = ssid != null && 
                          ssid.isNotEmpty && 
                          ssid != "<unknown ssid>" &&
                          ssid != "0x";
        
        // Get shared preferences to track changes
        final prefs = await SharedPreferences.getInstance();
        final lastSSID = prefs.getString("last_known_ssid") ?? "";
        final lastConnected = prefs.getBool("last_connected_status") ?? false;
        
        // Check if WiFi status has changed
        bool hasChanged = false;
        String status = "";
        
        if (isConnected && lastSSID != ssid) {
          // New connection
          hasChanged = true;
          status = "Connected";
        } else if (!isConnected && lastConnected && lastSSID.isNotEmpty) {
          // Disconnection
          hasChanged = true;
          status = "Disconnected";
        }
        
        if (hasChanged) {
          // Save new status
          await prefs.setString("last_known_ssid", isConnected ? ssid! : "");
          await prefs.setBool("last_connected_status", isConnected);
          
          // Save to history
          final historyJson = prefs.getString("wifi_history") ?? "[]";
          final historyList = jsonDecode(historyJson);
          
          // Add new entry with current timestamp
          final now = DateTime.now().toIso8601String();
          final newEntry = {
            "ssid": isConnected ? ssid : lastSSID,
            "status": status,
            "timestamp": now
          };
          
          historyList.add(newEntry);
          
          // Save updated history
          await prefs.setString("wifi_history", jsonEncode(historyList));
          
          // Show notification
          const androidDetails = AndroidNotificationDetails(
            'wifi_channel',
            'Wi-Fi Notifications',
            channelDescription: 'Notifies when Wi-Fi is connected',
            importance: Importance.max,
            priority: Priority.high,
          );

          const notifDetails = NotificationDetails(android: androidDetails);

          await notifications.show(
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            isConnected ? 'Wi-Fi Connected' : 'Wi-Fi Disconnected',
            isConnected 
                ? "Login to: $ssid" 
                : "Logged out from: $lastSSID",
            notifDetails,
          );
        }
      } catch (e) {
        print("Error in background task: $e");
      }
    }
    return Future.value(true);
  });
}


Future<void> openUnusedAppsSettings() async {
  if (Platform.isAndroid) {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 23) {
      final intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data:
            'package:com.tabsquare.Wifir', // replace with your package if needed
      );
      await intent.launch();
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  // ✅ Ask for notification permission here
  final status = await Permission.notification.request();
  print("Notification permission: $status");

  const AndroidInitializationSettings initAndroid =
      AndroidInitializationSettings('@mipmap/wifir_launcher');

  const InitializationSettings initSettings = InitializationSettings(
    android: initAndroid,
  );
  await notifications.initialize(initSettings);

  await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);

  await Workmanager().registerPeriodicTask(
    "wifiCheckTaskId",
    "wifiCheckTask",
    frequency: const Duration(minutes: 2),
    // initialDelay: const Duration(minutes: 1),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}
