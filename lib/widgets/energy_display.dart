import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Energy display widget - shows calculated muzzle energy.
///
/// Tap energy to toggle between ft-lbs and Joules.
/// Tap weight icon to open weight input dialog.
class EnergyDisplay extends StatelessWidget {
  /// Energy value to display (formatted string)
  final String value;

  /// Unit label (e.g., "ft-lbs" or "J")
  final String unit;

  /// Callback when energy display tapped (to toggle unit)
  final VoidCallback? onTap;

  /// Callback when weight icon tapped (to open weight dialog)
  final VoidCallback? onWeightTap;

  const EnergyDisplay({
    super.key,
    required this.value,
    required this.unit,
    this.onTap,
    this.onWeightTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    final valueSize = isCompact ? 24.0 : 28.0;
    final unitSize = isCompact ? 16.0 : 18.0;
    final iconSize = isCompact ? 14.0 : 16.0;
    final verticalPadding = isCompact ? 6.0 : 8.0;
    final textScale = Responsive.clampedTextScale(context, max: isCompact ? 1.1 : 1.2);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Energy display (tappable for unit toggle)
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.isEmpty || value == '0.0' ? '---' : value,
                  style: TextStyle(
                    fontSize: valueSize,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  textScaleFactor: textScale,
                ),
                SizedBox(width: isCompact ? 6 : 8),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: unitSize,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                  textScaleFactor: textScale,
                ),
                SizedBox(width: isCompact ? 3 : 4),
                Icon(
                  Icons.swap_horiz,
                  size: iconSize,
                  color: AppColors.toggleHint,
                ),
              ],
            ),
          ),
        ),
        // Weight icon button
        if (onWeightTap != null) ...[
          SizedBox(width: isCompact ? 12 : 16),
          GestureDetector(
            onTap: onWeightTap,
            child: Container(
              padding: EdgeInsets.all(isCompact ? 6 : 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.fitness_center,
                size: isCompact ? 18 : 20,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
