import 'package:flutter_test/flutter_test.dart';
import 'package:chrono_lite/services/pocket_pro_client.dart';

void main() {
  group('PocketProVelocity.tryParseString', () {
    test('parses canonical fps,angle,bc,type', () {
      final v = PocketProVelocity.tryParseString('3200,1.5,0.013,1');
      expect(v, isNotNull);
      expect(v!.velocityFps, 3200.0);
      expect(v.angle, 1.5);
      expect(v.bc, 0.013);
      expect(v.bcType, 1);
    });

    test('parses fractional fps', () {
      final v = PocketProVelocity.tryParseString('3200.5,1.5,0.013,1');
      expect(v, isNotNull);
      expect(v!.velocityFps, 3200.5);
    });

    test('tolerates trailing whitespace and inner spaces', () {
      final v = PocketProVelocity.tryParseString('  3200 , 1.5 , 0.013 , 1  ');
      expect(v, isNotNull);
      expect(v!.velocityFps, 3200);
      expect(v.bcType, 1);
    });

    test('returns null on too few fields', () {
      expect(PocketProVelocity.tryParseString('3200,1.5,0.013'), isNull);
      expect(PocketProVelocity.tryParseString('3200'), isNull);
      expect(PocketProVelocity.tryParseString(''), isNull);
    });

    test('returns null when any field fails to parse', () {
      expect(PocketProVelocity.tryParseString('abc,1.5,0.013,1'), isNull);
      expect(PocketProVelocity.tryParseString('3200,xyz,0.013,1'), isNull);
      expect(PocketProVelocity.tryParseString('3200,1.5,abc,1'), isNull);
      expect(PocketProVelocity.tryParseString('3200,1.5,0.013,xyz'), isNull);
    });

    test('rejects semantically invalid velocities', () {
      // double.tryParse accepts these, but they must not reach the
      // shot pipeline as muzzle velocities.
      expect(PocketProVelocity.tryParseString('NaN,1.5,0.013,1'), isNull);
      expect(PocketProVelocity.tryParseString('Infinity,1.5,0.013,1'), isNull);
      expect(PocketProVelocity.tryParseString('-5,1.5,0.013,1'), isNull);
      expect(PocketProVelocity.tryParseString('0,1.5,0.013,1'), isNull);
      expect(PocketProVelocity.tryParseString('99999,1.5,0.013,1'), isNull);
    });

    test('rejects non-finite angle and negative BC', () {
      expect(PocketProVelocity.tryParseString('3200,NaN,0.013,1'), isNull);
      expect(PocketProVelocity.tryParseString('3200,1.5,-0.013,1'), isNull);
      expect(PocketProVelocity.tryParseString('3200,1.5,NaN,1'), isNull);
    });
  });

  group('PocketProVelocity.tryParse (raw bytes)', () {
    test('parses bytes with trailing null terminator', () {
      // "3200,1.5,0.013,1" + '\0'
      final bytes = '3200,1.5,0.013,1'.codeUnits + [0];
      final v = PocketProVelocity.tryParse(bytes);
      expect(v, isNotNull);
      expect(v!.velocityFps, 3200);
    });

    test('parses bytes with multiple trailing nulls', () {
      final bytes = '3200,1.5,0.013,1'.codeUnits + [0, 0, 0];
      final v = PocketProVelocity.tryParse(bytes);
      expect(v, isNotNull);
      expect(v!.velocityFps, 3200);
    });

    test('returns null on empty payload', () {
      expect(PocketProVelocity.tryParse([]), isNull);
      expect(PocketProVelocity.tryParse([0, 0, 0]), isNull);
    });

    test('parses without trailing null', () {
      final v = PocketProVelocity.tryParse('3200,1.5,0.013,1'.codeUnits);
      expect(v, isNotNull);
    });

    test('returns null on invalid UTF-8', () {
      expect(PocketProVelocity.tryParse([0xFF, 0xFE, 0xFD]), isNull);
    });
  });

  group('Pocket Pro advertisement detection', () {
    test('service UUID matches VRS', () {
      expect(
        PocketProClient.serviceUuid.str.toLowerCase(),
        '5445883a-3cab-42e5-b625-ca4e243f5a2c',
      );
    });
  });
}
