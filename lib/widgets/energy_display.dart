import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Energy strip — shows ft·lbs and Joules side-by-side, with a weight
/// button on the right. The unit currently preferred by the user is
/// rendered in primary text; the alternate is muted.
class EnergyDisplay extends StatelessWidget {
  final String ftLbsValue;
  final String joulesValue;

  /// Which unit is the user's primary preference.
  final bool useFtLbs;

  /// Bullet weight in grains (e.g. "16.0 gr").
  final String weightLabel;

  /// Tap on either energy cell toggles the primary unit.
  final VoidCallback? onTap;

  /// Tap on the weight button opens the weight dialog.
  final VoidCallback? onWeightTap;

  const EnergyDisplay({
    super.key,
    required this.ftLbsValue,
    required this.joulesValue,
    required this.useFtLbs,
    required this.weightLabel,
    this.onTap,
    this.onWeightTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    final valueSize = isCompact ? 22.0 : 24.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 14,
        vertical: isCompact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: _cell(
                label: 'ENERGY',
                value: ftLbsValue,
                unit: 'ft·lbs',
                emphasized: useFtLbs,
                valueSize: valueSize,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: AppColors.border,
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: _cell(
                label: 'ENERGY',
                value: joulesValue,
                unit: 'J',
                emphasized: !useFtLbs,
                valueSize: valueSize,
              ),
            ),
          ),
          if (onWeightTap != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onWeightTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.fitness_center,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      weightLabel,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell({
    required String label,
    required String value,
    required String unit,
    required bool emphasized,
    required double valueSize,
  }) {
    final display = value.isEmpty || value == '0.0' ? '—' : value;
    final color = emphasized ? AppColors.textPrimary : AppColors.textTertiary;
    return Column(
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
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              display,
              style: TextStyle(
                fontFamily: AppFonts.numerals,
                fontSize: valueSize,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: TextStyle(
                fontSize: 11,
                color: color == AppColors.textPrimary
                    ? AppColors.textSecondary
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
