import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// One velocity reading parsed from a Pocket Pro VRS NOTIFY packet.
///
/// Firmware emits ASCII strings like `"3200.5,1.5,0.013,1"` =
/// `fps,angle,bc,bc_type`. Optional trailing null byte / whitespace is
/// tolerated by the parser. Mirrors the reference client in
/// `~/flutter/FXPocketFlutter/lib/services/pocket_pro_client.dart`.
@immutable
class PocketProVelocity {
  final double velocityFps;
  final double angle;

  /// BC and the firmware's drag-model enum, both PARSED BUT UNUSED —
  /// Chrono Lite only displays velocity/energy. Kept because the packet
  /// carries them and dropping fields at the parse layer makes the next
  /// person re-derive the format.
  ///
  /// If anything ever does consume [bcType]: the firmware enum is
  /// `0 = NONE, 1 = G1, 2 = G7, 3 = RA4, 4 = GA` (`session_sender.c`).
  final double bc;
  final int bcType;

  const PocketProVelocity({
    required this.velocityFps,
    required this.angle,
    required this.bc,
    required this.bcType,
  });

  /// Parse a raw VRS NOTIFY payload. Returns null on malformed input
  /// (never throws — bad packets shouldn't crash the app).
  static PocketProVelocity? tryParse(List<int> bytes) {
    if (bytes.isEmpty) return null;
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0) {
      end--;
    }
    if (end == 0) return null;
    String text;
    try {
      text = utf8.decode(bytes.sublist(0, end));
    } catch (_) {
      return null;
    }
    return tryParseString(text);
  }

  static PocketProVelocity? tryParseString(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(',');
    if (parts.length < 4) return null;
    final fps = double.tryParse(parts[0].trim());
    final angle = double.tryParse(parts[1].trim());
    final bc = double.tryParse(parts[2].trim());
    final type = int.tryParse(parts[3].trim());
    if (fps == null || angle == null || bc == null || type == null) {
      return null;
    }
    // Semantic sanity: `double.tryParse` happily accepts "NaN",
    // "Infinity", "-5" and "0" — a corrupt / partial packet must not
    // reach the shot pipeline as a muzzle velocity. A real chronograph
    // reading is a finite, positive, plausible fps (fastest small-arms
    // projectiles are well under 5000 fps; 10000 is a generous garbage
    // ceiling). Angle / BC must be finite; BC can't be negative.
    if (!fps.isFinite || fps <= 0 || fps > 10000) return null;
    if (!angle.isFinite) return null;
    if (!bc.isFinite || bc < 0) return null;
    return PocketProVelocity(
      velocityFps: fps,
      angle: angle,
      bc: bc,
      bcType: type,
    );
  }
}

/// Owns the GATT connection to a single FX Pocket Pro chronograph and
/// re-emits parsed shot data.
///
/// Pocket Pro is connection-oriented (unlike V2/D1 which broadcast).
class PocketProClient {
  /// Velocity Radar Service UUID — also advertised so the scanner can
  /// recognize the device before connecting.
  static final Guid serviceUuid = Guid('5445883a-3cab-42e5-b625-ca4e243f5a2c');

  /// Velocity NOTIFY characteristic — ASCII "fps,angle,bc,bc_type".
  static final Guid velocityCharUuid = Guid(
    '5445883a-3cab-42e5-b625-ca4e243f5a2d',
  );

  /// Command WRITE characteristic — TIME, FWU, P:tempC/F.
  /// Reserved for future use (time-sync, OTA entry).
  // ignore: unused_field
  static final Guid commandCharUuid = Guid(
    '5445883a-3cab-42e5-b625-ca4e243f5a2e',
  );

  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _velocitySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  bool _connecting = false;

  final StreamController<PocketProVelocity> _velocityController =
      StreamController.broadcast();
  final StreamController<BluetoothConnectionState> _connectionStateController =
      StreamController.broadcast();

  Stream<PocketProVelocity> get velocityStream => _velocityController.stream;
  Stream<BluetoothConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  bool get isConnected => _device != null && _device!.isConnected;

  /// True while [connect] is in flight — the GATT link is being
  /// established but isn't usable yet.
  bool get isConnecting => _connecting;

  String? get remoteId => _device?.remoteId.str;

  /// Connect to the given device, discover the VRS service, and
  /// subscribe to velocity notifications. No-op if already connected
  /// to the same device; releases the previous link first if connected
  /// to a different one.
  Future<void> connect(BluetoothDevice device) async {
    if (_connecting) {
      // Repeat scan results would otherwise spawn overlapping connects
      // that disconnect each other mid-setup.
      return;
    }
    if (_device?.remoteId == device.remoteId && _device!.isConnected) {
      return;
    }
    if (_device != null) {
      await disconnect();
    }
    _device = device;
    _connecting = true;
    try {
      await _doConnect(device);
    } finally {
      _connecting = false;
    }
  }

  Future<void> _doConnect(BluetoothDevice device) async {
    _connectionSub = device.connectionState.listen((state) {
      _connectionStateController.add(state);
    });

    // flutter_blue_plus throws on platforms that don't support GATT
    // (e.g. macOS without entitlements) — let it bubble up, but release
    // the connection-state listener and _device first so a failed
    // attempt doesn't leave a half-tracked handle behind.
    try {
      await device.connect(autoConnect: false);
    } catch (_) {
      await disconnect();
      rethrow;
    }

    // From here on, any failure leaves a half-set-up GATT link. We must
    // release it before rethrowing, otherwise [isConnected] stays true
    // and external retry logic thinks we're already connected.
    try {
      // CoreBluetooth quirk: device.connect() can resolve before
      // CBPeripheral.state has fully transitioned to .connected.
      // Without waiting, discoverServices / setNotifyValue
      // intermittently throw "device is disconnected" right after a
      // tap or auto-reconnect. Wait for the platform-confirmed
      // connected state with a generous timeout.
      if (!device.isConnected) {
        await device.connectionState
            .firstWhere((s) => s == BluetoothConnectionState.connected)
            .timeout(const Duration(seconds: 8));
      }
      final services = await device.discoverServices();
      final vrs = services.firstWhere(
        (s) => s.uuid == serviceUuid,
        orElse: () => throw StateError(
          'Pocket Pro VRS service not found on ${device.remoteId.str}',
        ),
      );
      final velocityChar = vrs.characteristics.firstWhere(
        (c) => c.uuid == velocityCharUuid,
        orElse: () =>
            throw StateError('Pocket Pro velocity characteristic not found'),
      );

      // Install the listener BEFORE enabling notifications — a shot
      // arriving right after the CCCD write would otherwise be lost
      // (onValueReceived doesn't replay missed values). If the enable
      // fails, the enclosing catch tears the subscription down via
      // disconnect().
      _velocitySub = velocityChar.onValueReceived.listen((bytes) {
        final velocity = PocketProVelocity.tryParse(bytes);
        if (velocity != null) {
          _velocityController.add(velocity);
        } else {
          debugPrint('PocketProClient: malformed VRS payload: $bytes');
        }
      });
      await velocityChar.setNotifyValue(true);
    } catch (e) {
      debugPrint(
        'PocketProClient: post-connect setup failed, '
        'releasing GATT link: $e',
      );
      await disconnect();
      rethrow;
    }
  }

  /// Tear down the velocity subscription and disconnect the GATT link.
  /// Safe to call repeatedly; safe to call when not connected.
  Future<void> disconnect() async {
    // Snapshot _connecting before clearing — if the user disconnects
    // during an in-flight connect, we need to bypass FBP's default
    // disconnect queue which would otherwise wait behind the ongoing
    // connect for up to its 35 s timeout.
    final wasConnecting = _connecting;
    _connecting = false;
    await _velocitySub?.cancel();
    _velocitySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect(queue: !wasConnecting);
      } catch (e) {
        debugPrint('PocketProClient: disconnect error (ignored): $e');
      }
    }
  }

  /// Release all resources. Call from the owning widget's `dispose`.
  Future<void> dispose() async {
    await disconnect();
    await _velocityController.close();
    await _connectionStateController.close();
  }
}
