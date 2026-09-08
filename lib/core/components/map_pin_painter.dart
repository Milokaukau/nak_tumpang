import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class MapPinPainter extends CustomPainter {
  final Color color;

  MapPinPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final headRadius = size.width / 2;
    final headCenter = Offset(size.width / 2, headRadius);

    final path = ui.Path()
      ..moveTo(size.width / 2 - headRadius * 0.62, headRadius * 1.55)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + headRadius * 0.62, headRadius * 1.55)
      ..close();

    final fillPaint = Paint()..color = color;

    canvas.drawPath(path, fillPaint);
    canvas.drawCircle(headCenter, headRadius, fillPaint);

    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(headCenter, headRadius * 0.38, dotPaint);
  }

  @override
  bool shouldRepaint(covariant MapPinPainter oldDelegate) => oldDelegate.color != color;
}