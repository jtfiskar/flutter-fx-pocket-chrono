import '../models/broadcast_data.dart';

/// Parses BLE advertising packets from Chrono Litegraph devices.
///
/// Ported from Android BroadcastDataParser.java.
/// These devices broadcast velocity data continuously without requiring
/// a GATT connection.
class BroadcastParser {
  // Nordic Semiconductor company ID (little-endian: 0x59 0x00)
  static const int _companyNordic = 0x0059;

  // Device type identifier for Pocket V2/D1
  static const int _devicePocketChrono = 0x30;

  // UUID bytes for Pocket V2: 57 65 FD CE
  static const List<int> _uuidV2 = [0x57, 0x65, 0xFD, 0xCE];

  // UUID bytes for Pocket D1: 57 65 FD CD
  static const List<int> _uuidD1 = [0x57, 0x65, 0xFD, 0xCD];

  /// Parse manufacturer data from a BLE scan result.
  ///
  /// The [manufacturerData] is the raw bytes from the manufacturer-specific
  /// data field in the BLE advertisement packet.
  ///
  /// Returns [BroadcastData] with isValid=true if parsing succeeded,
  /// or isValid=false if the data is not from a supported device.
  static BroadcastData parse(List<int> manufacturerData) {
    // Minimum expected length (without optional signal strength)
    // We read up to index 14 (FPS low byte), so need at least 15 bytes
    const minLength = 15;

    if (manufacturerData.length < minLength) {
      return BroadcastData.invalid();
    }

    try {
      // Data structure (after company ID which is handled by flutter_blue_plus):
      // Offset 0: Device type (0x30 for Pocket)
      // Offset 1: Data length
      // Offset 2-3: Major version
      // Offset 4-5: Minor version (only low byte used)
      // Offset 6-9: UUID (4 bytes for V2/V4 detection)
      // Offset 10: Battery %
      // Offset 11-12: Shot counter (big-endian)
      // Offset 13-14: FPS (big-endian)
      // Offset 15: Signal strength (optional)

      int index = 0;

      // Check device type
      final deviceType = manufacturerData[index];
      index += 1;
      if (deviceType != _devicePocketChrono) {
        return BroadcastData.invalid();
      }

      // Data length (skip)
      index += 1;

      // Major version (2 bytes, little-endian)
      final major = _decodeWord(manufacturerData, index);
      index += 2;

      // Minor version (2 bytes little-endian, only use low byte at current index)
      final minor = manufacturerData[index] & 0xFF;
      index += 2; // skip both bytes of minor version

      // UUID check (4 bytes)
      final uuid1 = manufacturerData[index] & 0xFF;
      index += 1;
      final uuid2 = manufacturerData[index] & 0xFF;
      index += 1;
      final uuid3 = manufacturerData[index] & 0xFF;
      index += 1;
      final uuid4 = manufacturerData[index] & 0xFF;
      index += 1;

      // Determine device version from UUID
      int uuidVersion = 0;
      if (_checkUuidV2(uuid1, uuid2, uuid3, uuid4)) {
        uuidVersion = 2;
      } else if (_checkUuidD1(uuid1, uuid2, uuid3, uuid4)) {
        uuidVersion = 4;
      } else {
        // Not a recognized device
        return BroadcastData.invalid();
      }

      // Battery percentage
      final battery = manufacturerData[index] & 0xFF;
      index += 1;

      // Shot counter (big-endian)
      final shotCounterHigh = manufacturerData[index] & 0xFF;
      index += 1;
      final shotCounterLow = manufacturerData[index] & 0xFF;
      index += 1;
      final shotCounter = (shotCounterHigh << 8) | shotCounterLow;

      // FPS (big-endian)
      final fpsHigh = manufacturerData[index] & 0xFF;
      index += 1;
      final fpsLow = manufacturerData[index] & 0xFF;
      index += 1;
      final fps = (fpsHigh << 8) | fpsLow;

      // Signal strength (optional)
      int? signalStrength;
      if (manufacturerData.length > index) {
        final rawSignal = manufacturerData[index] & 0xFF;
        // Convert to percentage: (value - 4) / 16 * 100, clamped to 0-100
        double percentage = ((rawSignal - 4) / 16.0) * 100.0;
        if (percentage > 100) percentage = 100;
        if (percentage < 0) percentage = 0;
        signalStrength = percentage.toInt();
      }

      return BroadcastData(
        majorVersion: major,
        minorVersion: minor,
        uuidVersion: uuidVersion,
        batteryPercent: battery,
        velocityFps: fps,
        shotCounter: shotCounter,
        signalStrength: signalStrength,
        isValid: true,
      );
    } catch (e) {
      // Any parsing error returns invalid data
      return BroadcastData.invalid();
    }
  }

  /// Check if manufacturer data is from a Nordic device.
  /// Use this for quick filtering before full parsing.
  static bool isNordicManufacturer(int companyId) {
    return companyId == _companyNordic;
  }

  /// Check if data is likely from a Pocket chronograph (quick check).
  static bool isPocketDevice(List<int> manufacturerData) {
    if (manufacturerData.isEmpty) return false;
    return manufacturerData[0] == _devicePocketChrono;
  }

  // Check UUID matches V2
  static bool _checkUuidV2(int u1, int u2, int u3, int u4) {
    return u1 == _uuidV2[0] &&
        u2 == _uuidV2[1] &&
        u3 == _uuidV2[2] &&
        u4 == _uuidV2[3];
  }

  // Check UUID matches D1
  static bool _checkUuidD1(int u1, int u2, int u3, int u4) {
    return u1 == _uuidD1[0] &&
        u2 == _uuidD1[1] &&
        u3 == _uuidD1[2] &&
        u4 == _uuidD1[3];
  }

  // Decode 2 bytes as little-endian word
  static int _decodeWord(List<int> data, int start) {
    return ((data[start + 1] & 0xFF) << 8) | (data[start] & 0xFF);
  }
}
