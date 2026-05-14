import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DataCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color? valueColor;
  final VoidCallback? onTap;

  const DataCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label row
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label.toUpperCase(),
                  style: WindCallTextStyles.dataLabel,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Value row
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: WindCallTextStyles.dataValue.copyWith(
                      color: valueColor ?? AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit!,
                    style: WindCallTextStyles.dataLabel.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Wind speed data card with special styling
class WindSpeedCard extends StatelessWidget {
  final double speedMs;
  final bool isConnected;

  const WindSpeedCard({
    super.key,
    required this.speedMs,
    this.isConnected = false,
  });

  @override
  Widget build(BuildContext context) {
    return DataCard(
      label: 'Wind Speed',
      value: isConnected ? speedMs.toStringAsFixed(1) : '---',
      unit: isConnected ? 'm/s' : null,
      icon: Icons.air,
      valueColor: isConnected ? null : AppColors.textTertiary,
    );
  }
}

/// Wind direction data card with cardinal direction
class WindDirectionCard extends StatelessWidget {
  final int directionDeg;
  final bool isConnected;

  const WindDirectionCard({
    super.key,
    required this.directionDeg,
    this.isConnected = false,
  });

  String get _cardinalDirection {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((directionDeg + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  @override
  Widget build(BuildContext context) {
    return DataCard(
      label: 'Direction',
      value: isConnected ? '$_cardinalDirection $directionDeg°' : '---',
      icon: Icons.explore,
      valueColor: isConnected ? null : AppColors.textTertiary,
    );
  }
}

/// Horizontal layout with two data cards side by side
class DataCardRow extends StatelessWidget {
  final Widget left;
  final Widget right;

  const DataCardRow({
    super.key,
    required this.left,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

/// Small inline data display (for setup bar)
class DataChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool showArrow;

  const DataChip({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textTertiary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: WindCallTextStyles.chipText,
                ),
              ],
            ),
            if (showArrow && onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
