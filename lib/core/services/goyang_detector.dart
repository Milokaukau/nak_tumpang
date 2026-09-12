import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

typedef GoyangCallback = void Function();
typedef MagnitudeCallback = void Function(double gForce);

/// Listens to the accelerometer and fires [onGoyang] when the device is
/// shaken, with a cooldown so one shake doesn't fire repeatedly.
///
/// [onMagnitudeUpdate] is optional and purely for diagnostics — it fires
/// on every sensor reading (unthrottled) so a debug UI can show the live
/// motion value and confirm the sensor stream itself is actually working,
/// independent of whether it's crossing the goyang threshold.
class GoyangDetector {
  final GoyangCallback onGoyang;
  final MagnitudeCallback? onMagnitudeUpdate;
  final double goyangThresholdGravity;
  final int goyangSlopTimeMs;

  StreamSubscription<AccelerometerEvent>? _subscription;
  DateTime? _lastGoyangTime;

  GoyangDetector({
    required this.onGoyang,
    this.onMagnitudeUpdate,
    this.goyangThresholdGravity = 2.0,
    this.goyangSlopTimeMs = 1500,
  });

  void startListening() {
    _subscription = accelerometerEventStream().listen(_onAccelerometerEvent);
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    const g = 9.80665;
    final gX = event.x / g;
    final gY = event.y / g;
    final gZ = event.z / g;
    final gForce = sqrt(gX * gX + gY * gY + gZ * gZ);

    onMagnitudeUpdate?.call(gForce);

    if (gForce > goyangThresholdGravity) {
      final now = DateTime.now();
      if (_lastGoyangTime != null &&
          now.difference(_lastGoyangTime!).inMilliseconds < goyangSlopTimeMs) {
        return;
      }
      _lastGoyangTime = now;
      onGoyang();
    }
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}