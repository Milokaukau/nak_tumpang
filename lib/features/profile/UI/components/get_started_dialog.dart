import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class GetStartedDialog extends StatelessWidget {
  const GetStartedDialog({super.key});

  static Future<String> show(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const GetStartedDialog(),
    );
    return choice ?? 'later';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Let's get started!",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first trip now, or explore the app first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.greyText, fontSize: 13),
            ),
            const SizedBox(height: 20),
            BaseButton(
              text: '+ Add trip',
              onPressed: () => Navigator.of(context).pop('add_trip'),
            ),
            const SizedBox(height: 10),
            BaseButton(
              text: 'Later',
              isOutlined: true,
              onPressed: () => Navigator.of(context).pop('later'),
            ),
          ],
        ),
      ),
    );
  }
}