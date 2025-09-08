// class WifiHistory {
//   final String ssid;
//   final String status; // "Connected" or "Disconnected"
//   final DateTime timestamp; // ✅ Use DateTime

//   WifiHistory({
//     required this.ssid,
//     required this.status,
//     required this.timestamp,
//   });
// }

// model/wifihistory.dart
class WifiHistory {
  final String ssid;
  final String status; // "Connected", "Disconnected", "Connection Failed", etc.
  final DateTime timestamp;

  WifiHistory({
    required this.ssid,
    required this.status,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'WifiHistory{ssid: $ssid, status: $status, timestamp: $timestamp}';
  }
}
