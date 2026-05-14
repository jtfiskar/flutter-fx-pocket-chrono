import 'package:flutter/material.dart';
import '../models/chronograph_device.dart';
import '../theme/app_theme.dart';

/// Device status bar showing connection state, device name, and battery.
///
/// Tap to open device scanner or show device info.
class DeviceStatusBar extends StatelessWidget {
  /// Connected device (null if not connected)
  final ChronographDevice? device;

  /// Whether currently scanning for devices
  final bool isScanning;

  /// Whether attempting to reconnect to a lost device
  final bool isReconnecting;

  /// Whether reconnection attempt has timed out
  final bool isTimedOut;

  /// Callback when tapped
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
    final isConnected = device != null && !device!.isLost;
    final isLost = device != null && device!.isLost;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            bottom: BorderSide(color: AppColors.border),
          ),
        ),
        child: Row(
          children: [
            // Connection indicator
            _ConnectionIndicator(
              isConnected: isConnected,
              isLost: isLost,
              isScanning: isScanning,
              isReconnecting: isReconnecting,
              isTimedOut: isTimedOut,
            ),
            const SizedBox(width: 12),

            // Device name or status text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getTitle(isConnected, isLost, isScanning, isReconnecting, isTimedOut),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (isConnected && device != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      device!.typeName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Battery indicator (if connected)
            if (isConnected && device != null) ...[
              _BatteryIndicator(percentage: device!.batteryPercent),
              const SizedBox(width: 12),
            ],

            // Chevron
            Icon(
              Icons.chevron_right,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  String _getTitle(bool isConnected, bool isLost, bool isScanning, bool isReconnecting, bool isTimedOut) {
    if (isLost && isTimedOut) return 'Connection lost';
    if (isLost && isReconnecting) return 'Reconnecting...';
    if (isScanning) return 'Scanning...';
    if (isLost) return 'Device Lost';
    if (isConnected && device != null) return device!.name;
    return 'Tap to connect';
  }
}

class _ConnectionIndicator extends StatefulWidget {
  final bool isConnected;
  final bool isLost;
  final bool isScanning;
  final bool isReconnecting;
  final bool isTimedOut;

  const _ConnectionIndicator({
    required this.isConnected,
    required this.isLost,
    required this.isScanning,
    required this.isReconnecting,
    required this.isTimedOut,
  });

  @override
  State<_ConnectionIndicator> createState() => _ConnectionIndicatorState();
}

class _ConnectionIndicatorState extends State<_ConnectionIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // Start animation if already reconnecting on initial build (not timed out)
    if (widget.isReconnecting && widget.isLost && !widget.isTimedOut) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_ConnectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isReconnecting && widget.isLost && !widget.isTimedOut) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    if (widget.isLost && widget.isTimedOut) {
      // Timed out - show error state
      color = AppColors.error;
      icon = Icons.bluetooth_disabled;
    } else if (widget.isLost && widget.isReconnecting) {
      // Reconnecting - show warning state with animation
      color = AppColors.warning;
      icon = Icons.bluetooth_searching;
    } else if (widget.isScanning) {
      color = AppColors.warning;
      icon = Icons.bluetooth_searching;
    } else if (widget.isLost) {
      color = AppColors.error;
      icon = Icons.bluetooth_disabled;
    } else if (widget.isConnected) {
      color = AppColors.success;
      icon = Icons.bluetooth_connected;
    } else {
      color = AppColors.textTertiary;
      icon = Icons.bluetooth;
    }

    final indicator = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 20,
        color: color,
      ),
    );

    // Animate when reconnecting (not timed out)
    if (widget.isLost && widget.isReconnecting && !widget.isTimedOut) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) => Opacity(
          opacity: _pulseAnimation.value,
          child: child,
        ),
        child: indicator,
      );
    }

    return indicator;
  }
}

class _BatteryIndicator extends StatelessWidget {
  final int percentage;

  const _BatteryIndicator({required this.percentage});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (percentage > 50) {
      color = AppColors.success;
    } else if (percentage > 20) {
      color = AppColors.warning;
    } else {
      color = AppColors.error;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _getBatteryIcon(),
          size: 20,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '$percentage%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  IconData _getBatteryIcon() {
    if (percentage > 80) return Icons.battery_full;
    if (percentage > 60) return Icons.battery_5_bar;
    if (percentage > 40) return Icons.battery_4_bar;
    if (percentage > 20) return Icons.battery_2_bar;
    return Icons.battery_1_bar;
  }
}
