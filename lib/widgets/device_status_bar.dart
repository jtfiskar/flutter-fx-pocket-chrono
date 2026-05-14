import 'package:flutter/material.dart';
import '../models/chronograph_device.dart';
import '../theme/app_theme.dart';

/// Compact BLE status pill — replaces the previous full-width bar so the
/// status chip can anchor top-left without crowding the hero velocity.
class DeviceStatusBar extends StatelessWidget {
  final ChronographDevice? device;
  final bool isScanning;
  final bool isReconnecting;
  final bool isTimedOut;
  final VoidCallback onTap;

  const DeviceStatusBar({
    super.key,
    required this.device,
    required this.isScanning,
    required this.onTap,
    this.isReconnecting = false,
    this.isTimedOut = false,
  });

  @override
  Widget build(BuildContext context) {
    final state = _resolveState();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(color: state.color, pulse: state.pulse),
            const SizedBox(width: 8),
            Text(
              state.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: 0.3,
              ),
            ),
            if (device != null && !state.disconnected) ...[
              const SizedBox(width: 8),
              Container(width: 1, height: 12, color: AppColors.border),
              const SizedBox(width: 8),
              Icon(
                _batteryIcon(device!.batteryPercent),
                size: 14,
                color: _batteryColor(device!.batteryPercent),
              ),
              const SizedBox(width: 3),
              Text(
                '${device!.batteryPercent}%',
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _batteryColor(device!.batteryPercent),
                ),
              ),
            ],
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  _State _resolveState() {
    final isConnected = device != null && !device!.isLost;
    final isLost = device != null && device!.isLost;

    if (isLost && isTimedOut) {
      return _State(label: 'Lost', color: AppColors.danger);
    }
    if (isLost && isReconnecting) {
      return _State(label: 'Reconnecting', color: AppColors.warn, pulse: true);
    }
    if (isLost) {
      return _State(label: 'Lost', color: AppColors.danger);
    }
    if (isConnected) {
      return _State(label: device!.name, color: AppColors.good);
    }
    if (isScanning) {
      return _State(label: 'Scanning', color: AppColors.warn, pulse: true);
    }
    return _State(
      label: 'Tap to connect',
      color: AppColors.textTertiary,
      disconnected: true,
    );
  }

  IconData _batteryIcon(int pct) {
    if (pct > 80) return Icons.battery_full;
    if (pct > 60) return Icons.battery_5_bar;
    if (pct > 40) return Icons.battery_4_bar;
    if (pct > 20) return Icons.battery_2_bar;
    return Icons.battery_1_bar;
  }

  Color _batteryColor(int pct) {
    if (pct > 50) return AppColors.good;
    if (pct > 20) return AppColors.warn;
    return AppColors.danger;
  }
}

class _State {
  final String label;
  final Color color;
  final bool pulse;
  final bool disconnected;

  _State({
    required this.label,
    required this.color,
    this.pulse = false,
    this.disconnected = false,
  });
}

class _Dot extends StatefulWidget {
  final Color color;
  final bool pulse;

  const _Dot({required this.color, required this.pulse});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.5),
            blurRadius: 6,
          ),
        ],
      ),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl),
      child: dot,
    );
  }
}
