import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chrono_lite/models/chronograph_device.dart';
import 'package:chrono_lite/providers/app_state.dart';
import 'package:chrono_lite/services/session_storage.dart';

/// Covers the GATT (Pocket Pro / True Ballistic) shot pipeline, which
/// differs from the broadcast path: one notify equals one shot, shots
/// persist on a serial chain, and each carries the session and arrival
/// time captured when its notification landed.
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

  void sendGattShot(
    AppState state, {
    int fps = 900,
    String remoteId = 'AA:BB:CC:DD:EE:FF',
    ChronographDeviceType kind = ChronographDeviceType.pocketPro,
  }) {
    state.processGattVelocity(
      remoteId: remoteId,
      name: 'FX Pocket Pro',
      fps: fps,
      deviceType: kind,
    );
  }

  group('GATT shot recording', () {
    test('a notify records exactly one shot', () async {
      await appState.startNewSession();
      sendGattShot(appState, fps: 900);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(appState.shotCount, 1);
      expect(appState.lastVelocityFps, 900);
    });

    test('rapid notifies are all persisted, none dropped', () async {
      await appState.startNewSession();
      for (var i = 0; i < 5; i++) {
        sendGattShot(appState, fps: 900 + i);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(appState.shotCount, 5);
      expect(
        appState.currentSession!.shots.map((s) => s.velocityFps),
        [900, 901, 902, 903, 904],
      );
    });

    test('zero or negative velocity is ignored', () async {
      await appState.startNewSession();
      sendGattShot(appState, fps: 0);
      sendGattShot(appState, fps: -5);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(appState.shotCount, 0);
    });

    test('shot timestamp reflects arrival, not persistence delay', () async {
      await appState.startNewSession();
      final before = DateTime.now();
      // Queue several shots at once so the later ones wait behind the
      // earlier SharedPreferences writes on the persistence chain.
      for (var i = 0; i < 4; i++) {
        sendGattShot(appState, fps: 900 + i);
      }
      final afterArrival = DateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(appState.shotCount, 4);
      for (final shot in appState.currentSession!.shots) {
        // Every shot must be stamped inside the arrival window, not
        // after it. Persistence necessarily finishes later than
        // `afterArrival`, so a persist-time stamp lands outside — no
        // tolerance is allowed here or the assertion loses its teeth.
        expect(
          shot.timestamp.isBefore(before),
          isFalse,
          reason: 'timestamp precedes the arrival window',
        );
        expect(
          shot.timestamp.isAfter(afterArrival),
          isFalse,
          reason: 'timestamp reflects persistence delay, not shot time',
        );
      }
    });

    test('a queued shot lands in the session it arrived under', () async {
      await appState.startNewSession();
      final firstSessionId = appState.currentSession!.id;

      // The 2 ms gap keeps the two session ids distinct — they're
      // derived from millisecondsSinceEpoch, which a test can collide
      // but a tapping user cannot.
      await Future<void>.delayed(const Duration(milliseconds: 2));

      sendGattShot(appState, fps: 900);
      // No await between the shot and the switch: the shot's storage
      // write is still queued on the persistence chain when the session
      // swaps, which is the case that used to misfile it.
      final switching = appState.startNewSession();
      final secondSessionId = appState.currentSession!.id;
      expect(secondSessionId, isNot(firstSessionId));
      await switching;

      await Future<void>.delayed(const Duration(milliseconds: 200));

      // The shot belongs to the session that was current when it fired.
      final firstSession = await SessionStorage.getSession(firstSessionId);
      expect(firstSession, isNotNull);
      expect(firstSession!.shots.length, 1);
      expect(firstSession.shots.first.velocityFps, 900);
      // ...and must not have leaked into the new one.
      expect(appState.currentSession!.shots, isEmpty);
    });

    test('consecutive queued shots stack in their arrival session',
        () async {
      await appState.startNewSession();
      final firstSessionId = appState.currentSession!.id;

      await Future<void>.delayed(const Duration(milliseconds: 2));
      sendGattShot(appState, fps: 900);
      sendGattShot(appState, fps: 901);
      sendGattShot(appState, fps: 902);
      // Switch with all three still queued (see the test above).
      await appState.startNewSession();

      await Future<void>.delayed(const Duration(milliseconds: 250));

      final firstSession = await SessionStorage.getSession(firstSessionId);
      expect(firstSession, isNotNull);
      // All three stack — a later shot must not overwrite an earlier
      // one by re-appending to a stale snapshot.
      expect(
        firstSession!.shots.map((s) => s.velocityFps),
        [900, 901, 902],
      );
      expect(appState.currentSession!.shots, isEmpty);
    });
  });

  group('GATT connection state', () {
    test('isConnected follows the link, not the lastSeen clock', () {
      appState.setGattConnected(
        true,
        remoteId: 'AA:BB:CC:DD:EE:FF',
        name: 'FX True Ballistic',
        deviceType: ChronographDeviceType.trueBallistic,
      );
      expect(appState.isConnected, isTrue);
      expect(appState.isDeviceLost, isFalse);
      expect(appState.connectedDevice!.deviceType,
          ChronographDeviceType.trueBallistic);

      // Dropping the link is authoritative immediately — no waiting for
      // the 3 s broadcast staleness window.
      appState.setGattConnected(false);
      expect(appState.isConnected, isFalse);
      expect(appState.isDeviceLost, isTrue);
    });

    test('reconnecting the same device clears the stale lost state', () {
      appState.setGattConnected(
        true,
        remoteId: 'AA:BB:CC:DD:EE:FF',
        name: 'FX Pocket Pro',
      );
      appState.setGattConnected(false);
      expect(appState.isDeviceLost, isTrue);

      appState.setGattConnected(
        true,
        remoteId: 'AA:BB:CC:DD:EE:FF',
        name: 'FX Pocket Pro',
      );
      expect(appState.isConnected, isTrue);
      expect(appState.connectedDevice!.isLost, isFalse);
    });

    test('True Ballistic telemetry reaches the device card', () {
      appState.setGattConnected(
        true,
        remoteId: 'AA:BB:CC:DD:EE:FF',
        name: 'FX True Ballistic',
        deviceType: ChronographDeviceType.trueBallistic,
      );
      appState.updateGattDeviceInfo(batteryPercent: 76, firmwareVersion: '1.4');

      expect(appState.connectedDevice!.batteryPercent, 76);
      expect(appState.connectedDevice!.firmwareVersion, '1.4');
    });
  });
}
