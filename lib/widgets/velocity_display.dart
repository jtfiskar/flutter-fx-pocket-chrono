import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// Hero velocity card — the dominant element of the live screen.
///
/// Layout: a LIVE chip + shot counter on top, the 138 px primary numeral
/// below, an alt-unit value beside it, and a tappable swap pill at the
/// bottom. A Δ-from-mean badge floats in the top-right when statistics
/// are available.
class VelocityDisplay extends StatelessWidget {
  final String primaryValue;
  final String primaryUnit;
  final String altValue;
  final String altUnit;
  final int shotIndex;
  final int shotTotal;
  final bool isConnected;
  final bool hasShots;

  /// Mean and SD used for the Δ badge color. Pass 0 to disable.
  final double averageFps;
  final double standardDeviationFps;
  final int velocityFps;

  /// Whether the user prefers fps over m/s. The Δ badge converts when
  /// false so its number reads in the same unit as the hero value above.
  final bool useFps;

  final VoidCallback? onTap;

  const VelocityDisplay({
    super.key,
    required this.primaryValue,
    required this.primaryUnit,
    required this.altValue,
    required this.altUnit,
    required this.shotIndex,
    required this.shotTotal,
    required this.isConnected,
    required this.hasShots,
    required this.averageFps,
    required this.standardDeviationFps,
    required this.velocityFps,
    required this.useFps,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = Responsive.isCompact(context);
    final heroSize = isCompact ? 108.0 : 138.0;
    final showDelta = hasShots && averageFps > 0 && velocityFps > 0;
    final delta = velocityFps - averageFps;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(isCompact ? 14 : 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerRow(showDelta, delta),
            const SizedBox(height: 4),
            _heroRow(heroSize),
            const SizedBox(height: 8),
            _swapPill(isCompact),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(bool showDelta, double delta) {
    // LIVE means we're actually receiving broadcasts. If the session has
    // shots but the device dropped, the last reading is stale — show a
    // PAUSED pill so the status here doesn't contradict the BLE status
    // pill on the screen header.
    final liveChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: AppColors.background,
          letterSpacing: 1.2,
        ),
      ),
    );
    final pausedChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'PAUSED',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: AppColors.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
    return Row(
      children: [
        if (hasShots) ...[
          isConnected ? liveChip : pausedChip,
          const SizedBox(width: 8),
          Text(
            '#$shotIndex / $shotTotal',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ] else
          const Text(
            'AWAITING SHOT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 1.5,
            ),
          ),
        const Spacer(),
        if (showDelta) _deltaBadge(delta),
      ],
    );
  }

  Widget _deltaBadge(double delta) {
    // Tolerance comparison runs in fps space (raw numerical) regardless of
    // unit toggle; only the displayed value converts.
    final absDelta = delta.abs();
    final threshold = standardDeviationFps > 0 ? standardDeviationFps * 0.5 : 5.0;
    final inTolerance = absDelta <= threshold;
    final color = inTolerance ? AppColors.good : AppColors.warn;
    final sign = delta >= 0 ? '+' : '−';
    final displayDelta = useFps ? absDelta : absDelta * 0.3048;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$sign${displayDelta.toStringAsFixed(displayDelta < 10 ? 1 : 0)}',
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _heroRow(double heroSize) {
    final display = primaryValue.isEmpty || primaryValue == '0'
        ? '—'
        : primaryValue;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              display,
              style: TextStyle(
                fontFamily: AppFonts.numerals,
                fontSize: heroSize,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
                height: 0.95,
                shadows: const [
                  Shadow(
                    color: AppColors.accentGlow,
                    blurRadius: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hasShots && altValue.isNotEmpty ? altValue : '—',
                style: const TextStyle(
                  fontFamily: AppFonts.numerals,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                altUnit,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _swapPill(bool isCompact) {
    final alt = altUnit.isEmpty ? '' : ' to $altUnit';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                primaryUnit.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.swap_horiz,
                size: 12,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 2),
              Text(
                'tap$alt',
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textTertiary,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
