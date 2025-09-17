// import 'package:flutter_background_service/flutter_background_service.dart';
// import 'package:flutter_background_service_android/flutter_background_service_android.dart';

// Future<void> initializeService() async {
//   final service = FlutterBackgroundService();

//   await service.configure(
//     androidConfiguration: AndroidConfiguration(
//       onStart: onStart,
//       autoStart: true,
//       isForegroundMode: true,
//       foregroundServiceNotificationId: 888,
//       initialNotificationTitle: 'Wifir Service',
//       initialNotificationContent: 'Running in the background...',
//     ),
//     iosConfiguration: IosConfiguration(),
//   );

//   service.startService();
// }

// void onStart(ServiceInstance service) {
//   if (service is AndroidServiceInstance) {
//     service.setForegroundNotificationInfo(
//       title: "Wifir Service",
//       content: "Monitoring WiFi in the background...",
//     );
//   }
// }




