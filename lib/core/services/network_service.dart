import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class NetworkService {
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
  static final ValueNotifier<bool> isOfflineNotifier = ValueNotifier<bool>(false);

  static Future<void> initialize() async {
    // 1. Instantly check the current status on boot
    final initialResults = await Connectivity().checkConnectivity();
    isOfflineNotifier.value = initialResults.contains(ConnectivityResult.none);

    // Trigger the UI update for the boot state
    _updateUI(isOfflineNotifier.value);

    // 2. Listen for all future changes
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isOffline = results.contains(ConnectivityResult.none);

      if (isOfflineNotifier.value == isOffline) return;

      isOfflineNotifier.value = isOffline;
      _updateUI(isOffline);
    });
  }

  static void _updateUI(bool isOffline) {
    // If the app just booted, the ScaffoldMessenger isn't attached yet.
    // We wait 200ms and try again until the UI is ready to receive the Snackbar.
    if (messengerKey.currentState == null) {
      Future.delayed(const Duration(milliseconds: 200), () => _updateUI(isOffline));
      return;
    }

    messengerKey.currentState?.clearSnackBars();

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
          duration: Duration(days: 365),
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.none,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}