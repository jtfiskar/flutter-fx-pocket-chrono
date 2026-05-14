import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chrono_lite/models/broadcast_data.dart';
import 'package:chrono_lite/providers/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState appState;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appState = AppState();
  });

  tearDown(() {
    appState.dispose();
  });

  BroadcastData createBroadcast({
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

  void sendBroadcast(AppState state, {int shotCounter = 1, int velocityFps = 900}) {
    state.processBroadcast(
      'AA:BB:CC:DD:EE:FF',
      'FX Pocket D1',
      -60,
      createBroadcast(shotCounter: shotCounter, velocityFps: velocityFps),
    );
  }

  group('Shot counter handling', () {
    test('first broadcast syncs counter without recording shot', () async {
      // First broadcast should just sync the counter, not record a shot
      sendBroadcast(appState, shotCounter: 5);

      // Allow async operations to complete
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 0);
    });

    test('counter increment records a shot', () async {
      // Sync counter
      sendBroadcast(appState, shotCounter: 5);
      await Future.delayed(const Duration(milliseconds: 100));

      // Increment counter - should record shot
      sendBroadcast(appState, shotCounter: 6, velocityFps: 895);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1);
      expect(appState.lastVelocityFps, 895);
    });

    test('same counter does not record duplicate shot', () async {
      sendBroadcast(appState, shotCounter: 5);
      await Future.delayed(const Duration(milliseconds: 100));

      sendBroadcast(appState, shotCounter: 6, velocityFps: 895);
      await Future.delayed(const Duration(milliseconds: 100));

      // Same counter value - should NOT record another shot
      sendBroadcast(appState, shotCounter: 6, velocityFps: 900);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1);
      expect(appState.lastVelocityFps, 895); // Original velocity, not 900
    });

    test('counter jump by more than 1 records single shot', () async {
      sendBroadcast(appState, shotCounter: 5);
      await Future.delayed(const Duration(milliseconds: 100));

      // Counter jumps from 5 to 10 (missed 4 broadcasts)
      sendBroadcast(appState, shotCounter: 10, velocityFps: 892);
      await Future.delayed(const Duration(milliseconds: 100));

      // Should record only 1 shot (we only have velocity for current broadcast)
      expect(appState.shotCount, 1);
      expect(appState.lastVelocityFps, 892);
    });

    test('zero velocity does not record shot', () async {
      sendBroadcast(appState, shotCounter: 5);
      await Future.delayed(const Duration(milliseconds: 100));

      // Counter incremented but velocity is 0 - invalid shot
      sendBroadcast(appState, shotCounter: 6, velocityFps: 0);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 0);
    });
  });

  group('Counter wrap handling (16-bit overflow)', () {
    test('counter wrap from 65535 to 0 records a shot', () async {
      // Start at high counter value (>= 65000)
      sendBroadcast(appState, shotCounter: 65535);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 0);

      // Counter wraps to 0 - should be detected as a shot
      sendBroadcast(appState, shotCounter: 0, velocityFps: 888);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1);
      expect(appState.lastVelocityFps, 888);
    });

    test('counter wrap from 65000 to 5 records a shot', () async {
      // Must be >= 65000 to trigger wrap detection
      sendBroadcast(appState, shotCounter: 65000);
      await Future.delayed(const Duration(milliseconds: 100));

      // Counter wraps (new counter < 1000)
      sendBroadcast(appState, shotCounter: 5, velocityFps: 901);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1);
    });

    test('counter wrap near boundary (65100 to 2) records a shot', () async {
      // Previous counter >= 65000
      sendBroadcast(appState, shotCounter: 65100);
      await Future.delayed(const Duration(milliseconds: 100));

      // New counter < 1000
      sendBroadcast(appState, shotCounter: 2, velocityFps: 905);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1);
    });

    test('large counter drop is treated as reset not wrap', () async {
      // Counter at 50000 (not near 65535)
      sendBroadcast(appState, shotCounter: 50000);
      await Future.delayed(const Duration(milliseconds: 100));

      sendBroadcast(appState, shotCounter: 50001, velocityFps: 890);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1);

      // Device reboots, counter drops to 0 - NOT a wrap (50000 < 65000)
      sendBroadcast(appState, shotCounter: 0, velocityFps: 895);
      await Future.delayed(const Duration(milliseconds: 100));

      // Should NOT record a ghost shot
      expect(appState.shotCount, 1);
    });

    test('new counter >= 1000 after high counter is treated as reset', () async {
      // Counter at 65500 (near max)
      sendBroadcast(appState, shotCounter: 65500);
      await Future.delayed(const Duration(milliseconds: 100));

      // Counter drops to 1500 (>= 1000) - treated as reset not wrap
      sendBroadcast(appState, shotCounter: 1500, velocityFps: 890);
      await Future.delayed(const Duration(milliseconds: 100));

      // Should NOT record a shot
      expect(appState.shotCount, 0);
    });
  });

  group('Counter reset handling (device reboot)', () {
    test('small counter decrease does not record shot', () async {
      // Start at counter 100
      sendBroadcast(appState, shotCounter: 100);
      await Future.delayed(const Duration(milliseconds: 100));

      sendBroadcast(appState, shotCounter: 101, velocityFps: 890);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1);

      // Device reboots, counter resets to 1 (delta = 1 - 101 = -100)
      // This is in [-32768, 0] range, so it's a reset not a wrap
      sendBroadcast(appState, shotCounter: 1, velocityFps: 895);
      await Future.delayed(const Duration(milliseconds: 100));

      // Should NOT record a shot - just sync counter
      expect(appState.shotCount, 1);

      // Next increment should work normally
      sendBroadcast(appState, shotCounter: 2, velocityFps: 892);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 2);
    });

    test('counter going from 50 to 10 does not record shot', () async {
      sendBroadcast(appState, shotCounter: 50);
      await Future.delayed(const Duration(milliseconds: 100));

      // Counter decreased (device reset)
      sendBroadcast(appState, shotCounter: 10, velocityFps: 900);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 0);
    });
  });

  group('Device change and loss handling', () {
    test('device change resets counter sync', () async {
      // First device
      appState.processBroadcast(
        'AA:BB:CC:DD:EE:FF',
        'Device 1',
        -60,
        createBroadcast(shotCounter: 100),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      appState.processBroadcast(
        'AA:BB:CC:DD:EE:FF',
        'Device 1',
        -60,
        createBroadcast(shotCounter: 101, velocityFps: 890),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1);

      // Different device with lower counter - should NOT record shot
      // because counter sync is reset on device change
      appState.processBroadcast(
        '11:22:33:44:55:66', // Different device ID
        'Device 2',
        -60,
        createBroadcast(shotCounter: 5, velocityFps: 900),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1); // No new shot recorded

      // Next increment on new device should work
      appState.processBroadcast(
        '11:22:33:44:55:66',
        'Device 2',
        -60,
        createBroadcast(shotCounter: 6, velocityFps: 895),
      );
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 2);
    });

    test('device loss resets counter sync on reconnection', () async {
      sendBroadcast(appState, shotCounter: 10);
      await Future.delayed(const Duration(milliseconds: 100));

      sendBroadcast(appState, shotCounter: 11, velocityFps: 890);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1);

      // Simulate device loss (wait for 3+ seconds)
      await Future.delayed(const Duration(milliseconds: 3100));

      expect(appState.isDeviceLost, true);

      // Device reconnects with different counter - should NOT record shot
      sendBroadcast(appState, shotCounter: 50, velocityFps: 900);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 1); // No new shot

      // Next increment should work
      sendBroadcast(appState, shotCounter: 51, velocityFps: 892);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.shotCount, 2);
    });
  });

  group('Multiple shots in sequence', () {
    test('records multiple shots correctly', () async {
      // Start session first to avoid auto-start timing issues
      await appState.startNewSession();
      await Future.delayed(const Duration(milliseconds: 100));

      sendBroadcast(appState, shotCounter: 0);
      // Wait for initial sync
      await Future.delayed(const Duration(milliseconds: 200));

      for (int i = 1; i <= 5; i++) {
        sendBroadcast(appState, shotCounter: i, velocityFps: 880 + i * 5);
        // Wait for async persistence to complete fully before next shot
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Extra wait for final save to complete
      await Future.delayed(const Duration(milliseconds: 200));

      expect(appState.shotCount, 5);
      expect(appState.hasStatistics, true);
      expect(appState.lastVelocityFps, 905); // 880 + 5*5
    });
  });

  group('Session auto-start', () {
    test('shot without session auto-starts session', () async {
      expect(appState.hasActiveSession, false);

      sendBroadcast(appState, shotCounter: 0);
      await Future.delayed(const Duration(milliseconds: 100));

      sendBroadcast(appState, shotCounter: 1, velocityFps: 900);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(appState.hasActiveSession, true);
      expect(appState.shotCount, 1);
    });
  });
}
