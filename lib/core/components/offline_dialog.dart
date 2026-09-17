import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

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