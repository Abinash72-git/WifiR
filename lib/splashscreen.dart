import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifir/homepage.dart';
import 'package:wifir/loginpage.dart';
import 'package:wifir/main.dart';
import 'package:wifir/util/appconstants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate after first frame to avoid context issues
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await openUnusedAppsSettings(); // only if needed
      }
      await _navigate();
    });
  }

  Future<void> _navigate() async {
    try {
      // show splash for 3s
      await Future.delayed(const Duration(seconds: 3));

      final prefs = await SharedPreferences.getInstance();
      final isRegistered = prefs.getBool(AppConstants.register) ?? false;

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => isRegistered
              ? const Homepage()
              : const Loginpage(), // <-- match class name
        ),
      );
    } catch (e) {
      // fallback to login on any error
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const Loginpage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blueGrey, Colors.blue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi, size: 80, color: Colors.white),
            SizedBox(height: 20),
            Text(
              "Wi-Fi Scanner",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 20),
            Image(
              image: AssetImage("assets/Empl.png"),
              width: 100,
              height: 100,
              fit: BoxFit.contain,
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
