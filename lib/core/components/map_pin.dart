import 'package:flutter/material.dart';
import 'map_pin_painter.dart';

class MapPin extends StatelessWidget {
  final Color color;

  const MapPin({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(32, 40),
      painter: MapPinPainter(color: color),
    );
  }
}

