import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class NetworkService {
  // This key allows us to show Snackbars from anywhere without needing a BuildContext
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void initialize() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // If the only result is 'none', the device has lost all connections
      final isOffline = results.contains(ConnectivityResult.none);

      if (isOffline) {
        messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.white),
                SizedBox(width: 12),
                Text('You are offline. Showing local cache.'),
              ],
            ),
            duration: Duration(days: 365), // Persistent
            behavior: SnackBarBehavior.floating,
            dismissDirection: DismissDirection.none, // Prevents user from swiping it away
            backgroundColor: Colors.redAccent,
          ),
        );
      } else {
        // Hides the snackbar as soon as connection is restored
        messengerKey.currentState?.hideCurrentSnackBar();
      }
    });
  }
}