import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Large velocity display widget - the main focal point of the UI.
///
/// Shows current velocity in large text with unit label.
/// Tap to toggle between FPS and m/s.
class VelocityDisplay extends StatelessWidget {
  /// Velocity value to display (formatted string)
  final String value;

  /// Unit label (e.g., "fps" or "m/s")
  final String unit;

  /// Whether device is connected and receiving data
  final bool isConnected;

  /// Callback when tapped (to toggle unit)
  final VoidCallback? onTap;

  const VelocityDisplay({
    super.key,
    required this.value,
    required this.unit,
    required this.isConnected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    final numberSize = isCompact ? 72.0 : 96.0;
    final unitSize = isCompact ? 20.0 : 24.0;
    final verticalPadding = isCompact ? 24.0 : 32.0;
    final textScale = Responsive.clampedTextScale(context, max: isCompact ? 1.1 : 1.2);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Large velocity number
            Text(
              value.isEmpty || value == '0' ? '---' : value,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: numberSize,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.0,
              ),
              textScaleFactor: textScale,
            ),
            SizedBox(height: isCompact ? 6 : 8),
            // Unit label with tap hint
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: unitSize,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                  textScaleFactor: textScale,
                ),
                SizedBox(width: isCompact ? 6 : 8),
                Icon(
                  Icons.swap_horiz,
                  size: isCompact ? 18 : 20,
                  color: AppColors.toggleHint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
