// dummy scrren for test

import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class TumpangSummaryScreen extends StatelessWidget {
  final String requestId;

  const TumpangSummaryScreen({
    super.key,
    required this.requestId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Summary', style: TextStyle(color: AppColors.black, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryYellow,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.handshake, size: 80, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Agreement Reached!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Request ID: $requestId'),
            const SizedBox(height: 24),
            const Text('Tumpang summary screen under construction...'),
          ],
        ),
      ),
    );
  }
}