/// Device type enumeration for supported chronographs
enum ChronographDeviceType {
  /// Chrono Litegraph V2
  pocketV2,

  /// Chrono Litegraph D1 (MkIII)
  pocketD1,

  /// FX Pocket Pro (GATT-connected, VRS service)
  pocketPro,

  /// FX True Ballistic Chronograph (GATT-connected, doppler radar)
  trueBallistic,
}

/// Whether this device type publishes its data via BLE advertisements
/// (true) or requires a GATT connection (false).
extension ChronographDeviceTypeTransport on ChronographDeviceType {
  bool get isBroadcast {
    switch (this) {
      case ChronographDeviceType.pocketV2:
      case ChronographDeviceType.pocketD1:
        return true;
      case ChronographDeviceType.pocketPro:
      case ChronographDeviceType.trueBallistic:
        return false;
    }
  }
}

/// Represents a connected or detected chronograph device.
class ChronographDevice {
  /// Bluetooth remote ID
  final String remoteId;

  /// Device name from advertisement or derived from type
  final String name;

  /// Type of chronograph device
  final ChronographDeviceType deviceType;

  /// RSSI signal strength in dBm
  final int rssi;

  /// Battery percentage (0-100)
  final int batteryPercent;

  /// Signal strength percentage (0-100), null if not available
  final int? signalStrength;

  /// Firmware version string ("major.minor") parsed from the broadcast,
  /// null until the first valid packet is processed.
  final String? firmwareVersion;

  /// Last time device was seen (scan result received)
  final DateTime lastSeen;

  const ChronographDevice({
    required this.remoteId,
    required this.name,
    required this.deviceType,
    required this.rssi,
    required this.batteryPercent,
    this.signalStrength,
    this.firmwareVersion,
    required this.lastSeen,
  });

  /// Whether device is considered "lost" (no scan for 3+ seconds)
  /// Uses milliseconds comparison to avoid truncation issues with inSeconds
  bool get isLost {
    return DateTime.now().difference(lastSeen).inMilliseconds > 3000;
  }

  /// Human-readable device type name
  String get typeName {
    switch (deviceType) {
      case ChronographDeviceType.pocketV2:
        return 'Pocket V2';
      case ChronographDeviceType.pocketD1:
        return 'Pocket D1';
      case ChronographDeviceType.pocketPro:
        return 'Pocket Pro';
      case ChronographDeviceType.trueBallistic:
        return 'True Ballistic';
    }
  }

  /// Signal quality description based on RSSI
  String get signalQuality {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Good';
    if (rssi >= -70) return 'Fair';
    return 'Weak';
  }

  /// Create updated device with new data
  ChronographDevice update({
    int? rssi,
    int? batteryPercent,
    int? signalStrength,
    String? firmwareVersion,
    DateTime? lastSeen,
  }) {
    return ChronographDevice(
      remoteId: remoteId,
      name: name,
      deviceType: deviceType,
      rssi: rssi ?? this.rssi,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      signalStrength: signalStrength ?? this.signalStrength,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  String toString() {
    return 'ChronographDevice($name, $typeName, bat:$batteryPercent%, rssi:$rssi)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChronographDevice && other.remoteId == remoteId;
  }

  @override
  int get hashCode => remoteId.hashCode;
}
