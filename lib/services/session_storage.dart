import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';

/// Handles persistence of shooting sessions using SharedPreferences.
///
/// Note: SharedPreferences has practical size limits. For very large session
/// histories, consider migrating to a file-based or database solution.
class SessionStorage {
  static const String _sessionsKey = 'chrono_sessions';
  static const String _corruptedBackupKey = 'chrono_sessions_corrupted';

  /// Save a session to storage.
  /// If session with same ID exists, it will be updated.
  /// Returns true on success, false on failure.
  static Future<bool> saveSession(Session session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessions = await loadAllSessions();

      // Find existing session by ID
      final index = sessions.indexWhere((s) => s.id == session.id);
      if (index >= 0) {
        // Update existing
        sessions[index] = session;
      } else {
        // Add new (at the beginning for recent-first ordering)
        sessions.insert(0, session);
      }

      // Save to preferences
      final jsonList = sessions.map((s) => s.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      // Check size before saving (SharedPreferences has ~1MB practical limit)
      if (jsonString.length > 900000) {
        debugPrint(
            'Warning: Session storage approaching size limit (${jsonString.length} bytes)');
      }

      final success = await prefs.setString(_sessionsKey, jsonString);
      if (!success) {
        debugPrint('Error: SharedPreferences.setString returned false');
      }
      return success;
    } catch (e) {
      debugPrint('Error saving session: $e');
      return false;
    }
  }

  /// Load all saved sessions.
  /// Returns empty list if no sessions exist or on parse error.
  /// Corrupted data is backed up before clearing.
  static Future<List<Session>> loadAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_sessionsKey);

    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final jsonList = jsonDecode(jsonString) as List;
      final sessions = <Session>[];

      for (final j in jsonList) {
        try {
          sessions.add(Session.fromJson(j as Map<String, dynamic>));
        } catch (e) {
          // Skip individual corrupted sessions but continue loading others
          debugPrint('Skipping corrupted session entry: $e');
        }
      }

      return sessions;
    } catch (e) {
      // Full parse failure - backup corrupted data and clear
      debugPrint('Session storage corrupted, backing up and clearing: $e');
      await _backupAndClearCorruptedData(prefs, jsonString);
      return [];
    }
  }

  /// Backup corrupted data for potential recovery and clear the main key.
  static Future<void> _backupAndClearCorruptedData(
      SharedPreferences prefs, String corruptedData) async {
    try {
      // Save corrupted data with timestamp for potential manual recovery
      final backupKey =
          '${_corruptedBackupKey}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(backupKey, corruptedData);
      debugPrint('Corrupted data backed up to: $backupKey');
    } catch (e) {
      debugPrint('Failed to backup corrupted data: $e');
    }

    // Clear the corrupted main data
    await prefs.remove(_sessionsKey);
  }

  /// Delete a session by ID.
  static Future<void> deleteSession(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await loadAllSessions();

    sessions.removeWhere((s) => s.id == sessionId);

    final jsonList = sessions.map((s) => s.toJson()).toList();
    await prefs.setString(_sessionsKey, jsonEncode(jsonList));
  }

  /// Delete all sessions.
  static Future<void> deleteAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionsKey);
  }

  /// Get a single session by ID.
  static Future<Session?> getSession(String sessionId) async {
    final sessions = await loadAllSessions();
    try {
      return sessions.firstWhere((s) => s.id == sessionId);
    } catch (e) {
      return null;
    }
  }

  /// Get storage size in bytes (approximate).
  static Future<int> getStorageSizeBytes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_sessionsKey);
    return jsonString?.length ?? 0;
  }

  /// Export a session to CSV format.
  static String exportToCsv(Session session) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('Chrono Lite - Session Export');
    buffer.writeln('Date,${session.createdAt.toIso8601String()}');
    buffer.writeln('Bullet Weight (grains),${session.bulletWeightGrains}');
    buffer.writeln('Shot Count,${session.shotCount}');
    buffer.writeln('Average (fps),${session.averageFps.toStringAsFixed(1)}');
    buffer.writeln('ES (fps),${session.extremeSpreadFps}');
    buffer.writeln('SD (fps),${session.standardDeviationFps.toStringAsFixed(1)}');
    buffer.writeln('');

    // Shot data
    buffer.writeln('Shot #,Velocity (fps),Time');
    for (final shot in session.shots) {
      buffer.writeln('${shot.number},${shot.velocityFps},${shot.timestamp.toIso8601String()}');
    }

    return buffer.toString();
  }
}
