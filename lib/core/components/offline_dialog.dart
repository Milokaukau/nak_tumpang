import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

/// Shows a blocking "you're offline" message for an action that can't be
/// completed without a connection (creating a trip, registering, ...).
///
/// A dialog rather than a SnackBar on purpose: while the device is
/// offline, NetworkService keeps a permanent SnackBar up (duration: 365
/// days, non-dismissible) on the app's single root ScaffoldMessenger.
/// ScaffoldMessenger shows one SnackBar at a time and queues the rest,
/// so a second SnackBar raised while that one is displayed simply never
/// appears — which is exactly the situation every one of these messages
/// is raised in. Hiding the persistent one first isn't a fix either:
/// that removes the offline banner for good and leaves the user with no
/// standing indication they're offline.
Future<void> showOfflineDialog(
    BuildContext context, {
      required String message,
      String title = "You're offline",
    }) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.wifi_off, color: Colors.red),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('OK', style: TextStyle(color: AppColors.black)),
        ),
      ],
    ),
  );
}