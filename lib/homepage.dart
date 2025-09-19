import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as Math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wifi_scan/wifi_scan.dart';
import 'package:wifi_iot/wifi_iot.dart';

import 'package:wifir/historypage.dart';
import 'package:wifir/model/wifihistory.dart';
import 'package:wifir/util/appconstants.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:workmanager/workmanager.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> with WidgetsBindingObserver {
  static const platform = MethodChannel("wifi.connect.channel");

  final List<WiFiAccessPoint> wifiList = [];
  final List<WifiHistory> wifiHistory = [];
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool isScanning = false;
  bool isConnecting = false;
  bool _permissionsChecked = false;
  bool _dialogOpen = false;

  String? _lastNotifiedSSID;
  DateTime? _lastNotificationTime;

  Timer? _connectionMonitor;

  String? connectedSSID;
  String? connectingSSID;

  String? _lastConnectedSSID;
  bool _wasConnected = false;
  DateTime? _disconnectionTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeNotifications();
    _initializeApp();
    _markUserRegistered();
    loadWifiHistory();
    _loadWifiHistoryFromPrefs();

    // Initialize connection state before registering break receiver
    _initConnectionState().then((_) {
      _registerBreakReceiver();
    });

    platform.setMethodCallHandler(_handleNativeMethodCalls);
    _startConnectionMonitor();
  }

  Future<void> _initConnectionState() async {
    try {
      final ssid = await WiFiForIoTPlugin.getSSID();
      _wasConnected =
          ssid != null &&
          ssid.isNotEmpty &&
          ssid != "<unknown ssid>" &&
          ssid != "0x";
      _lastConnectedSSID = ssid;
      print(
        "📡 Initial connection state: ${_wasConnected ? 'Connected to $_lastConnectedSSID' : 'Disconnected'}",
      );
    } catch (e) {
      print("❌ Error initializing connection state: $e");
      _wasConnected = false;
      _lastConnectedSSID = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Check current connection
      _checkCurrentConnection();

      // // Always reload history when app is resumed
      loadWifiHistory();
      _loadWifiHistoryFromPrefs();

      // // Check if WiFi state changed while app was in background
      _checkForExternalWifiChanges();
    }
  }

  Future<void> _checkForExternalWifiChanges() async {
    try {
      final currentSSID = await WiFiForIoTPlugin.getSSID();
      final isCurrentlyConnected =
          currentSSID != null &&
          currentSSID.isNotEmpty &&
          currentSSID != "<unknown ssid>" &&
          currentSSID != "0x";

      // Get the last known state
      final prefs = await SharedPreferences.getInstance();
      final lastKnownSSID = prefs.getString('last_known_ssid') ?? '';
      final wasConnected = prefs.getBool('was_connected') ?? false;

      print(
        "📱 App resumed: Current WiFi: $currentSSID, Last known: $lastKnownSSID",
      );

      // Check if state changed
      if (isCurrentlyConnected &&
          (lastKnownSSID != currentSSID || !wasConnected)) {
        // Connected to a new network while app was in background
        print("📡 Detected external connection to: $currentSSID");
        _saveWifiHistory(currentSSID, "Connected");
      } else if (!isCurrentlyConnected &&
          wasConnected &&
          lastKnownSSID.isNotEmpty) {
        // Disconnected while app was in background
        print("📡 Detected external disconnection from: $lastKnownSSID");
        _saveWifiHistory(lastKnownSSID, "Disconnected");
      }

      // Update the last known state
      await prefs.setString(
        'last_known_ssid',
        isCurrentlyConnected ? currentSSID : '',
      );
      await prefs.setBool('was_connected', isCurrentlyConnected);
    } catch (e) {
      print("❌ Error checking for external WiFi changes: $e");
    }
  }

  void _registerBreakReceiver() {
    const reconnectBroadcast = "com.tabsquare.wifir.RECONNECT_DURATION";
    final reconnectStream = EventChannel(reconnectBroadcast);

    reconnectStream.receiveBroadcastStream().listen(
      (event) async {
        final currentSSID = await WiFiForIoTPlugin.getSSID();
        final isConnected =
            currentSSID != null &&
            currentSSID.isNotEmpty &&
            currentSSID != "<unknown ssid>" &&
            currentSSID != "0x";

        if (_wasConnected && !isConnected) {
          _disconnectionTime = DateTime.now();
          print("📡 Disconnected at: $_disconnectionTime");
        } else if (!_wasConnected &&
            isConnected &&
            _disconnectionTime != null) {
          final now = DateTime.now();
          final breakDuration = now.difference(_disconnectionTime!);
          final minutes = breakDuration.inMinutes;

          String label;
          if (minutes < 1) {
            label = "Short Break ($minutes min)";
          } else if (minutes < 30) {
            label = "Tea Break ($minutes min)";
          } else {
            label = "Lunch Break ($minutes min)";
          }

          print("📡 $label - Reconnected to: $currentSSID");

          // ✅ NEW: show notification instead of only snackbar
          await _showBreakNotification(currentSSID!, label);

          _disconnectionTime = null;
        }

        _wasConnected = isConnected;
        _lastConnectedSSID = currentSSID;
      },
      onError: (error) {
        print("❌ Error in break receiver: $error");
      },
    );
  }

  Future<void> _showBreakNotification(String ssid, String label) async {
    const androidDetails = AndroidNotificationDetails(
      'wifi_channel',
      'Wi-Fi Notifications',
      channelDescription: 'Notifies when Wi-Fi breaks are detected',
      importance: Importance.max,
      priority: Priority.high,
    );

    const notifDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Wi-Fi Break Detected',
      '$label on $ssid',
      notifDetails,
    );
  }

  void _startConnectionMonitor() {
    _connectionMonitor = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final ssid = await WiFiForIoTPlugin.getSSID();
        final isCurrentlyConnected =
            ssid != null &&
            ssid.isNotEmpty &&
            ssid != "<unknown ssid>" &&
            ssid != "0x";

        // Get the last known state
        final prefs = await SharedPreferences.getInstance();
        final lastKnownSSID = prefs.getString('last_known_ssid') ?? '';
        final wasConnected = prefs.getBool('was_connected') ?? false;

        if (isCurrentlyConnected) {
          // Currently connected to WiFi
          if (connectedSSID != ssid) {
            // New connection detected
            print("✅ Connection monitor detected new connection to: $ssid");

            // Update UI
            if (mounted) {
              setState(() => connectedSSID = ssid);
            }

            // Save to history if this is an external change
            if (lastKnownSSID != ssid || !wasConnected) {
              _saveWifiHistory(ssid, "Connected");
            }

            await _scheduleReminderNotification(ssid);
          }
        } else {
          // Not connected to WiFi
          if (connectedSSID != null) {
            // Was connected before but not now - disconnection detected
            final previousSSID = connectedSSID!;
            print(
              "⚠️ Connection monitor detected disconnection from: $previousSSID",
            );

            // Update UI
            if (mounted) {
              setState(() => connectedSSID = null);
            }

            // Save to history if this is an external change
            if (wasConnected && lastKnownSSID.isNotEmpty) {
              _saveWifiHistory(previousSSID, "Disconnected");
            }

            await _notifications.cancel(1);
          }
        }

        // Always update the last known state
        await prefs.setString(
          'last_known_ssid',
          isCurrentlyConnected ? ssid : '',
        );
        await prefs.setBool('was_connected', isCurrentlyConnected);
      } catch (e) {
        print("❌ Monitor error: $e");
      }
    });
  }

  Future<dynamic> _handleNativeMethodCalls(MethodCall call) async {
    if (call.method == "wifiConnected") {
      final ssid = call.arguments is Map
          ? call.arguments['ssid']
          : call.arguments as String;

      if (ssid.isNotEmpty && ssid != "<unknown ssid>") {
        print("📡 Wi-Fi connected: $ssid");

        // Use simple "Connected" status
        _saveWifiHistory(ssid, "Connected");

        if (mounted) setState(() => connectedSSID = ssid);
        await _showWifiNotification(ssid);
        await _scheduleReminderNotification(ssid);
      }
    } else if (call.method == "wifiDisconnected") {
      String ssid;

      if (call.arguments is Map) {
        final args = call.arguments as Map<dynamic, dynamic>;
        ssid = args["ssid"] as String;
      } else {
        ssid = call.arguments as String;
      }

      if (ssid.isNotEmpty && ssid != "<unknown ssid>") {
        print("📡 Wi-Fi disconnected: $ssid");

        // Use simple "Disconnected" status
        _saveWifiHistory(ssid, "Disconnected");

        if (mounted) {
          setState(() => connectedSSID = null);

          // Navigate to history page
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryPage(wifiHistoryList: wifiHistory),
              ),
            );
          });
        }

        await _notifications.cancel(1);
      }
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/wifir_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          debugPrint("Notification tapped: ${response.payload}");
        }
      },
    );

    // Create channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'wifi_channel',
      'Wi-Fi Notifications',
      description: 'Notifies when Wi-Fi is connected',
      importance: Importance.max,
    );

    final androidImpl = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.createNotificationChannel(channel);
  }

  Future<void> _showWifiNotification(String ssid) async {
    // Prevent spam: same SSID within 10 seconds = skip
    if (_lastNotifiedSSID == ssid &&
        _lastNotificationTime != null &&
        DateTime.now().difference(_lastNotificationTime!).inSeconds < 10) {
      print("⏭ Skipping duplicate notification for $ssid");
      return;
    }

    _lastNotifiedSSID = ssid;
    _lastNotificationTime = DateTime.now();

    const androidDetails = AndroidNotificationDetails(
      'wifi_channel',
      'Wi-Fi Notifications',
      channelDescription: 'Notifies when Wi-Fi is connected',
      importance: Importance.max,
      priority: Priority.high,
    );

    const notifDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Wi-Fi Connected',
      'Login to: $ssid',
      notifDetails,
    );
  }

  Future<void> _scheduleReminderNotification(String ssid) async {
    const androidDetails = AndroidNotificationDetails(
      'wifi_channel',
      'Wi-Fi Notifications',
      channelDescription: 'Notifies when Wi-Fi is connected',
      importance: Importance.max,
      priority: Priority.high,
    );

    const notifDetails = NotificationDetails(android: androidDetails);

    await _notifications.zonedSchedule(
      1, // notification id
      'Wi-Fi Reminder',
      'Still connected to: $ssid',
      tz.TZDateTime.now(tz.local).add(const Duration(minutes: 15)),
      notifDetails,
      androidScheduleMode: AndroidScheduleMode.inexact,
      payload: ssid,
    );
  }

  Future<void> _markUserRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.register, true);

    final value = prefs.getBool(AppConstants.register);
    log("is_registered = $value");
    print("✅ User registration status saved: $value");
  }

  Future<void> _initializeApp() async {
    print("🚀 Initializing App...");
    final ready = await _checkAndRequestPermissions();
    print("📌 Permissions status: $ready");
    if (!ready) return;

    final wifiOk = await _ensureWifiEnabled();
    if (!wifiOk) return;

    await _checkCurrentConnection();
    await _scanWifi();
    print("✅ App initialization completed!");
  }

  List<WiFiAccessPoint> _prioritizeConnected(List<WiFiAccessPoint> items) {
    print("📶 Sorting Wi-Fi list, total: ${items.length}");
    // Sort by signal strength first
    items.sort((a, b) => b.level.compareTo(a.level));

    final ssid = connectedSSID;
    if (ssid == null || ssid.isEmpty) return items;

    final connected = <WiFiAccessPoint>[];
    final others = <WiFiAccessPoint>[];

    for (final ap in items) {
      if (ap.ssid == ssid) {
        connected.add(ap);
      } else {
        others.add(ap);
      }
    }
    print("🔄 Connected SSID moved to top: $ssid");
    return [...connected, ...others];
  }

  void _moveConnectedToTop() {
    if (!mounted || connectedSSID == null || connectedSSID!.isEmpty) return;

    setState(() {
      final ordered = _prioritizeConnected(
        List<WiFiAccessPoint>.from(wifiList),
      );
      wifiList
        ..clear()
        ..addAll(ordered);
    });
  }

  Future<bool> _ensureWifiEnabled() async {
    try {
      final isEnabled = await WiFiForIoTPlugin.isEnabled();
      if (isEnabled) return true;

      if (_dialogOpen) return false;
      _dialogOpen = true;

      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Wi-Fi is off"),
          content: const Text("Turn on Wi-Fi to scan and connect."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Open Wi-Fi Settings"),
            ),
          ],
        ),
      );

      _dialogOpen = false;

      if (go == true) {
        // Opens system Wi-Fi settings (your native method).
        await platform.invokeMethod("openWifiSettings");
      }
      // Do not auto-scan here; user may still be in settings.
      return false;
    } catch (e) {
      Fluttertoast.showToast(msg: "Wi-Fi check failed: $e");
      return false;
    }
  }

  Future<void> loadWifiHistory() async {
    const platform = MethodChannel("wifi.history.channel");
    try {
      // Get history from native code
      final String historyJson = await platform.invokeMethod("getWifiHistory");
      print(
        "📜 Raw WiFi History: ${historyJson.substring(0, Math.min(100, historyJson.length))}...",
      );

      final List<dynamic> historyList = jsonDecode(
        historyJson.isNotEmpty ? historyJson : "[]",
      );
      print("📜 Loaded Wi-Fi History: ${historyList.length} records");

      if (mounted && historyList.isNotEmpty) {
        setState(() {
          wifiHistory.clear();
          wifiHistory.addAll(
            historyList.map(
              (e) => WifiHistory(
                ssid: e["ssid"],
                status: e["status"],
                timestamp: DateTime.parse(e["timestamp"]),
              ),
            ),
          );
        });
      }
    } on PlatformException catch (e) {
      log("Failed to load Wi-Fi history: ${e.message}");
      print("❌ Failed to load Wi-Fi history: ${e.message}");
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    if (_permissionsChecked) {
      print("✅ Permissions already granted");
      return true;
    }

    print("🔍 Checking permissions...");
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (!servicesOn) {
      print("⚠️ Location services OFF! Requesting user to enable...");
      await _showLocationServicesDialog();
      if (!await Geolocator.isLocationServiceEnabled()) {
        print("❌ Location services still disabled!");
        return false;
      }
    }

    if (Platform.isAndroid) {
      final statuses = await [
        Permission.location,
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices,
        Permission.locationAlways,
      ].request();

      final granted =
          (statuses[Permission.nearbyWifiDevices]?.isGranted ?? false) ||
          (statuses[Permission.location]?.isGranted ?? false) ||
          (statuses[Permission.locationWhenInUse]?.isGranted ?? false);

      print("📌 Permission granted: $granted");
      if (!granted) {
        Fluttertoast.showToast(
          msg: "Location or Nearby Wi-Fi permission is required.",
        );
        return false;
      }
    }

    if (mounted) {
      setState(() => _permissionsChecked = true);
    }
    return true;
  }

  Future<bool> _showLocationServicesDialog() async {
    if (_dialogOpen) return false;
    _dialogOpen = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Location required"),
        content: const Text("Enable device Location to scan nearby Wi-Fi."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );

    _dialogOpen = false;
    return true; // only reports closure; no scan here
  }

  Future<void> _checkCurrentConnection() async {
    try {
      final ssid = await WiFiForIoTPlugin.getSSID();
      if (!mounted) return;

      if (ssid != null &&
          ssid.isNotEmpty &&
          ssid != "<unknown ssid>" &&
          ssid != "0x") {
        setState(() => connectedSSID = ssid);
        print("📡 Currently connected to: $ssid");

        if (wifiHistory.isEmpty || wifiHistory.last.ssid != ssid) {
          // Use simple "Connected" status
          _saveWifiHistory(ssid, "Connected");
        }
      } else {
        setState(() => connectedSSID = null);
      }
    } catch (_) {
      if (mounted) {
        setState(() => connectedSSID = null);
      }
    }
  }

  Future<void> _scanWifi() async {
    if (isScanning) {
      print("⏳ Scan already in progress, skipping...");
      return;
    }

    if (!await _checkAndRequestPermissions()) return;

    final wifiOk = await _ensureWifiEnabled();
    if (!wifiOk) return;

    if (!mounted) return;
    setState(() => isScanning = true);

    final started = DateTime.now();
    print("🔍 Starting Wi-Fi Scan...");

    try {
      // do the real scan
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        final results = await WiFiScan.instance.getScannedResults();
        print("📡 Found Wi-Fi Networks: ${results.length}");
        if (mounted) {
          final ordered = _prioritizeConnected(
            List<WiFiAccessPoint>.from(results),
          );
          setState(() {
            wifiList
              ..clear()
              ..addAll(ordered);
          });
        }
      } else {
        print("❌ Cannot start Wi-Fi scan, permissions issue!");
        Fluttertoast.showToast(
          msg: "Cannot start Wi-Fi scan. Check permissions.",
        );
      }
    } catch (e) {
      print("❌ Wi-Fi scan error: $e");
      Fluttertoast.showToast(msg: "Scan failed: $e");
    }

    // enforce at least 3 seconds of loading
    final elapsed = DateTime.now().difference(started);
    final remain = const Duration(seconds: 3) - elapsed;
    if (remain.inMilliseconds > 0) {
      await Future.delayed(remain);
    }

    if (mounted) {
      setState(() => isScanning = false);
    }
    print("✅ Wi-Fi Scan Completed!");
  }

  void _saveWifiHistory(String ssid, String status) {
    if (!mounted) return;

    // Standardize status for connection/disconnection
    String standardStatus = status;
    if (status.startsWith("Connected") || status.startsWith("Login")) {
      standardStatus = "Connected";
    } else if (status.startsWith("Disconnected") ||
        status.startsWith("Logout")) {
      standardStatus = "Disconnected";
    }

    // Check for recent duplicates (within 60 seconds)
    final now = DateTime.now();
    bool isDuplicate = false;

    for (final entry in wifiHistory) {
      if (entry.ssid == ssid &&
          entry.status == standardStatus &&
          now.difference(entry.timestamp).inSeconds < 60) {
        isDuplicate = true;
        print(
          "⚠️ Skipping duplicate history entry: $ssid - $standardStatus (within 60 seconds)",
        );
        break;
      }
    }

    if (!isDuplicate) {
      print("📝 Adding history entry: $ssid - $standardStatus");
      setState(() {
        wifiHistory.add(
          WifiHistory(ssid: ssid, status: standardStatus, timestamp: now),
        );
      });
      _persistWifiHistory();
    }
  }

  Future<void> _persistWifiHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> historyJson = wifiHistory
          .map(
            (h) => {
              "ssid": h.ssid,
              "status": h.status,
              "timestamp": h.timestamp.toIso8601String(),
            },
          )
          .toList();
      await prefs.setString("wifi_history", jsonEncode(historyJson));
    } catch (e) {
      print("❌ Failed to persist Wi-Fi history: $e");
    }
  }

  Future<void> _loadWifiHistoryFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString("wifi_history");
      if (data == null) return;

      final List<dynamic> decoded = jsonDecode(data);
      if (mounted) {
        setState(() {
          wifiHistory.clear();
          wifiHistory.addAll(
            decoded.map(
              (e) => WifiHistory(
                ssid: e["ssid"],
                status: e["status"],
                timestamp: DateTime.parse(e["timestamp"]),
              ),
            ),
          );
        });
      }
    } catch (e) {
      print("❌ Failed to load Wi-Fi history from preferences: $e");
    }
  }

  Future<void> connectToWifi(String ssid, String password) async {
    if (!mounted) return;
    setState(() {
      isConnecting = true;
      connectingSSID = ssid;
    });

    print("🔗 Connecting to Wi-Fi: $ssid");

    try {
      final bool result = await platform.invokeMethod("connectToWifi", {
        "ssid": ssid,
        "password": password,
      });

      if (!mounted) return;
      if (result) {
        setState(() {
          connectedSSID = ssid;
          isConnecting = false;
          connectingSSID = null;
        });

        // Use simple "Connected" status
        _saveWifiHistory(ssid, "Connected");

        print("✅ Connected to $ssid");
        Fluttertoast.showToast(msg: "Connected to $ssid");

        await _showWifiNotification(ssid);
        await _scheduleReminderNotification(ssid);
        _moveConnectedToTop();
      } else {
        setState(() {
          isConnecting = false;
          connectingSSID = null;
        });
        _saveWifiHistory(ssid, "Connection Failed");
        print("❌ Failed to connect to $ssid");
        Fluttertoast.showToast(msg: "Failed to connect to $ssid");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isConnecting = false;
        connectingSSID = null;
      });
      _saveWifiHistory(ssid, "Connection Error");
      print("❌ Connection error: $e");
      Fluttertoast.showToast(msg: "Error: $e");
    }
  }

  Future<void> _disconnectWifi() async {
    try {
      final previousSSID = connectedSSID ?? "Unknown Wi-Fi";
      final bool result = await platform.invokeMethod("disconnectWifi");

      if (result) {
        // Always use consistent "Disconnected" status
        _saveWifiHistory(previousSSID, "Disconnected");
        if (mounted) setState(() => connectedSSID = null);

        print("🔌 Disconnected from $previousSSID");
        Fluttertoast.showToast(msg: "Disconnected from $previousSSID");

        await _notifications.cancel(1);
        _moveConnectedToTop();
      } else {
        // Android 10+ fallback
        Fluttertoast.showToast(
          msg: "Please manually disconnect from Wi-Fi in settings",
        );
        print("⚠️ Manual disconnect required for $previousSSID (Android 10+)");

        // Same consistent status here
        _saveWifiHistory(previousSSID, "Disconnected");
        if (mounted) setState(() => connectedSSID = null);
      }
    } on PlatformException catch (e) {
      print("❌ Failed to disconnect Wi-Fi: ${e.message}");
      Fluttertoast.showToast(msg: "Failed to disconnect: ${e.message}");
    }
  }

  void _showWifiDetails(WiFiAccessPoint wifi) {
    final isAlreadyConnected = connectedSSID == wifi.ssid;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // allows full height scroll
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 50,
            // adds safe space for keyboard & extra padding
          ),
          child: SingleChildScrollView(
            // scrollable content
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Icon(Icons.wifi, size: 40, color: Colors.blue),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    wifi.ssid.isNotEmpty ? wifi.ssid : "Unknown Wi-Fi",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text("BSSID: ${wifi.bssid}"),
                Text("Signal Strength: ${wifi.level} dBm"),
                Text("Frequency: ${wifi.frequency} MHz"),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (isAlreadyConnected) {
                        _disconnectWifi();
                      } else {
                        _showPasswordDialog(wifi);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAlreadyConnected
                          ? Colors.red
                          : Colors.blue,
                    ),
                    child: Text(isAlreadyConnected ? "Disconnect" : "Connect"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPasswordDialog(WiFiAccessPoint wifi) {
    final TextEditingController passwordController = TextEditingController();
    bool isPasswordVisible = false;

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSBState) {
            return AlertDialog(
              title: Text("Connect to ${wifi.ssid}"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: passwordController,
                    obscureText: !isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: "Enter Wi-Fi Password",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.blue,
                        ),
                        onPressed: () => setSBState(() {
                          isPasswordVisible = !isPasswordVisible;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    connectToWifi(wifi.ssid, passwordController.text);
                  },
                  child: const Text("Connect"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        title: const Text(
          "Wi-Fi Scanner",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryPage(wifiHistoryList: wifiHistory),
              ),
            ),
          ),
          isScanning
              ? const Padding(
                  padding: EdgeInsets.all(14.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _scanWifi,
                ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'Menu',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Scan History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistoryPage(wifiHistoryList: wifiHistory),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/bg2.jpg"),
            fit: BoxFit.cover,
          ),
        ),
        child: isScanning
            ? const Center(child: CircularProgressIndicator())
            : wifiList.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "No Wi-Fi networks found",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _scanWifi, // retry scan on tap
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app, // hand tap icon
                            size: 18,
                            color: Colors.blue,
                          ),
                          SizedBox(width: 5),
                          Text(
                            "Click here to reload",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: wifiList.length,
                itemBuilder: (_, index) {
                  final wifi = wifiList[index];
                  final isConnected = connectedSSID == wifi.ssid;

                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isConnected
                            ? Colors.green.shade100
                            : Colors.blue.shade100,
                        child: Icon(
                          Icons.wifi,
                          color: isConnected ? Colors.green : Colors.blue,
                        ),
                      ),
                      title: Text(
                        wifi.ssid.isNotEmpty ? wifi.ssid : "Unknown Wi-Fi",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: isConnected
                              ? Colors.green.shade700
                              : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        isConnected
                            ? "Connected ✅"
                            : "Signal: ${wifi.level} dBm",
                        style: TextStyle(
                          fontSize: 13,
                          color: isConnected
                              ? Colors.green.shade600
                              : Colors.grey.shade700,
                        ),
                      ),
                      trailing: isConnecting && wifi.ssid == connectingSSID
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.blue,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: Colors.grey,
                            ),
                      onTap: () => _showWifiDetails(wifi),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
