import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// BLE-related utility functions.
class BleUtils {
  BleUtils._();

  /// Get signal strength color based on RSSI value.
  static Color getSignalColor(int rssi) {
    if (rssi >= -60) return AppColors.success;
    if (rssi >= -80) return AppColors.warning;
    return AppColors.error;
  }

  /// Get cardinal direction label from degrees (0-360).
  static String getWindDirectionLabel(int degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    int index = ((degrees + 22.5) / 45).floor() % 8;
    return directions[index];
  }
}
