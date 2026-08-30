import 'package:flutter/material.dart';
import 'package:nak_tumpang/core/theme/app_colors.dart';
import 'package:nak_tumpang/core/components/base_button.dart';

class MixedRouteOptionCard extends StatelessWidget {
  final String firstMileType;
  final String? driverAName;
  final String? driverADepartTime;
  final double? pickupDistanceKm;

  final String boardStation;
  final String alightStation;
  final String trainLine;
  final Color trainColor;
  final int trainStops;
  final int trainDuration;

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

  const MixedRouteOptionCard({
    super.key,
    required this.firstMileType,
    this.driverAName,
    this.driverADepartTime,
    this.pickupDistanceKm,

    required this.boardStation,
    required this.alightStation,
    required this.trainLine,
    required this.trainColor,
    required this.trainStops,
    required this.trainDuration,

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
  });

  // Capitalize name and append type (LRT/Monorail/MRT)
  String _formatStationName(String name, String lineName) {
    // Title case formatting
    final formattedName = name.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');

    // Determine transit suffix
    String suffix = 'LRT';
    if (lineName.toLowerCase().contains('mrl') || lineName.toLowerCase().contains('monorail')) {
      suffix = 'Monorail';
    } else if (lineName.toLowerCase().contains('mrt')) {
      suffix = 'MRT';
    }

    return '$formattedName $suffix';
  }

  @override
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

        // Node 2: Train
        _buildTimelineStep(
          location: _formatStationName(boardStation, trainLine),
          isLast: false,
          isDashed: true,
          child: _buildLrtInfo(trainLine, Icons.train, trainColor, '$trainStops stops • $trainDuration mins'),
        ),

        // Node 3: Last Mile
        _buildTimelineStep(
          location: _formatStationName(alightStation, trainLine),
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
        BaseButton(
          text: 'Request tumpang',
          onPressed: () => print('Requesting mixed route...'),
        ),
      ],
    );
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
                width: 16, height: 16, margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(color: AppColors.primaryYellow, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: isDashed
                      ? Container(
                    width: 2, margin: const EdgeInsets.symmetric(vertical: 4),
                    child: CustomPaint(painter: _DashedLinePainter()),
                  )
                      : Container(
                    width: 2, margin: const EdgeInsets.symmetric(vertical: 4),
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
                    overflow: TextOverflow.ellipsis
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
          width: 40, height: 40,
          decoration: BoxDecoration(color: AppColors.driverBlueBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: AppColors.greyText),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w600)),
            if (distanceKm != null)
              Text('${distanceKm.toStringAsFixed(1)} km from your pickup', style: const TextStyle(fontSize: 12, color: AppColors.greyText)),
            Text('Departs at $time', style: const TextStyle(fontSize: 12, color: AppColors.greyText)),
          ],
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
          width: 40, height: 40,
          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.directions_walk, color: Colors.green),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(actionText, style: const TextStyle(fontSize: 14, color: AppColors.black, fontWeight: FontWeight.w600)),
            Text('$formattedDistance • $durationMins mins', style: const TextStyle(fontSize: 12, color: AppColors.greyText)),
          ],
        ),
      ],
    );
  }

  Widget _buildLrtInfo(String lineName, IconData icon, Color iconColor, String detail) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
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