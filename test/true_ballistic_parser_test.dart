import 'package:flutter_test/flutter_test.dart';

import 'package:chrono_lite/services/true_ballistic_client.dart';

/// Expected values were computed from the reference chain in
/// ChronoAndroid/ChronoIOS:
///   hertz = (int)(10525/24080 * raw)
///   m/s   = hertz * 299792458 / 10_525_000_000 / 2
/// raw 144583 -> hertz 63195 -> 900.0182604897863 m/s
void main() {
  /// Big-endian uint24 helper matching the wire layout at bytes[1..3].
  List<int> raw24(int raw) =>
      [(raw >> 16) & 0xFF, (raw >> 8) & 0xFF, raw & 0xFF];

  /// 0x0A must be exactly 20 bytes: type + 3 hertz + 4 veldist + padding.
  List<int> simplePacket(int raw) => [
        TrueBallisticParser.typeSimple,
        ...raw24(raw),
        0x00, 0x00, 0x00, 0x00, // packed velocity/distance — ignored
        ...List<int>.filled(12, 0),
      ];

  group('velocity extraction', () {
    test('simple packet (0x0A) yields muzzle velocity', () {
      final shot = TrueBallisticParser.parse(simplePacket(144583));

      expect(shot, isNotNull);
      expect(shot!.packetType, TrueBallisticParser.typeSimple);
      expect(shot.hertz, 63195);
      expect(shot.velocityMs, closeTo(900.018, 0.001));
    });

    test('ballistic packet (0x0B) yields velocity and ignores BC/drag model',
        () {
      // type + hertz(3) + bc float(4) + drag model(1)
      final bytes = [
        TrueBallisticParser.typeBallistic,
        ...raw24(144583),
        0x3E, 0xA1, 0x47, 0xAE, // ~0.315 as a big-endian float32
        0x01, // drag model
      ];

      final shot = TrueBallisticParser.parse(bytes);

      expect(shot, isNotNull);
      expect(shot!.packetType, TrueBallisticParser.typeBallistic);
      expect(shot.velocityMs, closeTo(900.018, 0.001));
    });

    test('polynomial packet (0x0C) yields velocity and ignores coefficients',
        () {
      final bytes = [
        TrueBallisticParser.typePolynomial,
        ...raw24(100000),
        ...List<int>.filled(12, 0x3F), // three float32 coefficients
        0x18, // tx freq
        0x00, 0x64, // sampling freq
      ];

      final shot = TrueBallisticParser.parse(bytes);

      expect(shot, isNotNull);
      expect(shot!.packetType, TrueBallisticParser.typePolynomial);
      expect(shot.hertz, 43708);
      expect(shot.velocityMs, closeTo(622.486, 0.001));
    });

    test('a slower shot scales linearly', () {
      final shot = TrueBallisticParser.parse(simplePacket(50000));

      expect(shot!.hertz, 21854);
      expect(shot.velocityMs, closeTo(311.243, 0.001));
    });

    test('velocityFps converts m/s to the fps shot pipeline', () {
      final shot = TrueBallisticParser.parse(simplePacket(144583));
      // 900.018 m/s / 0.3048 = 2952.816... fps
      expect(shot!.velocityFps, closeTo(2952.82, 0.01));
    });
  });

  group('conversion helpers', () {
    test('rawToHertz reproduces the vendor rescale, truncation included', () {
      expect(TrueBallisticParser.rawToHertz(144583), 63195);
      expect(TrueBallisticParser.rawToHertz(100000), 43708);
      // Truncation floors sub-Hz raws to zero, which the idle guard relies on.
      expect(TrueBallisticParser.rawToHertz(1), 0);
    });

    test('hertzToMs matches the sibling apps doppler maths', () {
      expect(TrueBallisticParser.hertzToMs(63195), closeTo(900.018, 0.001));
      expect(TrueBallisticParser.hertzToMs(0), 0);
    });

    test('two-step rescale stays within 0.015 m/s of a direct 24.08 GHz solve',
        () {
      // The vendor's 10525/24080 detour cancels to a plain 24.08 GHz doppler
      // conversion; only their int truncation separates the two.
      const c = 299792458.0;
      for (final raw in [144583, 100000, 50000]) {
        final direct = raw * c / (2 * 24080000000.0);
        final twoStep =
            TrueBallisticParser.hertzToMs(TrueBallisticParser.rawToHertz(raw));
        expect((direct - twoStep).abs(), lessThan(0.015));
      }
    });
  });

  group('guards', () {
    test('rejects unknown packet types', () {
      expect(TrueBallisticParser.parse([0x0D, 0x02, 0x34, 0xC7]), isNull);
      expect(TrueBallisticParser.parse([0x00, 0x02, 0x34, 0xC7]), isNull);
    });

    test('rejects a truncated packet', () {
      expect(TrueBallisticParser.parse([]), isNull);
      expect(
          TrueBallisticParser.parse([TrueBallisticParser.typeSimple]), isNull);
      expect(
        TrueBallisticParser.parse([TrueBallisticParser.typeSimple, 0x02, 0x34]),
        isNull,
      );
    });

    test('rejects a 0x0A packet that is not exactly 20 bytes', () {
      final short = [TrueBallisticParser.typeSimple, ...raw24(144583)];
      expect(TrueBallisticParser.parse(short), isNull);
      expect(
          TrueBallisticParser.parse([...simplePacket(144583), 0x00]), isNull);
    });

    test('treats a zero reading as idle, not a shot', () {
      expect(TrueBallisticParser.parse(simplePacket(0)), isNull);
      // Raw values small enough to truncate to 0 Hz are idle too.
      expect(TrueBallisticParser.parse(simplePacket(1)), isNull);
    });

    test('rejects implausible velocities from corrupt doppler counts', () {
      // raw 1_000_000 -> ~6225 m/s — no projectile; must not reach the
      // shot pipeline. Ceiling mirrors the Pocket Pro's 10 000 fps guard.
      expect(TrueBallisticParser.parse(simplePacket(1000000)), isNull);
      // Max uint24 would be ~104 000 m/s.
      expect(TrueBallisticParser.parse(simplePacket(0xFFFFFF)), isNull);
      // A fast but plausible rifle shot still passes (raw 144583 ≈ 900 m/s).
      expect(TrueBallisticParser.parse(simplePacket(144583)), isNotNull);
    });
  });

  group('device identification', () {
    test('matches the vendor advertised-name prefix', () {
      expect(TrueBallisticParser.matchesName('vXfS3c6k'), isTrue);
      expect(TrueBallisticParser.matchesName('vXfS3c6k-1234'), isTrue);
    });

    test('does not match other FX devices or null', () {
      expect(TrueBallisticParser.matchesName('FXCHR12'), isFalse);
      expect(TrueBallisticParser.matchesName('DRCHR17'), isFalse);
      expect(TrueBallisticParser.matchesName('FX-Level'), isFalse);
      expect(TrueBallisticParser.matchesName('FX Pocket Pro'), isFalse);
      expect(TrueBallisticParser.matchesName(''), isFalse);
      expect(TrueBallisticParser.matchesName(null), isFalse);
    });

    test('matchesAd accepts the service UUID by exact match only', () {
      expect(
        TrueBallisticClient.matchesAd(
          ['00001623-88ec-688c-644b-3fa706c0bb76'],
          'SomethingElse',
        ),
        isTrue,
      );
      expect(
        TrueBallisticClient.matchesAd(
          ['5445883a-3cab-42e5-b625-ca4e243f5a2c'], // Pocket Pro VRS
          'SomethingElse',
        ),
        isFalse,
      );
      expect(TrueBallisticClient.matchesAd([], 'vXfS3c6k-99'), isTrue);
    });
  });
}
