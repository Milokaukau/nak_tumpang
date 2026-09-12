import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_profile_card.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

enum LegType { driver, transit, walk }

class ActiveSubscriptionLeg {
  final LegType type;
  final String name;
  final String? imageUrl;
  final String pickupLocation;
  final String dropoffLocation;
  final String time;
  final String? exceptionButtonText;
  final VoidCallback? onCallPressed;
  final VoidCallback? onDetailsPressed;
  final VoidCallback? onExceptionPressed;

  const ActiveSubscriptionLeg({
    required this.type,
    required this.name,
    this.imageUrl,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.time,
    this.exceptionButtonText,
    this.onCallPressed,
    this.onDetailsPressed,
    this.onExceptionPressed,
  });
}

class ActiveSubscriptionCard extends StatelessWidget {
  final String tripName;
  final List<ActiveSubscriptionLeg> legs;
  final bool isSelected;
  final VoidCallback? onTap;

  const ActiveSubscriptionCard({
    super.key,
    required this.tripName,
    required this.legs,
    this.isSelected = false,
    this.onTap,
  }) : assert(legs.length > 0, 'ActiveSubscriptionCard needs at least one leg');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.primaryYellow : AppColors.greyBorder,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 10, right: 10),
                child: Text(
                  tripName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.black),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.0),
                child: Divider(height: 12, thickness: 1, color: AppColors.greyBorder),
              ),
              for (int i = 0; i < legs.length; i++) ...[
                _buildLeg(legs[i]),
                if (i != legs.length - 1) _buildLegConnector(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegConnector() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10.0),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Icon(Icons.arrow_downward, size: 12, color: AppColors.greyText),
                SizedBox(width: 2),
                Text(
                  'then',
                  style: TextStyle(fontSize: 10, color: AppColors.greyText, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(child: Divider(height: 1, thickness: 1, color: AppColors.greyBorder)),
        ],
      ),
    );
  }

  Widget _buildLeg(ActiveSubscriptionLeg leg) {
    if (leg.type == LegType.transit) return _buildTransitLeg(leg);
    if (leg.type == LegType.walk) return _buildWalkLeg(leg);
    return _buildDriverLeg(leg);
  }

  Widget _buildTransitLeg(ActiveSubscriptionLeg leg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.teal.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.train, color: Colors.teal, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(leg.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                const SizedBox(height: 2),
                Text('${leg.pickupLocation} ➔ ${leg.dropoffLocation}', style: const TextStyle(fontSize: 11, color: AppColors.greyText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalkLeg(ActiveSubscriptionLeg leg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.directions_walk, color: Colors.blueGrey, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(leg.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                const SizedBox(height: 2),
                Text('${leg.pickupLocation} ➔ ${leg.dropoffLocation}', style: const TextStyle(fontSize: 11, color: AppColors.greyText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverLeg(ActiveSubscriptionLeg leg) {
    return BaseProfileCard(
      hasBorder: false,
      padding: const EdgeInsets.only(left: 10, right: 10, top: 10, bottom: 10),
      profileImageUrl: leg.imageUrl,
      title: Text(
        leg.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 12, color: AppColors.primaryYellow),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  leg.pickupLocation,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.keyboard_double_arrow_right, size: 12, color: AppColors.primaryYellow),
              ),
              const Icon(Icons.location_on_outlined, size: 12, color: AppColors.primaryYellow),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  leg.dropoffLocation,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.schedule, size: 12, color: AppColors.primaryYellow),
              const SizedBox(width: 4),
              Text(leg.time, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
      actionButtons: Column(
        children: [
          if (leg.onCallPressed != null)
            BaseButton(
              text: 'Call',
              onPressed: leg.onCallPressed!,
              height: 32,
              foregroundColor: AppColors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (leg.onDetailsPressed != null)
                Expanded(
                  flex: 2,
                  child: BaseButton(
                    text: 'Details',
                    onPressed: leg.onDetailsPressed!,
                    isOutlined: true,
                    height: 32,
                    textStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 11),
                  ),
                ),
              if (leg.onDetailsPressed != null && leg.onExceptionPressed != null)
                const SizedBox(width: 6),
              if (leg.onExceptionPressed != null)
                Expanded(
                  flex: 3,
                  child: BaseButton(
                    text: leg.exceptionButtonText ?? 'Exception',
                    onPressed: leg.onExceptionPressed!,
                    isOutlined: true,
                    height: 32,
                    textStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}