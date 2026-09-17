import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class NetworkService {
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
  static final ValueNotifier<bool> isOfflineNotifier = ValueNotifier<bool>(false);

  static Future<void> initialize() async {
    final initialResults = await Connectivity().checkConnectivity();
    isOfflineNotifier.value = initialResults.contains(ConnectivityResult.none);
    _updateUI(isOfflineNotifier.value);

    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isOffline = results.contains(ConnectivityResult.none);

      if (isOfflineNotifier.value == isOffline) return;

      isOfflineNotifier.value = isOffline;
      _updateUI(isOffline);
    });
  }

  static void _updateUI(bool isOffline) {
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
              Expanded(
                child: Text('You are offline. Showing local cache.'),
              ),
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