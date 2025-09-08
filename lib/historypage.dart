// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:wifir/model/wifihistory.dart';

// class HistoryPage extends StatelessWidget {
//   final List<WifiHistory> wifiHistoryList;

//   const HistoryPage({super.key, required this.wifiHistoryList});
//   void saveWifiHistory(String ssid, String status) {
//     final timestamp = DateTime.now(); // ✅ Keep DateTime, not String
//     wifiHistoryList.add(
//       WifiHistory(ssid: ssid, status: status, timestamp: timestamp),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("WiFi History")),
//       body: wifiHistoryList.isEmpty
//           ? const Center(child: Text("No WiFi history found"))
//           : ListView.builder(
//               itemCount: wifiHistoryList.length,
//               itemBuilder: (context, index) {
//                 final history = wifiHistoryList[index];
//                 return ListTile(
//                   leading: Icon(
//                     history.status == "Connected" ? Icons.wifi : Icons.wifi_off,
//                     color: history.status == "Connected"
//                         ? Colors.green
//                         : Colors.red,
//                   ),
//                   title: Text(history.ssid),
//                   subtitle: Text(
//                     "${history.status} • ${DateFormat('yyyy-MM-dd HH:mm:ss').format(history.timestamp)}",
//                   ),
//                 );
//               },
//             ),
//     );
//   }
// }

// historypage.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wifir/model/wifihistory.dart';

class HistoryPage extends StatelessWidget {
  final List<WifiHistory> wifiHistoryList;

  const HistoryPage({super.key, required this.wifiHistoryList});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        title: const Text(
          "WiFi History",
          style: TextStyle(fontWeight: FontWeight.bold),
          textScaler: TextScaler.linear(1),
        ),
        actions: [
          if (wifiHistoryList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text(
                      "Clear History",
                      textScaler: TextScaler.linear(1),
                    ),
                    content: const Text(
                      "Are you sure you want to clear all WiFi history?",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "Cancel",
                          textScaler: TextScaler.linear(1),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          wifiHistoryList.clear();
                          Navigator.pop(context);
                          Navigator.pop(context); // Go back to homepage
                        },
                        child: const Text(
                          "Clear",
                          style: TextStyle(color: Colors.red),
                          textScaler: TextScaler.linear(1),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
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
        child: wifiHistoryList.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      "No WiFi history found",
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                      textScaler: TextScaler.linear(1),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Connect or disconnect from WiFi networks to see history",
                      style: TextStyle(color: Colors.grey),
                      textScaler: TextScaler.linear(1),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: wifiHistoryList.length,
                itemBuilder: (context, index) {
                  final history =
                      wifiHistoryList[wifiHistoryList.length -
                          1 -
                          index]; // Show newest first
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getStatusColor(history.status),
                        child: Icon(
                          _getStatusIcon(history.status),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        history.ssid,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "${history.status} • ${DateFormat('MMM dd, yyyy • hh:mm a').format(history.timestamp)}",
                        textScaler: TextScaler.linear(1),
                      ),
                      trailing: Text(
                        _getTimeAgo(history.timestamp),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        textScaler: TextScaler.linear(1),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Connected":
        return Colors.green;
      case "Disconnected":
        return Colors.orange;
      case "Connection Failed":
      case "Connection Error":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case "Connected":
        return Icons.wifi;
      case "Disconnected":
        return Icons.wifi_off;
      case "Connection Failed":
      case "Connection Error":
        return Icons.error;
      default:
        return Icons.help;
    }
  }

  String _getTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return "Just now";
    } else if (difference.inHours < 1) {
      return "${difference.inMinutes}m ago";
    } else if (difference.inDays < 1) {
      return "${difference.inHours}h ago";
    } else {
      return "${difference.inDays}d ago";
    }
  }
}
