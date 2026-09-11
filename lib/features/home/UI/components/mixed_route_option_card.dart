import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';
import 'package:nak_tumpang/core/constants/transit_constants.dart'; // Add this import

class MixedRouteOptionCard extends StatelessWidget {
  final String firstMileType;
  final String? driverAName;
  final String? driverADepartTime;
  final double? pickupDistanceKm;

  final String boardStation;
  final String alightStation;
  final int trainDuration;

  final bool isInterchange;
  final String boardLineName;
  final String boardLineShortName;
  final Color boardLineColor;
  final String alightLineName;
  final String alightLineShortName;
  final Color alightLineColor;

  final String lastMileType;
  final String? driverBName;
  final String? driverBDepartTime;
  final double? dropoffDistanceKm;

  final String pickupLocation;
  final String destinationLocation;
  final double walkToStationMeters;
  final int walkToStationMins;
  final double walkToDestMeters;
  final int walkToDestMins;

  final VoidCallback? onRequestTumpang;
  final bool isRequested;

  const MixedRouteOptionCard({
    super.key,
    required this.firstMileType,
    this.driverAName,
    this.driverADepartTime,
    this.pickupDistanceKm,
    required this.boardStation,
    required this.alightStation,
    required this.trainDuration,
    required this.isInterchange,
    required this.boardLineName,
    required this.boardLineShortName,
    required this.boardLineColor,
    required this.alightLineName,
    required this.alightLineShortName,
    required this.alightLineColor,
    required this.lastMileType,
    this.driverBName,
    this.driverBDepartTime,
    this.dropoffDistanceKm,
    required this.pickupLocation,
    required this.destinationLocation,
    required this.walkToStationMeters,
    required this.walkToStationMins,
    required this.walkToDestMeters,
    required this.walkToDestMins,
    this.onRequestTumpang,
    this.isRequested = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Node 1: First Mile
        _buildTimelineStep(
          location: pickupLocation,
          isLast: false,
          child: firstMileType == 'Driver' && driverAName != null
              ? _buildDriverInfo(driverAName!, Icons.directions_car, driverADepartTime!, pickupDistanceKm)
              : _buildWalkInfo('Walk to station', distanceMeters: walkToStationMeters, durationMins: walkToStationMins),
        ),

        // Node 2: Train Step
        _buildTimelineStep(
          // --- Use TransitConstants here ---
          location: TransitConstants.formatStationName(boardStation, boardLineShortName),
          isLast: false,
          isDashed: true,
          child: _buildTrainInfo(),
        ),

        // Node 3: Last Mile
        _buildTimelineStep(
          // --- Use TransitConstants here ---
          location: TransitConstants.formatStationName(alightStation, alightLineShortName),
          isLast: false,
          child: lastMileType == 'Driver' && driverBName != null
              ? _buildDriverInfo(driverBName!, Icons.directions_car, driverBDepartTime!, dropoffDistanceKm)
              : _buildWalkInfo('Walk to destination', distanceMeters: walkToDestMeters, durationMins: walkToDestMins),
        ),

        // Node 4: Destination
        _buildTimelineStep(
          location: destinationLocation,
          isLast: true,
          child: const SizedBox.shrink(),
        ),

        const SizedBox(height: 16),
        isRequested
            ? ElevatedButton(
          onPressed: () {}, // Disabled state
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade200,
            foregroundColor: Colors.grey.shade500,
            elevation: 0,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 18),
              SizedBox(width: 8),
              Text('Requested Tumpang', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        )
            : BaseButton(
          text: 'Request tumpang',
          onPressed: onRequestTumpang,
        ),
      ],
    );
  }

  Widget _buildTrainInfo() {
    if (isInterchange) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.greyBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.train, color: boardLineColor, size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    boardLineShortName,
                    style: TextStyle(color: boardLineColor, fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, color: Colors.grey, size: 16),
                ),
                Icon(Icons.train, color: alightLineColor, size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    alightLineShortName,
                    style: TextStyle(color: alightLineColor, fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('~ $trainDuration mins (Line Transfer)', style: const TextStyle(fontSize: 12, color: AppColors.greyText)),
          ],
        ),
      );
    }

    // --- Use TransitConstants here ---
    return _buildLrtInfo(TransitConstants.getLineName(boardLineShortName, boardLineName), Icons.train, boardLineColor, '~ $trainDuration mins');
  }

  Widget _buildTimelineStep({
    required String location,
    required bool isLast,
    bool isDashed = false,
    required Widget child,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(color: AppColors.primaryYellow, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: isDashed
                      ? Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: CustomPaint(painter: _DashedLinePainter()),
                  )
                      : Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.primaryYellow,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                child,
                if (!isLast) const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverInfo(String name, IconData icon, String time, double? distanceKm) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: AppColors.driverBlueBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: AppColors.greyText),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (distanceKm != null)
                Text('${distanceKm.toStringAsFixed(1)} km from your pickup', style: const TextStyle(fontSize: 12, color: AppColors.greyText), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('Departs at $time', style: const TextStyle(fontSize: 12, color: AppColors.greyText), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWalkInfo(String actionText, {required double distanceMeters, required int durationMins}) {
    final formattedDistance = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
        : '${distanceMeters.toInt()} m';

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.directions_walk, color: Colors.green),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(actionText, style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('$formattedDistance • $durationMins mins', style: const TextStyle(fontSize: 12, color: AppColors.greyText), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLrtInfo(String lineName, IconData icon, Color iconColor, String detail) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lineName, style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(detail, style: const TextStyle(fontSize: 12, color: AppColors.greyText), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryYellow
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 5.0;
    const dashSpace = 4.0;
    double startY = 0.0;

    while (startY < size.height) {
      canvas.drawLine(Offset(size.width / 2, startY), Offset(size.width / 2, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}