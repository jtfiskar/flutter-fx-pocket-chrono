/// Parser and GATT client for the FX True Ballistic Chronograph.
///
/// The device is a 24.08 GHz doppler radar. Unlike the Pocket Chronograph —
/// which broadcasts shots in its advertisement and needs no connection — the
/// True Ballistic is a connected GATT device that pushes one notification per
/// shot on [TrueBallisticUuids.notify].
///
/// Chrono Lite wants **muzzle velocity only**. The device also reports a
/// measured BC (packet 0x0B) and a polynomial drag model (0x0C); those fields
/// are parsed past and discarded. Mirrors the reference client in
/// `~/flutter/BallisticSolver/lib/services/true_ballistic_parser.dart` and
/// `true_ballistic_ble_service.dart`.
///
/// Format verified against BOTH sibling implementations, which agree exactly:
///   - ChronoAndroid  `scanner/FirearmParser.java`
///   - ChronoIOS      `Scanner/FirearmDataParser.swift`
/// Do not "fix" the constants from first principles without re-reading those —
/// the 10525/24080 pair below looks wrong and is not.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// GATT identifiers for the True Ballistic chronograph.
class TrueBallisticUuids {
  /// Advertised-name prefix. The device does not advertise its data service,
  /// so the scan has to match on name (mirrors `isFirearmDevice` in
  /// ChronoAndroid's `ExtendedBluetoothDevice`). Obfuscated by the vendor —
  /// this string is a device fingerprint, not a typo.
  static const String namePrefix = 'vXfS3c6k';

  static const String service = '00001623-88ec-688c-644b-3fa706c0bb76';

  /// Shot notifications — one per shot.
  static const String notify = '00001624-88ec-688c-644b-3fa706c0bb76';

  /// Command channel (write). Unused: we only listen.
  static const String command = '00001625-88ec-688c-644b-3fa706c0bb76';

  /// Raw doppler stream. Unused — far too chatty for a chronograph app.
  static const String stream = '00001626-88ec-688c-644b-3fa706c0bb76';

  /// Battery level (read).
  static const String battery = '00001627-88ec-688c-644b-3fa706c0bb76';
}

/// One shot as reported by the chronograph.
class TrueBallisticShot {
  /// Muzzle velocity in m/s (the doppler maths is SI).
  final double velocityMs;

  /// Doppler frequency after the vendor's 10.525 GHz rescale, kept for
  /// diagnostics — this is the number the FX apps display as "Hz".
  final int hertz;

  /// Packet discriminator: 0x0A simple, 0x0B ballistic, 0x0C polynomial.
  final int packetType;

  const TrueBallisticShot({
    required this.velocityMs,
    required this.hertz,
    required this.packetType,
  });

  /// Muzzle velocity in fps — Chrono Lite's shot pipeline is fps-based.
  double get velocityFps => velocityMs / 0.3048;

  @override
  String toString() =>
      'TrueBallisticShot(${velocityMs.toStringAsFixed(1)} m/s, '
      '$hertz Hz, type 0x${packetType.toRadixString(16).toUpperCase()})';
}

class TrueBallisticParser {
  /// Simple shot: velocity only (plus a downrange vel/dist pair we ignore).
  /// The reference implementations require exactly 20 bytes for this type.
  static const int typeSimple = 0x0A;

  /// Ballistic: velocity + measured BC + drag model. BC/model discarded.
  static const int typeBallistic = 0x0B;

  /// Polynomial: velocity + three drag coefficients. Coefficients discarded.
  static const int typePolynomial = 0x0C;

  /// Speed of light used by the sibling apps (exact SI value).
  static const double _c = 299792458.0;

  /// The radar's transmit frequency is 24.08 GHz, but the vendor's velocity
  /// maths runs against a legacy 10.525 GHz reference (from the older X-band
  /// Pocket radar), so the parser first rescales the raw count by
  /// 10525/24080 and the converter then divides by 10.525 GHz. The two
  /// cancel to a plain 24.08 GHz doppler conversion.
  ///
  /// We keep the two-step form on purpose: the reference truncates the
  /// rescaled value to an int, and reproducing that truncation makes our
  /// velocity match what the FX apps show for the same shot — worth more
  /// than the ≤0.015 m/s it costs.
  static const double _rescaleNum = 10525.0;
  static const double _rescaleDen = 24080.0;
  static const double _sensorFrequency = 10525000000.0;

  /// Doppler frequency → m/s, matching `BaseConverter.coreConversionFromHertz`
  /// in ChronoIOS and `FpsConverter.fromHertz` in ChronoAndroid.
  static double hertzToMs(int hertz) => hertz * _c / _sensorFrequency / 2.0;

  /// Applies the vendor's raw→Hz rescale, including its integer truncation.
  static int rawToHertz(int rawHertz) =>
      (_rescaleNum / _rescaleDen * rawHertz).toInt();

  /// Parses a shot notification. Returns null when [bytes] is not a shot
  /// packet we understand, or carries no usable velocity — callers should
  /// simply ignore those rather than surfacing an error, since the device
  /// also emits packet types we do not consume.
  static TrueBallisticShot? parse(List<int> bytes) {
    // 1 type byte + 3 hertz bytes is the shortest thing worth reading.
    if (bytes.length < 4) return null;

    final type = bytes[0];
    if (type != typeSimple && type != typeBallistic && type != typePolynomial) {
      return null;
    }

    // The reference guards the simple packet on an exact length; a short
    // 0x0A is a malformed frame, not a shot.
    if (type == typeSimple && bytes.length != 20) return null;

    // Big-endian uint24 at bytes[1..3], left-padded into a uint32.
    final rawHertz = (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];

    final hertz = rawToHertz(rawHertz);
    // A zero/negative reading is the device's idle state, not a shot.
    if (hertz <= 0) return null;

    final velocityMs = hertzToMs(hertz);
    // Semantic sanity, mirroring PocketProVelocity's 10 000 fps garbage
    // ceiling (= 3048 m/s): a corrupt frame can carry any uint24, and a
    // recognized packet type is no proof the count is a projectile. An
    // implausible velocity must not reach the shot pipeline where it
    // would poison statistics and energy readouts.
    if (velocityMs > 3048) return null;

    return TrueBallisticShot(
      velocityMs: velocityMs,
      hertz: hertz,
      packetType: type,
    );
  }

  /// True when [name] looks like a True Ballistic chronograph.
  static bool matchesName(String? name) =>
      name != null && name.startsWith(TrueBallisticUuids.namePrefix);
}

/// Owns the GATT connection to a single FX True Ballistic chronograph and
/// re-emits parsed shot data. Mirrors [PocketProClient]'s connection
/// lifecycle so HomePage can drive both connected chronographs through
/// one code path.
class TrueBallisticClient {
  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _shotSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  bool _connecting = false;

  final StreamController<TrueBallisticShot> _shotController =
      StreamController.broadcast();
  final StreamController<BluetoothConnectionState> _connectionStateController =
      StreamController.broadcast();

  /// One event per shot; idle (0 Hz) frames and unknown packet types are
  /// dropped by the parser.
  Stream<TrueBallisticShot> get shotStream => _shotController.stream;
  Stream<BluetoothConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Battery percentage read once during connect (the vendor characteristic
  /// is not notifiable), or null when the read failed / not connected yet.
  int? batteryPercent;

  /// Firmware revision string, when the device exposes 0x2A26.
  String? firmwareVersion;

  bool get isConnected => _device != null && _device!.isConnected;

  /// True while [connect] is in flight — the GATT link is being
  /// established but isn't usable yet.
  bool get isConnecting => _connecting;

  String? get remoteId => _device?.remoteId.str;

  /// True when a scan row looks like a True Ballistic chronograph.
  ///
  /// The device does not advertise its data service (the sibling apps
  /// identify it purely by the vendor's obfuscated name prefix), so the
  /// name is the primary signal. A unit that does advertise the service
  /// UUID is accepted too; matched by full-string equality, since a
  /// substring test could let an unrelated UUID's tail match.
  static bool matchesAd(Iterable<String> serviceUuidsLower, String name) {
    if (TrueBallisticParser.matchesName(name)) return true;
    return serviceUuidsLower.any((u) => u == TrueBallisticUuids.service);
  }

  /// Connect to the given device, discover the shot service, subscribe to
  /// shot notifications, and read battery + firmware once. No-op if already
  /// connected to the same device; releases the previous link first if
  /// connected to a different one.
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
      // Same CoreBluetooth quirk the Pocket Pro client guards against:
      // connect() can resolve before CBPeripheral.state has fully
      // transitioned, and racing into discoverServices / setNotifyValue
      // then throws "device is disconnected".
      if (!device.isConnected) {
        await device.connectionState
            .firstWhere((s) => s == BluetoothConnectionState.connected)
            .timeout(const Duration(seconds: 8));
      }
      final services = await device.discoverServices();
      for (final s in services) {
        final serviceUuid = s.uuid.toString().toLowerCase();
        if (serviceUuid == TrueBallisticUuids.service) {
          for (final c in s.characteristics) {
            final uuid = c.uuid.toString().toLowerCase();
            if (uuid == TrueBallisticUuids.notify) {
              // Install the listener BEFORE enabling notifications so a
              // shot arriving right after the CCCD write isn't lost.
              // Cancel before reassigning, in case firmware exposes the
              // same characteristic twice.
              await _shotSub?.cancel();
              _shotSub = c.onValueReceived.listen(_onShotBytes);
              await _setNotifyWithRetry(c);
            } else if (uuid == TrueBallisticUuids.battery) {
              // Vendor battery characteristic: a plain uint8 percentage
              // (ChronoAndroid feeds this straight into
              // Battery.setPercentage). Read once — it is not notifiable.
              try {
                final bytes = await c.read();
                if (bytes.isNotEmpty && bytes.first <= 100) {
                  batteryPercent = bytes.first;
                }
              } catch (_) {}
            }
            // CMD (0x1625) and STREAM (0x1626) are intentionally untouched:
            // we only listen, and the raw doppler stream is far too chatty.
          }
        } else if (serviceUuid.contains('180a')) {
          // Device Information: firmware revision 0x2a26.
          for (final c in s.characteristics) {
            if (c.uuid.toString().toLowerCase().contains('2a26')) {
              try {
                final bytes = await c.read();
                firmwareVersion = String.fromCharCodes(bytes).trim();
              } catch (_) {}
            }
          }
        }
      }

      // The scan match is name-based and therefore permissive. If the user
      // taps a device that matches by name but exposes no shot
      // characteristic, discovery completes with nothing subscribed —
      // without this guard the app would persist that id and auto-reconnect
      // to it forever while never producing a shot.
      if (_shotSub == null) {
        throw StateError(
          'Selected device exposes no shot characteristic — '
          'not a recognised True Ballistic Chronograph.',
        );
      }
    } catch (e) {
      debugPrint(
        'TrueBallisticClient: post-connect setup failed, '
        'releasing GATT link: $e',
      );
      await disconnect();
      rethrow;
    }
  }

  /// Retry setNotifyValue once if the platform still claims disconnected —
  /// the peripheral occasionally needs another tick after discovery.
  static Future<void> _setNotifyWithRetry(BluetoothCharacteristic c) async {
    try {
      await c.setNotifyValue(true);
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await c.setNotifyValue(true);
    }
  }

  void _onShotBytes(List<int> value) {
    final shot = TrueBallisticParser.parse(value);
    // Unknown packet types and idle (0 Hz) frames parse to null — the
    // device emits both, and neither is a shot.
    if (shot != null) _shotController.add(shot);
  }

  /// Tear down the shot subscription and disconnect the GATT link.
  /// Safe to call repeatedly; safe to call when not connected.
  Future<void> disconnect() async {
    // Snapshot _connecting before clearing — if the user disconnects
    // during an in-flight connect, we need to bypass FBP's default
    // disconnect queue which would otherwise wait behind the ongoing
    // connect for up to its 35 s timeout.
    final wasConnecting = _connecting;
    _connecting = false;
    await _shotSub?.cancel();
    _shotSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    final device = _device;
    _device = null;
    batteryPercent = null;
    firmwareVersion = null;
    if (device != null) {
      try {
        await device.disconnect(queue: !wasConnecting);
      } catch (e) {
        debugPrint('TrueBallisticClient: disconnect error (ignored): $e');
      }
    }
  }

  /// Release all resources. Call from the owning widget's `dispose`.
  Future<void> dispose() async {
    await disconnect();
    await _shotController.close();
    await _connectionStateController.close();
  }
}
