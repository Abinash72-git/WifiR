import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:wifi_iot/wifi_iot.dart';

import 'package:wifir/historypage.dart';
import 'package:wifir/model/wifihistory.dart';
import 'package:wifir/util/appconstants.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  static const platform = MethodChannel("wifi.connect.channel");

  final List<WiFiAccessPoint> wifiList = [];
  final List<WifiHistory> wifiHistory = [];

  bool isScanning = false;
  bool isConnecting = false;
  bool _permissionsChecked = false;
  bool _dialogOpen = false;

  String? connectedSSID;
  String? connectingSSID;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _markUserRegistered();
  }

  Future<void> _markUserRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.register, true);

    final value = prefs.getBool(AppConstants.register);
    log("is_registered = $value");
  }

  Future<void> _initializeApp() async {
    final ready = await _checkAndRequestPermissions();
    if (!ready) return;

    final wifiOk = await _ensureWifiEnabled();
    if (!wifiOk) return;

    await _checkCurrentConnection();
    await _scanWifi();
  }

  List<WiFiAccessPoint> _prioritizeConnected(List<WiFiAccessPoint> items) {
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

  Future<bool> _checkAndRequestPermissions() async {
    if (_permissionsChecked) return true;

    // 1) Location services
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (!servicesOn) {
      await _showLocationServicesDialog();
      if (!await Geolocator.isLocationServiceEnabled()) return false;
    }

    // 2) Runtime permissions
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.location,
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices,
      ].request();

      final granted =
          (statuses[Permission.nearbyWifiDevices]?.isGranted ?? false) ||
          (statuses[Permission.location]?.isGranted ?? false) ||
          (statuses[Permission.locationWhenInUse]?.isGranted ?? false);

      if (!granted) {
        Fluttertoast.showToast(
          msg: "Location or Nearby Wi-Fi permission is required.",
        );
        return false;
      }
    }

    if (!mounted) return true;
    setState(() => _permissionsChecked = true);
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
      setState(() => connectedSSID = ssid);
    } catch (_) {
      if (!mounted) return;
      setState(() => connectedSSID = null);
    }
  }

  Future<void> _scanWifi() async {
    if (isScanning) return;
    if (!await _checkAndRequestPermissions()) return;

    final wifiOk = await _ensureWifiEnabled();
    if (!wifiOk) return;

    if (!mounted) return;
    setState(() => isScanning = true);

    final started = DateTime.now();

    // do the real scan
    Future<void> doScan() async {
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        final results = await WiFiScan.instance.getScannedResults();
        if (!mounted) return;
        final ordered = _prioritizeConnected(
          List<WiFiAccessPoint>.from(results),
        );
        setState(() {
          wifiList
            ..clear()
            ..addAll(ordered);
        });
      } else {
        Fluttertoast.showToast(
          msg: "Cannot start Wi-Fi scan. Check permissions.",
        );
      }
    }

    await doScan();

    // enforce at least 3 seconds of loading
    final elapsed = DateTime.now().difference(started);
    final remain = Duration(seconds: 3) - elapsed;
    if (remain.inMilliseconds > 0) {
      await Future.delayed(remain);
    }

    if (!mounted) return;
    setState(() => isScanning = false);
  }

  void _saveWifiHistory(String ssid, String status) {
    if (!mounted) return;
    setState(() {
      wifiHistory.add(
        WifiHistory(ssid: ssid, status: status, timestamp: DateTime.now()),
      );
    });
  }

  Future<void> connectToWifi(String ssid, String password) async {
    if (!mounted) return;
    setState(() {
      isConnecting = true;
      connectingSSID = ssid;
    });

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
        _saveWifiHistory(ssid, "Connected");
        Fluttertoast.showToast(msg: "Connected to $ssid");

        // Automatically move the connected network to top
        _moveConnectedToTop();
      } else {
        setState(() {
          isConnecting = false;
          connectingSSID = null;
        });
        _saveWifiHistory(ssid, "Connection Failed");
        Fluttertoast.showToast(msg: "Failed to connect to $ssid");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isConnecting = false;
        connectingSSID = null;
      });
      _saveWifiHistory(ssid, "Connection Error");
      Fluttertoast.showToast(msg: "Error: $e");
    }
  }

  Future<void> _disconnectWifi() async {
    try {
      final bool result = await platform.invokeMethod("disconnectWifi");
      if (result) {
        final previousSSID = connectedSSID ?? "Unknown Wi-Fi";
        _saveWifiHistory(previousSSID, "Disconnected");
        if (!mounted) return;
        setState(() => connectedSSID = null);
        Fluttertoast.showToast(msg: "Disconnected from $previousSSID");

        // Re-sort the list after disconnection (removes priority of previously connected network)
        _moveConnectedToTop();
      }
    } on PlatformException catch (e) {
      Fluttertoast.showToast(msg: "Failed to disconnect: ${e.message}");
    }
  }

  void _showWifiDetails(WiFiAccessPoint wifi) {
    final isAlreadyConnected = connectedSSID == wifi.ssid;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
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
