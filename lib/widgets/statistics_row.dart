import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Six-cell statistics grid: AVG / ES / SD on the top row, MIN / MAX / CNT
/// on the bottom. Replaces the prior 3-cell row to match the design's
/// instrument-cluster glance pattern.
class StatisticsRow extends StatelessWidget {
  final String average;
  final String extremeSpread;
  final String standardDeviation;
  final String minValue;
  final String maxValue;
  final int count;
  final String unit;
  final bool showStats;
  final int shotCount;

  const StatisticsRow({
    super.key,
    required this.average,
    required this.extremeSpread,
    required this.standardDeviation,
    required this.minValue,
    required this.maxValue,
    required this.count,
    required this.unit,
    required this.showStats,
    required this.shotCount,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = Responsive.isCompact(context);

    if (!showStats) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16,
          vertical: isCompact ? 14 : 18,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.info_outline,
              size: 14,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Text(
              shotCount == 0
                  ? 'Stats appear after your first shot'
                  : 'One more shot to unlock stats',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _Cell(label: 'AVG', value: average, unit: unit)),
                _Sep(),
                Expanded(
                  child: _Cell(
                    label: 'ES',
                    value: extremeSpread,
                    unit: unit,
                    accent: AppColors.accentSoft,
                  ),
                ),
                _Sep(),
                Expanded(
                  child: _Cell(
                    label: 'SD',
                    value: standardDeviation,
                    unit: unit,
                    accent: AppColors.good,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _Cell(label: 'MIN', value: minValue, unit: unit)),
                _Sep(),
                Expanded(child: _Cell(label: 'MAX', value: maxValue, unit: unit)),
                _Sep(),
                Expanded(
                  child: _Cell(
                    label: 'CNT',
                    value: '$count',
                    unit: '',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color? accent;

  const _Cell({
    required this.label,
    required this.value,
    required this.unit,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: AppFonts.numerals,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: accent ?? AppColors.textPrimary,
                  height: 1.0,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: AppColors.border);
  }
}
