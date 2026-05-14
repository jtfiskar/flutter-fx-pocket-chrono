import 'package:flutter_test/flutter_test.dart';
import 'package:chrono_lite/models/chronograph_device.dart';
import 'package:chrono_lite/models/broadcast_data.dart';
import 'package:chrono_lite/providers/app_state.dart';

void main() {
  group('ChronographDevice', () {
    ChronographDevice createDevice({DateTime? lastSeen}) {
      return ChronographDevice(
        remoteId: 'AA:BB:CC:DD:EE:FF',
        name: 'FX Pocket D1',
        deviceType: ChronographDeviceType.pocketD1,
        rssi: -60,
        batteryPercent: 85,
        signalStrength: 80,
        lastSeen: lastSeen ?? DateTime.now(),
      );
    }

    group('isLost', () {
      test('returns false when device was seen less than 3 seconds ago', () {
        final device = createDevice(lastSeen: DateTime.now());
        expect(device.isLost, false);
      });

      test('returns false at exactly 3 seconds', () {
        final device = createDevice(
          lastSeen: DateTime.now().subtract(const Duration(seconds: 3)),
        );
        expect(device.isLost, false);
      });

      test('returns true when device was seen more than 3 seconds ago', () {
        final device = createDevice(
          lastSeen: DateTime.now().subtract(const Duration(seconds: 4)),
        );
        expect(device.isLost, true);
      });

      test('returns true for device seen 10 seconds ago', () {
        final device = createDevice(
          lastSeen: DateTime.now().subtract(const Duration(seconds: 10)),
        );
        expect(device.isLost, true);
      });
    });

    group('signalQuality', () {
      test('returns Excellent for RSSI >= -50', () {
        final device = ChronographDevice(
          remoteId: 'test',
          name: 'test',
          deviceType: ChronographDeviceType.pocketD1,
          rssi: -45,
          batteryPercent: 100,
          lastSeen: DateTime.now(),
        );
        expect(device.signalQuality, 'Excellent');
      });

      test('returns Good for RSSI >= -60', () {
        final device = ChronographDevice(
          remoteId: 'test',
          name: 'test',
          deviceType: ChronographDeviceType.pocketD1,
          rssi: -55,
          batteryPercent: 100,
          lastSeen: DateTime.now(),
        );
        expect(device.signalQuality, 'Good');
      });

      test('returns Fair for RSSI >= -70', () {
        final device = ChronographDevice(
          remoteId: 'test',
          name: 'test',
          deviceType: ChronographDeviceType.pocketD1,
          rssi: -65,
          batteryPercent: 100,
          lastSeen: DateTime.now(),
        );
        expect(device.signalQuality, 'Fair');
      });

      test('returns Weak for RSSI < -70', () {
        final device = ChronographDevice(
          remoteId: 'test',
          name: 'test',
          deviceType: ChronographDeviceType.pocketD1,
          rssi: -80,
          batteryPercent: 100,
          lastSeen: DateTime.now(),
        );
        expect(device.signalQuality, 'Weak');
      });
    });

    group('typeName', () {
      test('returns correct name for V2', () {
        final device = ChronographDevice(
          remoteId: 'test',
          name: 'test',
          deviceType: ChronographDeviceType.pocketV2,
          rssi: -60,
          batteryPercent: 100,
          lastSeen: DateTime.now(),
        );
        expect(device.typeName, 'Pocket V2');
      });

      test('returns correct name for D1', () {
        final device = ChronographDevice(
          remoteId: 'test',
          name: 'test',
          deviceType: ChronographDeviceType.pocketD1,
          rssi: -60,
          batteryPercent: 100,
          lastSeen: DateTime.now(),
        );
        expect(device.typeName, 'Pocket D1');
      });
    });

    group('equality', () {
      test('devices with same remoteId are equal', () {
        final device1 = ChronographDevice(
          remoteId: 'AA:BB:CC:DD:EE:FF',
          name: 'Device 1',
          deviceType: ChronographDeviceType.pocketD1,
          rssi: -60,
          batteryPercent: 80,
          lastSeen: DateTime.now(),
        );
        final device2 = ChronographDevice(
          remoteId: 'AA:BB:CC:DD:EE:FF',
          name: 'Device 2',
          deviceType: ChronographDeviceType.pocketV2,
          rssi: -70,
          batteryPercent: 90,
          lastSeen: DateTime.now(),
        );
        expect(device1, equals(device2));
      });

      test('devices with different remoteId are not equal', () {
        final device1 = createDevice();
        final device2 = ChronographDevice(
          remoteId: '11:22:33:44:55:66',
          name: 'FX Pocket V4',
          deviceType: ChronographDeviceType.pocketD1,
          rssi: -60,
          batteryPercent: 85,
          lastSeen: DateTime.now(),
        );
        expect(device1, isNot(equals(device2)));
      });
    });
  });

  group('AppState device management', () {
    late AppState appState;

    setUp(() {
      appState = AppState();
    });

    tearDown(() {
      appState.dispose();
    });

    BroadcastData createValidBroadcast({
      int shotCounter = 1,
      int velocityFps = 900,
    }) {
      return BroadcastData(
        majorVersion: 1,
        minorVersion: 0,
        uuidVersion: 4,
        batteryPercent: 85,
        velocityFps: velocityFps,
        shotCounter: shotCounter,
        signalStrength: 80,
        isValid: true,
      );
    }

    test('isConnected is false initially', () {
      expect(appState.isConnected, false);
      expect(appState.connectedDevice, isNull);
    });

    test('processBroadcast sets connected device', () {
      appState.processBroadcast(
        'AA:BB:CC:DD:EE:FF',
        'FX Pocket D1',
        -60,
        createValidBroadcast(),
      );

      expect(appState.isConnected, true);
      expect(appState.connectedDevice, isNotNull);
      expect(appState.connectedDevice!.remoteId, 'AA:BB:CC:DD:EE:FF');
    });

    test('processBroadcast updates device info on subsequent calls', () {
      appState.processBroadcast(
        'AA:BB:CC:DD:EE:FF',
        'FX Pocket D1',
        -60,
        BroadcastData(
          majorVersion: 1,
          minorVersion: 0,
          uuidVersion: 4,
          batteryPercent: 80,
          velocityFps: 900,
          shotCounter: 1,
          signalStrength: 70,
          isValid: true,
        ),
      );

      expect(appState.connectedDevice!.batteryPercent, 80);

      appState.processBroadcast(
        'AA:BB:CC:DD:EE:FF',
        'FX Pocket D1',
        -55,
        BroadcastData(
          majorVersion: 1,
          minorVersion: 0,
          uuidVersion: 4,
          batteryPercent: 75,
          velocityFps: 900,
          shotCounter: 1,
          signalStrength: 85,
          isValid: true,
        ),
      );

      expect(appState.connectedDevice!.batteryPercent, 75);
      expect(appState.connectedDevice!.rssi, -55);
    });

    test('processBroadcast ignores invalid broadcast data', () {
      appState.processBroadcast(
        'AA:BB:CC:DD:EE:FF',
        'FX Pocket D1',
        -60,
        BroadcastData.invalid(),
      );

      expect(appState.connectedDevice, isNull);
      expect(appState.isConnected, false);
    });

    test('disconnectDevice clears connected device', () {
      appState.processBroadcast(
        'AA:BB:CC:DD:EE:FF',
        'FX Pocket D1',
        -60,
        createValidBroadcast(),
      );
      expect(appState.isConnected, true);

      appState.disconnectDevice();

      expect(appState.isConnected, false);
      expect(appState.connectedDevice, isNull);
    });

    test('isDeviceLost returns false for recently seen device', () {
      appState.processBroadcast(
        'AA:BB:CC:DD:EE:FF',
        'FX Pocket D1',
        -60,
        createValidBroadcast(),
      );

      expect(appState.isDeviceLost, false);
    });

    test('device loss timer triggers notifyListeners', () async {
      int notifyCount = 0;
      appState.addListener(() => notifyCount++);

      appState.processBroadcast(
        'AA:BB:CC:DD:EE:FF',
        'FX Pocket D1',
        -60,
        createValidBroadcast(),
      );

      final initialCount = notifyCount;

      // Wait for device loss timer (3.5 seconds)
      await Future.delayed(const Duration(milliseconds: 3600));

      // Timer should have fired and called notifyListeners
      expect(notifyCount, greaterThan(initialCount));
    });
  });
}
