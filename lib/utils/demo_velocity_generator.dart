import 'dart:math';

import '../config/app_config.dart';

/// Generates realistic demo velocities with normal distribution variation.
///
/// For airguns, typical velocity is 800-950 FPS with 1-2% standard deviation.
class DemoVelocityGenerator {
  final Random _random = Random();

  final int minVelocityFps;
  final int maxVelocityFps;
  final double stdDevPercent;

  late final int _meanVelocity;
  late final double _stdDev;

  DemoVelocityGenerator({
    this.minVelocityFps = AppConfig.demoMinVelocityFps,
    this.maxVelocityFps = AppConfig.demoMaxVelocityFps,
    this.stdDevPercent = AppConfig.demoStdDevPercent,
  }) {
    _meanVelocity = (minVelocityFps + maxVelocityFps) ~/ 2;
    _stdDev = _meanVelocity * (stdDevPercent / 100);
  }

  /// Generate a single velocity using Box-Muller transform for normal distribution.
  int generateVelocity() {
    // Box-Muller transform: convert uniform random to normal distribution
    final u1 = _random.nextDouble();
    final u2 = _random.nextDouble();

    // Standard normal variate (mean=0, stddev=1)
    final z = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);

    // Scale to our distribution
    final velocity = _meanVelocity + (z * _stdDev);

    // Clamp to realistic range and round to integer
    return velocity.round().clamp(minVelocityFps, maxVelocityFps).toInt();
  }
}
