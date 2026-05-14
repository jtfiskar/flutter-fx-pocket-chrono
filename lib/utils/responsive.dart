import 'package:flutter/material.dart';

/// Lightweight helpers for adjusting layout on very small devices.
class Responsive {
  /// Treat screens narrower than 360 or shorter than 720 as compact.
  static bool isCompact(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width < 360 || size.height < 720;
  }

  /// Returns `compact` when compact, otherwise `regular`.
  static T value<T>({
    required BuildContext context,
    required T compact,
    required T regular,
  }) {
    return isCompact(context) ? compact : regular;
  }

  /// Clamp text scale so large accessibility settings don't break layout.
  static double clampedTextScale(BuildContext context, {double max = 1.2}) {
    final scale = MediaQuery.textScaleFactorOf(context);
    return scale.clamp(1.0, max).toDouble();
  }
}
