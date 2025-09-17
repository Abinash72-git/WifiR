import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
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
      final ssid = await WiFiForIoTPlugin.getSSID();

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
        'Wi-Fi Status',
        ssid != null && ssid.isNotEmpty
            ? "Currently connected to: $ssid"
            : "Not connected",
        notifDetails,
      );
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
        data: 'package:com.tabsquare.Wifir', // replace with your package if needed
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
