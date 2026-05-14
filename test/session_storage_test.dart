import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chrono_lite/models/session.dart';
import 'package:chrono_lite/models/shot.dart';
import 'package:chrono_lite/services/session_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Reset SharedPreferences before each test
    SharedPreferences.setMockInitialValues({});
  });

  group('SessionStorage', () {
    Session createTestSession({
      String id = 'test-session-1',
      int shotCount = 3,
      double bulletWeight = 18.0,
    }) {
      final shots = List.generate(
        shotCount,
        (i) => Shot(
          number: i + 1,
          velocityFps: 890 + i * 5,
          timestamp: DateTime(2024, 1, 1, 12, 0, i),
        ),
      );
      return Session(
        id: id,
        createdAt: DateTime(2024, 1, 1, 12, 0, 0),
        bulletWeightGrains: bulletWeight,
        shots: shots,
      );
    }

    group('saveSession', () {
      test('saves a new session', () async {
        final session = createTestSession();
        await SessionStorage.saveSession(session);

        final loaded = await SessionStorage.loadAllSessions();
        expect(loaded.length, 1);
        expect(loaded.first.id, session.id);
        expect(loaded.first.shotCount, session.shotCount);
      });

      test('updates existing session with same ID', () async {
        final session1 = createTestSession(shotCount: 2);
        await SessionStorage.saveSession(session1);

        final session2 = session1.addShot(900);
        await SessionStorage.saveSession(session2);

        final loaded = await SessionStorage.loadAllSessions();
        expect(loaded.length, 1);
        expect(loaded.first.shotCount, 3);
      });

      test('adds new sessions at the beginning', () async {
        final session1 = createTestSession(id: 'session-1');
        final session2 = createTestSession(id: 'session-2');

        await SessionStorage.saveSession(session1);
        await SessionStorage.saveSession(session2);

        final loaded = await SessionStorage.loadAllSessions();
        expect(loaded.length, 2);
        expect(loaded[0].id, 'session-2'); // Most recent first
        expect(loaded[1].id, 'session-1');
      });
    });

    group('loadAllSessions', () {
      test('returns empty list when no sessions exist', () async {
        final loaded = await SessionStorage.loadAllSessions();
        expect(loaded, isEmpty);
      });

      test('returns empty list on corrupted data', () async {
        SharedPreferences.setMockInitialValues({
          'chrono_sessions': 'not valid json',
        });

        final loaded = await SessionStorage.loadAllSessions();
        expect(loaded, isEmpty);
      });

      test('preserves session data through save/load cycle', () async {
        final session = createTestSession(
          id: 'preserve-test',
          shotCount: 5,
          bulletWeight: 25.4,
        );
        await SessionStorage.saveSession(session);

        final loaded = await SessionStorage.loadAllSessions();
        final loadedSession = loaded.first;

        expect(loadedSession.id, session.id);
        expect(loadedSession.bulletWeightGrains, session.bulletWeightGrains);
        expect(loadedSession.shotCount, session.shotCount);
        expect(loadedSession.shots[0].velocityFps, session.shots[0].velocityFps);
      });
    });

    group('deleteSession', () {
      test('removes session by ID', () async {
        final session1 = createTestSession(id: 'keep');
        final session2 = createTestSession(id: 'delete');

        await SessionStorage.saveSession(session1);
        await SessionStorage.saveSession(session2);

        await SessionStorage.deleteSession('delete');

        final loaded = await SessionStorage.loadAllSessions();
        expect(loaded.length, 1);
        expect(loaded.first.id, 'keep');
      });

      test('does nothing if ID not found', () async {
        final session = createTestSession();
        await SessionStorage.saveSession(session);

        await SessionStorage.deleteSession('nonexistent');

        final loaded = await SessionStorage.loadAllSessions();
        expect(loaded.length, 1);
      });
    });

    group('deleteAllSessions', () {
      test('removes all sessions', () async {
        await SessionStorage.saveSession(createTestSession(id: '1'));
        await SessionStorage.saveSession(createTestSession(id: '2'));
        await SessionStorage.saveSession(createTestSession(id: '3'));

        await SessionStorage.deleteAllSessions();

        final loaded = await SessionStorage.loadAllSessions();
        expect(loaded, isEmpty);
      });
    });

    group('getSession', () {
      test('returns session by ID', () async {
        final session = createTestSession(id: 'find-me');
        await SessionStorage.saveSession(session);

        final found = await SessionStorage.getSession('find-me');
        expect(found, isNotNull);
        expect(found!.id, 'find-me');
      });

      test('returns null if not found', () async {
        final found = await SessionStorage.getSession('nonexistent');
        expect(found, isNull);
      });
    });

    group('exportToCsv', () {
      test('generates valid CSV format', () {
        final session = createTestSession(id: 'csv-test', shotCount: 2);
        final csv = SessionStorage.exportToCsv(session);

        expect(csv, contains('Chrono Lite - Session Export'));
        expect(csv, contains('Shot Count,2'));
        expect(csv, contains('Shot #,Velocity (fps),Time'));
        expect(csv, contains('1,890'));
        expect(csv, contains('2,895'));
      });
    });
  });

  group('Session model', () {
    test('calculates average velocity correctly', () {
      final session = Session(
        id: 'test',
        createdAt: DateTime.now(),
        bulletWeightGrains: 18.0,
        shots: [
          Shot(number: 1, velocityFps: 880, timestamp: DateTime.now()),
          Shot(number: 2, velocityFps: 900, timestamp: DateTime.now()),
          Shot(number: 3, velocityFps: 920, timestamp: DateTime.now()),
        ],
      );

      expect(session.averageFps, 900.0);
    });

    test('calculates extreme spread correctly', () {
      final session = Session(
        id: 'test',
        createdAt: DateTime.now(),
        bulletWeightGrains: 18.0,
        shots: [
          Shot(number: 1, velocityFps: 880, timestamp: DateTime.now()),
          Shot(number: 2, velocityFps: 920, timestamp: DateTime.now()),
        ],
      );

      expect(session.extremeSpreadFps, 40);
    });

    test('calculates standard deviation correctly', () {
      final session = Session(
        id: 'test',
        createdAt: DateTime.now(),
        bulletWeightGrains: 18.0,
        shots: [
          Shot(number: 1, velocityFps: 890, timestamp: DateTime.now()),
          Shot(number: 2, velocityFps: 900, timestamp: DateTime.now()),
          Shot(number: 3, velocityFps: 910, timestamp: DateTime.now()),
        ],
      );

      // SD = sqrt(((890-900)^2 + (900-900)^2 + (910-900)^2) / 3)
      // SD = sqrt((100 + 0 + 100) / 3) = sqrt(66.67) = ~8.16
      expect(session.standardDeviationFps, closeTo(8.16, 0.01));
    });

    test('returns zero statistics for empty session', () {
      final session = Session(
        id: 'test',
        createdAt: DateTime.now(),
        bulletWeightGrains: 18.0,
        shots: [],
      );

      expect(session.averageFps, 0);
      expect(session.extremeSpreadFps, 0);
      expect(session.standardDeviationFps, 0);
      expect(session.minFps, 0);
      expect(session.maxFps, 0);
    });

    test('returns zero SD for single shot', () {
      final session = Session(
        id: 'test',
        createdAt: DateTime.now(),
        bulletWeightGrains: 18.0,
        shots: [
          Shot(number: 1, velocityFps: 900, timestamp: DateTime.now()),
        ],
      );

      expect(session.standardDeviationFps, 0);
      expect(session.extremeSpreadFps, 0);
    });

    test('addShot creates new session with additional shot', () {
      final session = Session(
        id: 'test',
        createdAt: DateTime.now(),
        bulletWeightGrains: 18.0,
        shots: [],
      );

      final withShot = session.addShot(900);

      expect(session.shotCount, 0); // Original unchanged
      expect(withShot.shotCount, 1);
      expect(withShot.shots.first.velocityFps, 900);
      expect(withShot.shots.first.number, 1);
    });

    test('JSON serialization round-trip preserves data', () {
      final original = Session(
        id: 'json-test',
        createdAt: DateTime(2024, 6, 15, 10, 30, 0),
        bulletWeightGrains: 21.5,
        shots: [
          Shot(number: 1, velocityFps: 885, timestamp: DateTime(2024, 6, 15, 10, 30, 1)),
          Shot(number: 2, velocityFps: 892, timestamp: DateTime(2024, 6, 15, 10, 30, 5)),
        ],
        name: 'Test Session',
      );

      final json = original.toJson();
      final restored = Session.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.createdAt, original.createdAt);
      expect(restored.bulletWeightGrains, original.bulletWeightGrains);
      expect(restored.name, original.name);
      expect(restored.shotCount, original.shotCount);
      expect(restored.shots[0].velocityFps, original.shots[0].velocityFps);
      expect(restored.shots[1].timestamp, original.shots[1].timestamp);
    });
  });
}
