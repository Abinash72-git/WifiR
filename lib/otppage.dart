import 'package:flutter/material.dart';
import 'package:wifir/homepage.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

class OTPScreen extends StatefulWidget {
  final String mobile;

  const OTPScreen({super.key, required this.mobile});

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final TextEditingController otpController = TextEditingController();
  bool isValid = false;

  void verifyOTP() {
    final otp = otpController.text.trim();
    if (otp.length == 6) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const Homepage()),
        (route) => false, // removes all previous routes
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid 6-digit OTP"),),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sh = MediaQuery.of(context).size.height;
    final sw = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        title: const Text("OTP Verification", textScaler: TextScaler.linear(1),),
        backgroundColor: Colors.blueGrey,
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
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: sw * 0.05),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                  height: 60,
                ), // 👈 Add this to push entire content down
                Image.asset(
                  "assets/wifir_launcher.png",
                  height: 120,
                  width: 120,
                ),
                const Text(
                  "WIFIR",
                  style: TextStyle(
                    fontSize: 28,
                    color: Colors.green,
                    fontWeight: FontWeight.w900,
                  ),
                  textScaler: TextScaler.linear(1),
                ),
                const SizedBox(height: 30),
                Text(
                  "OTP sent to ${widget.mobile}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ), textScaler: TextScaler.linear(1),
                ),
                const SizedBox(height: 20),
                PinCodeTextField(
                  appContext: context,
                  length: 6,
                  obscureText: true, // mask the digits with •
                  animationType: AnimationType.scale,
                  keyboardType: TextInputType.number,
                  controller: otpController,
                  pinTheme: PinTheme(
                    shape: PinCodeFieldShape.circle,
                    borderRadius: BorderRadius.circular(5),
                    fieldHeight: 50,
                    fieldWidth: 50,
                    activeFillColor: Colors.white,
                    selectedFillColor: Colors.white,
                    inactiveFillColor: Colors.white,
                    inactiveColor: Colors.grey,
                    selectedColor: Colors.green,
                    activeColor: Colors.green,
                  ),
                  animationDuration: const Duration(milliseconds: 300),
                  enableActiveFill: true,
                  onChanged: (value) {
                    setState(() {
                      isValid = value.length == 6;
                    });
                  },
                ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isValid ? verifyOTP : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "Verify",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ), textScaler: TextScaler.linear(1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
