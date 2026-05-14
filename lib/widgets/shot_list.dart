import 'package:flutter/material.dart';
import '../models/shot.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Scrollable list of shots — most recent first.
///
/// Each row is a 5-column grid: index · velocity · energy · Δ-badge · elapsed.
/// The latest row gets an amber gradient background and border.
class ShotList extends StatelessWidget {
  final List<Shot> shots;
  final String Function(int fps) formatVelocity;
  final String Function(int fps) formatEnergy;
  final String velocityUnit;
  final String energyUnit;
  final double averageFps;
  final double standardDeviationFps;
  final DateTime? sessionStart;
  final double? maxHeight;

  /// User's velocity unit preference. The Δ-from-mean badge converts to
  /// m/s when this is false so it stays in the same unit as the velocity
  /// column rendered beside it.
  final bool useFps;

  const ShotList({
    super.key,
    required this.shots,
    required this.formatVelocity,
    required this.formatEnergy,
    required this.velocityUnit,
    required this.energyUnit,
    required this.averageFps,
    required this.standardDeviationFps,
    required this.sessionStart,
    required this.useFps,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (shots.isEmpty) {
      return _empty(context);
    }

    final reversed = shots.reversed.toList();
    // When the caller supplies a maxHeight, scroll inside that bounded box.
    // Without one (e.g. inside an outer page ListView) defer scrolling to
    // the parent so drags on the table don't fight page scroll.
    final physics = maxHeight != null
        ? const AlwaysScrollableScrollPhysics()
        : const NeverScrollableScrollPhysics();
    return Container(
      constraints: maxHeight != null
          ? BoxConstraints(maxHeight: maxHeight!)
          : null,
      child: ListView.builder(
        shrinkWrap: true,
        physics: physics,
        itemCount: reversed.length,
        itemBuilder: (context, index) {
          final shot = reversed[index];
          return _Row(
            shot: shot,
            formatVelocity: formatVelocity,
            formatEnergy: formatEnergy,
            velocityUnit: velocityUnit,
            energyUnit: energyUnit,
            averageFps: averageFps,
            standardDeviationFps: standardDeviationFps,
            sessionStart: sessionStart,
            useFps: useFps,
            isLatest: index == 0,
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    return Container(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed_outlined,
              size: isCompact ? 36 : 44,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            const Text(
              'No shots yet',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pull the trigger and watch this fill up',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Shot shot;
  final String Function(int fps) formatVelocity;
  final String Function(int fps) formatEnergy;
  final String velocityUnit;
  final String energyUnit;
  final double averageFps;
  final double standardDeviationFps;
  final DateTime? sessionStart;
  final bool useFps;
  final bool isLatest;

  const _Row({
    required this.shot,
    required this.formatVelocity,
    required this.formatEnergy,
    required this.velocityUnit,
    required this.energyUnit,
    required this.averageFps,
    required this.standardDeviationFps,
    required this.sessionStart,
    required this.useFps,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    final delta = averageFps > 0
        ? (shot.velocityFps - averageFps)
        : 0.0;
    final hasDelta = averageFps > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isLatest ? AppColors.surfaceElevated : null,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#${shot.number}',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isLatest ? AppColors.accent : AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatVelocity(shot.velocityFps),
                  style: TextStyle(
                    fontFamily: AppFonts.numerals,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isLatest
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  velocityUnit,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${formatEnergy(shot.velocityFps)} $energyUnit',
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          if (hasDelta) ...[
            _deltaBadge(delta),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 44,
            child: Text(
              _elapsed(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deltaBadge(double delta) {
    // Tolerance comparison and sign run in fps space (raw numerics);
    // only the displayed number converts.
    final absDelta = delta.abs();
    final threshold = standardDeviationFps > 0
        ? standardDeviationFps * 0.5
        : 5.0;
    final Color color;
    if (absDelta <= threshold) {
      color = AppColors.good;
    } else if (delta < 0) {
      color = AppColors.warn;
    } else {
      color = AppColors.accentSoft;
    }
    final sign = delta == 0
        ? '±'
        : delta > 0
            ? '+'
            : '−';
    final displayDelta = useFps ? absDelta : absDelta * 0.3048;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$sign${displayDelta.toStringAsFixed(displayDelta < 10 ? 1 : 0)}',
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _elapsed() {
    if (sessionStart == null) return '';
    final diff = shot.timestamp.difference(sessionStart!);
    final minutes = diff.inMinutes;
    final seconds = diff.inSeconds % 60;
    if (minutes < 0 || diff.inSeconds < 0) return '';
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
