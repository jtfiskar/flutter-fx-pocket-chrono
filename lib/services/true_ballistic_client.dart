/// Parser and GATT client for the FX True Ballistic Chronograph.
///
/// The device is a 24.08 GHz doppler radar. Unlike the Pocket Chronograph —
/// which broadcasts shots in its advertisement and needs no connection — the
/// True Ballistic is a connected GATT device that pushes one notification per
/// shot on [TrueBallisticUuids.notify].
///
/// Chrono Lite's shot pipeline wants **muzzle velocity only**, but the parser
/// decodes everything the firmware puts on the wire so this file doubles as a
/// worked example of the protocol:
///
///   - 0x0B "ballistic" packets carry the on-device BC fit and the drag model
///     it was fitted against ([TrueBallisticShot.bc], [TrueBallisticShot.dragModel]).
///   - 0x0C "polynomial" packets carry the raw velocity-decay polynomial for
///     shots where the BC fit did not converge; those coefficients are still
///     parsed past and discarded.
///   - The optional "3rd party interface" characteristic
///     ([TrueBallisticUuids.thirdParty]) pushes an ASCII string with the
///     fitted velocity at 0 / 50 / 100 m ([TrueBallisticDownrange]).
///
/// Mirrors the reference client in
/// `~/flutter/BallisticSolver/lib/services/true_ballistic_parser.dart` and
/// `true_ballistic_ble_service.dart`, extended with the firmware's 0x0B
/// payload and 0x162B string (`StmRangeChrono/Src/ble.c`).
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

  /// "3rd party interface" (read + notify, added in later firmware).
  ///
  /// One ASCII string per shot, `"%05u-%05u-%05u"`, holding the fitted
  /// velocity at 0 m, 50 m and 100 m in tenths of fps. The 50/100 m fields
  /// are `00000` whenever the BC fit failed (the same shots that arrive as
  /// 0x0C on [notify]). Initial value before the first shot is `"Boot"`.
  /// Older firmware does not expose this characteristic at all.
  static const String thirdParty = '0000162b-88ec-688c-644b-3fa706c0bb76';
}

/// Drag model the chronograph fitted its BC against (0x0B byte 8).
///
/// Ids match `DRAG_MODEL_*` in the firmware's `config.h`. Ids 1 and 2 were
/// the first-generation G1/G7 tables and are no longer selectable in the
/// device menu, but are kept here so an old unit still decodes.
enum TrueBallisticDragModel {
  /// "Basic": no drag model, the BC solver never runs. A shot taken in this
  /// mode is always sent as 0x0C, so this value never appears in a 0x0B
  /// packet in practice; it is here for completeness.
  basic(0, 'Basic'),
  g1Legacy(1, 'G1 (legacy)'),
  g7Legacy(2, 'G7 (legacy)'),
  g1(3, 'G1'),
  g7(4, 'G7'),
  ra4(5, 'RA4'),
  ga(6, 'GA');

  const TrueBallisticDragModel(this.id, this.label);

  /// Wire id.
  final int id;

  /// Short human label, as shown in the device's own menu.
  final String label;

  static TrueBallisticDragModel? fromId(int id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }
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

  /// Ballistic coefficient fitted on the device, in the units of [dragModel]
  /// (e.g. lb/in² for G1/G7). Only present on 0x0B packets; null otherwise,
  /// which means the device could not fit a BC for this shot — *not* that
  /// the drag model is "Basic".
  final double? bc;

  /// Drag model the BC was fitted against. Only present on 0x0B packets.
  final TrueBallisticDragModel? dragModel;

  /// Raw drag-model id from the wire, kept so an id this enum does not know
  /// (newer firmware) is still visible. Only present on 0x0B packets.
  final int? dragModelId;

  const TrueBallisticShot({
    required this.velocityMs,
    required this.hertz,
    required this.packetType,
    this.bc,
    this.dragModel,
    this.dragModelId,
  });

  /// Muzzle velocity in fps — Chrono Lite's shot pipeline is fps-based.
  double get velocityFps => velocityMs / 0.3048;

  /// True when the packet carried a fitted BC.
  bool get hasBc => bc != null;

  @override
  String toString() {
    final base = 'TrueBallisticShot(${velocityMs.toStringAsFixed(1)} m/s, '
        '$hertz Hz, type 0x${packetType.toRadixString(16).toUpperCase()}';
    if (bc == null) return '$base)';
    final model = dragModel?.label ?? 'model $dragModelId';
    return '$base, BC ${bc!.toStringAsFixed(3)} $model)';
  }
}

/// Fitted downrange velocities from the "3rd party interface" string.
///
/// The firmware evaluates its fitted trajectory at three fixed ranges. Field
/// one is the regression's 0 m velocity and can differ by a few fps from the
/// Doppler peak carried in the shot packet for the same shot.
class TrueBallisticDownrange {
  /// Velocity at the muzzle (0 m), fps.
  final double muzzleFps;

  /// Velocity at 50 m, fps. Null when the device could not fit a BC.
  final double? fps50m;

  /// Velocity at 100 m, fps. Null when the device could not fit a BC.
  final double? fps100m;

  const TrueBallisticDownrange({
    required this.muzzleFps,
    this.fps50m,
    this.fps100m,
  });

  /// True when both downrange values are present, i.e. the BC fit succeeded.
  bool get hasDownrange => fps50m != null && fps100m != null;

  @override
  String toString() => 'TrueBallisticDownrange('
      '${muzzleFps.toStringAsFixed(1)} fps @0m, '
      '${fps50m?.toStringAsFixed(1) ?? '—'} @50m, '
      '${fps100m?.toStringAsFixed(1) ?? '—'} @100m)';
}

class TrueBallisticParser {
  /// Simple shot: velocity only (plus a downrange vel/dist pair we ignore).
  /// The reference implementations require exactly 20 bytes for this type.
  static const int typeSimple = 0x0A;

  /// Ballistic: velocity + measured BC + drag model. Layout:
  ///
  /// | Bytes | Field       | Encoding                              |
  /// |-------|-------------|---------------------------------------|
  /// | 0     | type        | 0x0B                                  |
  /// | 1-3   | muzzle Hz   | uint24 big-endian, 24.08 GHz carrier  |
  /// | 4-7   | BC          | float32 big-endian                    |
  /// | 8     | drag model  | [TrueBallisticDragModel] id           |
  static const int typeBallistic = 0x0B;

  /// Wire length of a complete 0x0B packet.
  static const int ballisticLength = 9;

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

    double? bc;
    int? dragModelId;
    if (type == typeBallistic && bytes.length >= ballisticLength) {
      // Firmware writes the float MSB-first (bc[3]..bc[0] of a little-endian
      // ARM float), so this is a plain big-endian IEEE 754 read.
      final value = ByteData.sublistView(
        Uint8List.fromList(bytes.sublist(4, 8)),
      ).getFloat32(0, Endian.big);
      // A non-finite or non-positive BC is a corrupt frame, never a fit —
      // the solver only reports after it converged on a positive value.
      if (value.isFinite && value > 0) {
        bc = value;
        dragModelId = bytes[8];
      }
    }

    return TrueBallisticShot(
      velocityMs: velocityMs,
      hertz: hertz,
      packetType: type,
      bc: bc,
      dragModel: dragModelId == null
          ? null
          : TrueBallisticDragModel.fromId(dragModelId),
      dragModelId: dragModelId,
    );
  }

  /// Parses a "3rd party interface" notification ([TrueBallisticUuids.thirdParty]).
  ///
  /// The payload is ASCII `"%05u-%05u-%05u"`: velocity at 0 / 50 / 100 m in
  /// tenths of fps, e.g. `20434-20441-20623` = 2043.4 / 2044.1 / 2062.3 fps.
  /// Returns null for the boot placeholder, a malformed string, or a zero
  /// muzzle field. Zero downrange fields decode as null (BC fit failed).
  static TrueBallisticDownrange? parseThirdParty(List<int> bytes) {
    // Any byte outside printable ASCII is not this string.
    if (bytes.any((b) => b < 0x20 || b > 0x7E)) return null;
    final text = String.fromCharCodes(bytes).trim();
    final parts = text.split('-');
    if (parts.length != 3) return null;

    final values = <int>[];
    for (final part in parts) {
      // Exactly five digits — the format is zero-padded and a uint16 never
      // exceeds 65535, so anything else is not a firmware frame.
      if (part.length != 5) return null;
      final v = int.tryParse(part);
      if (v == null || v < 0) return null;
      values.add(v);
    }

    final muzzleFps = values[0] / 10.0;
    if (muzzleFps <= 0) return null;
    return TrueBallisticDownrange(
      muzzleFps: muzzleFps,
      fps50m: values[1] == 0 ? null : values[1] / 10.0,
      fps100m: values[2] == 0 ? null : values[2] / 10.0,
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
  StreamSubscription<List<int>>? _thirdPartySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  bool _connecting = false;

  final StreamController<TrueBallisticShot> _shotController =
      StreamController.broadcast();
  final StreamController<TrueBallisticDownrange> _downrangeController =
      StreamController.broadcast();
  final StreamController<BluetoothConnectionState> _connectionStateController =
      StreamController.broadcast();

  /// One event per shot; idle (0 Hz) frames and unknown packet types are
  /// dropped by the parser.
  Stream<TrueBallisticShot> get shotStream => _shotController.stream;

  /// Fitted 0 / 50 / 100 m velocities, one event per shot, from the
  /// "3rd party interface" characteristic. Chrono Lite does not consume
  /// this — it is wired up as a reference for clients that want downrange
  /// data without re-fitting the 0x0C polynomial. Silent on firmware that
  /// predates the characteristic (see [hasThirdPartyInterface]).
  Stream<TrueBallisticDownrange> get downrangeStream =>
      _downrangeController.stream;

  /// True once discovery found the optional 0x162B characteristic.
  bool get hasThirdPartyInterface => _thirdPartySub != null;
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
            } else if (uuid == TrueBallisticUuids.thirdParty) {
              // Optional on newer firmware. Same listener-before-CCCD
              // ordering as the shot characteristic; a failure here must
              // not abort the connect, since the shot feed is what matters.
              await _thirdPartySub?.cancel();
              _thirdPartySub = c.onValueReceived.listen(_onThirdPartyBytes);
              try {
                await _setNotifyWithRetry(c);
              } catch (e) {
                debugPrint(
                  'TrueBallisticClient: 3rd party notify failed (ignored): $e',
                );
                await _thirdPartySub?.cancel();
                _thirdPartySub = null;
              }
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
    if (shot != null) {
      // Logged so anyone running from source can see the full decode
      // (BC, drag model) even though the UI shows only velocity.
      debugPrint('TrueBallisticClient: $shot');
      _shotController.add(shot);
    }
  }

  void _onThirdPartyBytes(List<int> value) {
    final downrange = TrueBallisticParser.parseThirdParty(value);
    // "Boot" and malformed strings parse to null.
    if (downrange != null) {
      debugPrint('TrueBallisticClient: $downrange');
      _downrangeController.add(downrange);
    }
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
    await _thirdPartySub?.cancel();
    _thirdPartySub = null;
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
    await _downrangeController.close();
    await _connectionStateController.close();
  }
}
