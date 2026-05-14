import 'package:flutter/material.dart';
import '../models/shot.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Scrollable list of shots from current session.
///
/// Shows shots in reverse order (most recent first).
class ShotList extends StatelessWidget {
  /// List of shots to display
  final List<Shot> shots;

  /// Format velocity for display
  final String Function(int fps) formatVelocity;

  /// Velocity unit label
  final String unit;

  /// Maximum height for the list (optional)
  final double? maxHeight;

  const ShotList({
    super.key,
    required this.shots,
    required this.formatVelocity,
    required this.unit,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    final emptyIconSize = isCompact ? 40.0 : 48.0;
    final emptyTitleSize = isCompact ? 15.0 : 16.0;
    final emptySubtitleSize = isCompact ? 13.0 : 14.0;

    if (shots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.speed_outlined,
                size: emptyIconSize,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                'No shots recorded',
                style: TextStyle(
                  fontSize: emptyTitleSize,
                  color: AppColors.textSecondary,
                ),
                textScaleFactor: Responsive.clampedTextScale(context, max: 1.2),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap "New Session" and shoot to record',
                style: TextStyle(
                  fontSize: emptySubtitleSize,
                  color: AppColors.textTertiary,
                ),
                textScaleFactor: Responsive.clampedTextScale(context, max: 1.2),
              ),
            ],
          ),
        ),
      );
    }

    // Reverse the list to show most recent first
    final reversedShots = shots.reversed.toList();

    return Container(
      constraints: maxHeight != null
          ? BoxConstraints(maxHeight: maxHeight!)
          : null,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: reversedShots.length,
        itemBuilder: (context, index) {
          final shot = reversedShots[index];
          final isFirst = index == 0;
          return _ShotListItem(
            shot: shot,
            formatVelocity: formatVelocity,
            unit: unit,
            isHighlighted: isFirst,
          );
        },
      ),
    );
  }
}

class _ShotListItem extends StatelessWidget {
  final Shot shot;
  final String Function(int fps) formatVelocity;
  final String unit;
  final bool isHighlighted;

  const _ShotListItem({
    required this.shot,
    required this.formatVelocity,
    required this.unit,
    required this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    final paddingH = isCompact ? 12.0 : 16.0;
    final paddingV = isCompact ? 8.0 : 10.0;
    final numberSize = isCompact ? 13.0 : 14.0;
    final valueSize = isCompact ? 15.0 : 16.0;
    final textScale = Responsive.clampedTextScale(context, max: isCompact ? 1.1 : 1.2);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: isHighlighted ? AppColors.surface : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withOpacity(0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Shot number
          Container(
            width: 32,
            alignment: Alignment.centerLeft,
            child: Text(
              '#${shot.number}',
              style: TextStyle(
                fontSize: numberSize,
                fontWeight: FontWeight.w500,
                color: isHighlighted ? AppColors.primary : AppColors.textTertiary,
              ),
              textScaleFactor: textScale,
            ),
          ),
          // Velocity
          Expanded(
            child: Text(
              '${formatVelocity(shot.velocityFps)} $unit',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: valueSize,
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
                color: isHighlighted ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              textScaleFactor: textScale,
            ),
          ),
        ],
      ),
    );
  }
}
