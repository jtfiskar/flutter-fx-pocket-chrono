import 'package:flutter_test/flutter_test.dart';
import 'package:chrono_lite/models/session.dart';
import 'package:chrono_lite/models/shot.dart';

Session _withVelocities(List<int> values) {
  return Session(
    id: 't',
    createdAt: DateTime(2024),
    bulletWeightGrains: 18.0,
    shots: [
      for (int i = 0; i < values.length; i++)
        Shot(
          number: i + 1,
          velocityFps: values[i],
          timestamp: DateTime(2024, 1, 1, 12, 0, i),
        ),
    ],
  );
}

void main() {
  group('Session.medianFps', () {
    test('returns 0 for an empty session', () {
      expect(_withVelocities([]).medianFps, 0);
    });

    test('returns the single value when length is 1', () {
      expect(_withVelocities([900]).medianFps, 900.0);
    });

    test('returns the middle value on odd length', () {
      // sorted: [880, 890, 900, 910, 920], median = 900
      expect(_withVelocities([900, 880, 920, 890, 910]).medianFps, 900.0);
    });

    test('averages the two middle values on even length', () {
      // sorted: [880, 890, 900, 910], median = (890 + 900) / 2 = 895
      expect(_withVelocities([900, 880, 910, 890]).medianFps, 895.0);
    });

    test('handles duplicates correctly', () {
      // sorted: [900, 900, 900], median = 900
      expect(_withVelocities([900, 900, 900]).medianFps, 900.0);
    });
  });
}
