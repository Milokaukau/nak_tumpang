import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class RouteMapHeader extends StatelessWidget {
  final String label;

  const RouteMapHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.greyBorder),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, color: Colors.red, size: 32),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}