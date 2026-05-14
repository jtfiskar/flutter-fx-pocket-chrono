import 'package:flutter_test/flutter_test.dart';
import 'package:chrono_lite/services/broadcast_parser.dart';

void main() {
  group('BroadcastParser', () {
    group('parse', () {
      test('returns invalid for empty data', () {
        final result = BroadcastParser.parse([]);
        expect(result.isValid, false);
      });

      test('returns invalid for data shorter than minimum length', () {
        final result = BroadcastParser.parse([0x30, 0x0E, 0x01, 0x00]);
        expect(result.isValid, false);
      });

      test('returns invalid for wrong device type', () {
        // Device type 0x20 instead of 0x30
        final data = [
          0x20, // Wrong device type
          0x0E, // Data length
          0x01, 0x00, // Major version
          0x02, 0x00, // Minor version
          0x57, 0x65, 0xFD, 0xCE, // UUID V2
          0x55, // Battery 85%
          0x00, 0x05, // Shot counter
          0x03, 0x7C, // FPS = 892
        ];
        final result = BroadcastParser.parse(data);
        expect(result.isValid, false);
      });

      test('returns invalid for unrecognized UUID', () {
        final data = [
          0x30, // Device type
          0x0E, // Data length
          0x01, 0x00, // Major version
          0x02, 0x00, // Minor version
          0x00, 0x00, 0x00, 0x00, // Unknown UUID
          0x55, // Battery 85%
          0x00, 0x05, // Shot counter
          0x03, 0x7C, // FPS = 892
        ];
        final result = BroadcastParser.parse(data);
        expect(result.isValid, false);
      });

      test('parses valid V2 device data correctly', () {
        final data = [
          0x30, // Device type (Pocket Chrono)
          0x0E, // Data length
          0x01, 0x00, // Major version = 1
          0x0C, 0x00, // Minor version = 12 (low byte)
          0x57, 0x65, 0xFD, 0xCE, // UUID V2
          0x55, // Battery 85%
          0x00, 0x05, // Shot counter = 5
          0x03, 0x7C, // FPS = 892 (0x037C)
        ];

        final result = BroadcastParser.parse(data);

        expect(result.isValid, true);
        expect(result.uuidVersion, 2);
        expect(result.majorVersion, 1);
        expect(result.minorVersion, 12);
        expect(result.batteryPercent, 85);
        expect(result.shotCounter, 5);
        expect(result.velocityFps, 892);
        expect(result.signalStrength, null);
      });

      test('parses valid D1 device data correctly', () {
        final data = [
          0x30, // Device type (Pocket Chrono)
          0x0E, // Data length
          0x02, 0x00, // Major version = 2
          0x05, 0x00, // Minor version = 5
          0x57, 0x65, 0xFD, 0xCD, // UUID D1
          0x64, // Battery 100%
          0x00, 0x0A, // Shot counter = 10
          0x03, 0x20, // FPS = 800 (0x0320)
        ];

        final result = BroadcastParser.parse(data);

        expect(result.isValid, true);
        expect(result.uuidVersion, 4);
        expect(result.majorVersion, 2);
        expect(result.minorVersion, 5);
        expect(result.batteryPercent, 100);
        expect(result.shotCounter, 10);
        expect(result.velocityFps, 800);
      });

      test('parses optional signal strength when present', () {
        final data = [
          0x30, // Device type
          0x0F, // Data length (includes signal)
          0x01, 0x00, // Major version
          0x00, 0x00, // Minor version
          0x57, 0x65, 0xFD, 0xCE, // UUID V2
          0x50, // Battery 80%
          0x00, 0x01, // Shot counter = 1
          0x03, 0xE8, // FPS = 1000
          0x14, // Signal strength raw = 20
        ];

        final result = BroadcastParser.parse(data);

        expect(result.isValid, true);
        expect(result.signalStrength, isNotNull);
        // Signal calculation: ((20-4)/16)*100 = 100 (clamped)
        expect(result.signalStrength, 100);
      });

      test('clamps signal strength to 0-100 range', () {
        // Test low signal (raw value 4 = 0%)
        final dataLow = [
          0x30, 0x0F, 0x01, 0x00, 0x00, 0x00,
          0x57, 0x65, 0xFD, 0xCE,
          0x50, 0x00, 0x01, 0x03, 0xE8,
          0x04, // Signal raw = 4 -> 0%
        ];
        final resultLow = BroadcastParser.parse(dataLow);
        expect(resultLow.signalStrength, 0);

        // Test high signal (raw value 24 = 125% -> clamped to 100)
        final dataHigh = [
          0x30, 0x0F, 0x01, 0x00, 0x00, 0x00,
          0x57, 0x65, 0xFD, 0xCE,
          0x50, 0x00, 0x01, 0x03, 0xE8,
          0x18, // Signal raw = 24 -> 125% -> 100%
        ];
        final resultHigh = BroadcastParser.parse(dataHigh);
        expect(resultHigh.signalStrength, 100);
      });

      test('handles big-endian shot counter correctly', () {
        final data = [
          0x30, 0x0E, 0x01, 0x00, 0x00, 0x00,
          0x57, 0x65, 0xFD, 0xCE,
          0x50,
          0x01, 0x00, // Shot counter = 256 (big-endian: 0x0100)
          0x03, 0xE8,
        ];

        final result = BroadcastParser.parse(data);
        expect(result.shotCounter, 256);
      });

      test('handles big-endian FPS correctly', () {
        final data = [
          0x30, 0x0E, 0x01, 0x00, 0x00, 0x00,
          0x57, 0x65, 0xFD, 0xCE,
          0x50, 0x00, 0x01,
          0x04, 0x00, // FPS = 1024 (big-endian: 0x0400)
        ];

        final result = BroadcastParser.parse(data);
        expect(result.velocityFps, 1024);
      });

      test('handles little-endian major version correctly', () {
        final data = [
          0x30, 0x0E,
          0x0A, 0x01, // Major version = 266 (little-endian: 0x010A)
          0x00, 0x00,
          0x57, 0x65, 0xFD, 0xCE,
          0x50, 0x00, 0x01, 0x03, 0xE8,
        ];

        final result = BroadcastParser.parse(data);
        expect(result.majorVersion, 266);
      });
    });

    group('isNordicManufacturer', () {
      test('returns true for Nordic company ID 0x0059', () {
        expect(BroadcastParser.isNordicManufacturer(0x0059), true);
      });

      test('returns false for other company IDs', () {
        expect(BroadcastParser.isNordicManufacturer(0x0000), false);
        expect(BroadcastParser.isNordicManufacturer(0x004C), false); // Apple
        expect(BroadcastParser.isNordicManufacturer(0x0006), false); // Microsoft
      });
    });

    group('isPocketDevice', () {
      test('returns true when first byte is 0x30', () {
        expect(BroadcastParser.isPocketDevice([0x30, 0x00]), true);
      });

      test('returns false when first byte is not 0x30', () {
        expect(BroadcastParser.isPocketDevice([0x00, 0x30]), false);
        expect(BroadcastParser.isPocketDevice([0x20, 0x00]), false);
      });

      test('returns false for empty data', () {
        expect(BroadcastParser.isPocketDevice([]), false);
      });
    });
  });
}
