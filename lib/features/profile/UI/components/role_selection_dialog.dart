import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

class RoleSelectionDialog extends StatelessWidget {
  final bool dismissible;

  const RoleSelectionDialog({super.key, this.dismissible = false});

  static Future<String?> show(BuildContext context, {bool dismissible = false}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: dismissible,
      builder: (_) => RoleSelectionDialog(dismissible: dismissible),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: dismissible,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'How will you be using Nak Tumpang?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.black,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (dismissible)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.close, color: AppColors.greyText),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
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
                    style: TextStyle(color: AppColors.greyText, fontSize: 12),
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