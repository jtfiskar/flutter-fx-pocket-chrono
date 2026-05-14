import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Compact statistics row showing AVG, ES, and SD.
///
/// Displays session statistics in a horizontal row.
class StatisticsRow extends StatelessWidget {
  /// Average velocity (formatted string with unit)
  final String average;

  /// Extreme spread (formatted string)
  final String extremeSpread;

  /// Standard deviation (formatted string)
  final String standardDeviation;

  /// Velocity unit label
  final String unit;

  /// Whether to show the statistics (need 2+ shots)
  final bool showStats;

  /// Number of shots in session
  final int shotCount;

  const StatisticsRow({
    super.key,
    required this.average,
    required this.extremeSpread,
    required this.standardDeviation,
    required this.unit,
    required this.showStats,
    required this.shotCount,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    final containerPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 12 : 16,
      vertical: isCompact ? 10 : 12,
    );

    if (!showStats) {
      // Show placeholder when not enough shots
      return Container(
        padding: containerPadding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: isCompact ? 14 : 16,
              color: AppColors.textTertiary,
            ),
            SizedBox(width: isCompact ? 6 : 8),
            Text(
              shotCount == 0
                  ? 'Start session and shoot to see statistics'
                  : 'Shoot once more to see statistics',
              style: TextStyle(
                fontSize: isCompact ? 13 : 14,
                color: AppColors.textTertiary,
              ),
              textScaleFactor: Responsive.clampedTextScale(context, max: 1.2),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: containerPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(label: 'AVG', value: average, unit: unit),
          _VerticalDivider(),
          _StatItem(label: 'ES', value: extremeSpread, unit: unit),
          _VerticalDivider(),
          _StatItem(label: 'SD', value: standardDeviation, unit: unit),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _StatItem({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    final labelSize = isCompact ? 10.0 : 11.0;
    final valueSize = isCompact ? 16.0 : 18.0;
    final unitSize = isCompact ? 10.0 : 11.0;
    final textScale = Responsive.clampedTextScale(context, max: isCompact ? 1.1 : 1.2);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: labelSize,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textScaleFactor: textScale,
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: TextStyle(
                fontSize: unitSize,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
              textScaleFactor: textScale,
            ),
          ],
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final height = Responsive.isCompact(context) ? 28.0 : 32.0;
    return Container(
      width: 1,
      height: height,
      color: AppColors.border,
    );
  }
}
