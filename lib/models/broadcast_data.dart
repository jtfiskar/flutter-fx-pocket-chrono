/// Parsed BLE broadcast data from Chrono Litegraph devices.
///
/// This data is extracted from BLE advertising packets - no GATT connection needed.
/// Supports both Pocket V2 and Pocket D1 (MkIII) chronographs.
class BroadcastData {
  /// Firmware major version
  final int majorVersion;

  /// Firmware minor version
  final int minorVersion;

  /// UUID version: 2 = Pocket V2, 4 = Pocket D1 (MkIII)
  final int uuidVersion;

  /// Battery percentage (0-100)
  final int batteryPercent;

  /// Velocity in feet per second
  final int velocityFps;

  /// Shot counter - increments with each shot
  final int shotCounter;

  /// Signal strength as percentage (0-100), null if not available
  final int? signalStrength;

  /// Whether the parsed data is valid
  final bool isValid;

  const BroadcastData({
    required this.majorVersion,
    required this.minorVersion,
    required this.uuidVersion,
    required this.batteryPercent,
    required this.velocityFps,
    required this.shotCounter,
    this.signalStrength,
    required this.isValid,
  });

  /// Creates an invalid/empty broadcast data instance
  factory BroadcastData.invalid() {
    return const BroadcastData(
      majorVersion: 0,
      minorVersion: 0,
      uuidVersion: 0,
      batteryPercent: 0,
      velocityFps: 0,
      shotCounter: 0,
      signalStrength: null,
      isValid: false,
    );
  }

  /// Device name based on UUID version
  String get deviceName {
    switch (uuidVersion) {
      case 4:
        return 'FX Pocket D1';
      case 2:
        return 'FX Pocket V2';
      default:
        return 'FX Pocket';
    }
  }

  /// Firmware version string
  String get firmwareVersion => '$majorVersion.$minorVersion';

  @override
  String toString() {
    return 'BroadcastData(v$uuidVersion, $velocityFps fps, shot#$shotCounter, bat:$batteryPercent%, valid:$isValid)';
  }
}
