import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

/// Shown right before the registration form — asks the new user whether
/// they'll be using Nak Tumpang as a Passenger or a Driver, so the form
/// after this can show the right fields.
class RoleSelectionDialog extends StatelessWidget {
  const RoleSelectionDialog({super.key});

  /// Shows the dialog and returns 'passenger' or 'driver'.
  static Future<String> show(BuildContext context) async {
    final role = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const RoleSelectionDialog(),
    );
    return role ?? 'passenger';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How will you be using Nak Tumpang?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
              ),
              const SizedBox(height: 6),
              _RoleOption(
                icon: Icons.directions_walk_rounded,
                label: 'Passenger',
                sublabel: 'Find a tumpang to your destination',
                onTap: () => Navigator.of(context).pop('passenger'),
              ),
              const SizedBox(height: 12),
              _RoleOption(
                icon: Icons.directions_car_filled_rounded,
                label: 'Driver',
                sublabel: 'Offer a tumpang along your route',
                onTap: () => Navigator.of(context).pop('driver'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final VoidCallback onTap;

  const _RoleOption({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.lightYellow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.greyBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryYellow, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.black,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(color: AppColors.greyText, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.greyText),
          ],
        ),
      ),
    );
  }
}
