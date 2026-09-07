import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';

// shown when user choose to create new account
class RoleSelectionDialog extends StatelessWidget {
  final bool dismissible;

  const RoleSelectionDialog({super.key, this.dismissible = false});

  /// Show the dialog and return the chosen role, or null if the user
  /// canceled (only possible when [dismissible] is true — e.g. the
  /// login screen's "create an account" entry point, where backing out
  /// should return to login). Callers that can't sensibly proceed
  /// without a role (e.g. first-time profile setup) should leave
  /// [dismissible] false and treat the result as non-null.
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dismissible)
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.close, color: AppColors.greyText),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
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