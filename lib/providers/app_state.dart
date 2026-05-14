import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/broadcast_data.dart';
import '../models/chronograph_device.dart';
import '../models/session.dart';
import '../models/shot.dart';
import '../services/session_storage.dart';

/// Central state management for Chrono Lite app.
///
/// Manages:
/// - Device connection state (via BLE broadcasts)
/// - Current shooting session
/// - Saved sessions history
/// - User preferences (units, bullet weight)
class AppState extends ChangeNotifier {
  // ============================================================
  // Device State
  // ============================================================

  /// Currently "connected" chronograph device (detected via broadcasts)
  ChronographDevice? _connectedDevice;

  /// Whether we're actively scanning for devices
  bool _isScanning = false;

  /// Timer for device loss detection (checks every second)
  Timer? _deviceLossTimer;

  /// Duration after which reconnection attempt is considered timed out
  static const _reconnectTimeout = Duration(seconds: 30);

  /// When device was first detected as lost (for timeout tracking)
  DateTime? _deviceLostAt;

  /// Last connected device ID (persisted for auto-reconnect)
  String? _lastConnectedDeviceId;

  // ============================================================
  // Session State
  // ============================================================

  /// Current active session (null if no session started)
  Session? _currentSession;

  /// All saved sessions from storage
  List<Session> _savedSessions = [];

  /// Last shot counter from device (for detecting new shots)
  int _lastShotCounter = -1;

  /// Last connected device ID (for detecting device changes)
  String? _lastDeviceId;

  /// Flag to prevent concurrent _recordShot calls (simple mutex)
  bool _isRecordingShot = false;

  // ============================================================
  // User Preferences
  // ============================================================

  /// Bullet weight in grains (for energy calculations)
  double _bulletWeightGrains = 18.0;

  /// Use FPS for velocity display (false = m/s)
  bool _useFps = true;

  /// Use ft-lbs for energy display (false = Joules)
  bool _useFtLbs = true;

  // ============================================================
  // Persistence Keys
  // ============================================================

  static const String _bulletWeightKey = 'bullet_weight_grains';
  static const String _useFpsKey = 'use_fps';
  static const String _useFtLbsKey = 'use_ftlbs';
  static const String _currentSessionIdKey = 'current_session_id';
  static const String _lastConnectedDeviceIdKey = 'last_connected_device_id';

  // ============================================================
  // Getters - Device
  // ============================================================

  ChronographDevice? get connectedDevice => _connectedDevice;
  bool get isScanning => _isScanning;
  bool get isConnected => _connectedDevice != null && !_connectedDevice!.isLost;
  bool get isDeviceLost => _connectedDevice != null && _connectedDevice!.isLost;
  String? get lastConnectedDeviceId => _lastConnectedDeviceId;

  /// Whether reconnection attempt has timed out (device lost for > 30 seconds)
  bool get isReconnectTimedOut {
    if (_deviceLostAt == null) return false;
    return DateTime.now().difference(_deviceLostAt!) > _reconnectTimeout;
  }

  // ============================================================
  // Getters - Session
  // ============================================================

  Session? get currentSession => _currentSession;
  List<Session> get savedSessions => _savedSessions;
  bool get hasActiveSession => _currentSession != null;

  /// Most recent shot from current session
  Shot? get lastShot => _currentSession?.lastShot;

  /// Last velocity in FPS (0 if no shots)
  int get lastVelocityFps => lastShot?.velocityFps ?? 0;

  /// Number of shots in current session
  int get shotCount => _currentSession?.shotCount ?? 0;

  /// Whether current session has statistics (2+ shots)
  bool get hasStatistics => _currentSession?.hasStatistics ?? false;

  // ============================================================
  // Getters - Statistics (from current session)
  // ============================================================

  double get averageFps => _currentSession?.averageFps ?? 0;
  double get averageMs => _currentSession?.averageMs ?? 0;
  int get extremeSpreadFps => _currentSession?.extremeSpreadFps ?? 0;
  double get standardDeviationFps => _currentSession?.standardDeviationFps ?? 0;
  int get minFps => _currentSession?.minFps ?? 0;
  int get maxFps => _currentSession?.maxFps ?? 0;

  // ============================================================
  // Getters - Preferences
  // ============================================================

  double get bulletWeightGrains => _bulletWeightGrains;
  double get bulletWeightGrams => _bulletWeightGrains * 0.0648;
  bool get useFps => _useFps;
  bool get useFtLbs => _useFtLbs;

  // ============================================================
  // Initialization
  // ============================================================

  /// Initialize state by loading saved sessions and preferences.
  Future<void> initialize() async {
    await Future.wait([
      _loadPreferences(),
      _loadSavedSessions(),
    ]);
  }

  /// Load preferences from SharedPreferences.
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    _bulletWeightGrains = prefs.getDouble(_bulletWeightKey) ?? 18.0;
    _useFps = prefs.getBool(_useFpsKey) ?? true;
    _useFtLbs = prefs.getBool(_useFtLbsKey) ?? true;
    _lastConnectedDeviceId = prefs.getString(_lastConnectedDeviceIdKey);

    // Try to restore current session if app was closed mid-session
    final currentSessionId = prefs.getString(_currentSessionIdKey);
    if (currentSessionId != null) {
      _currentSession = await SessionStorage.getSession(currentSessionId);
      if (_currentSession != null) {
        // Restore shot counter to avoid re-recording shots
        _lastShotCounter = -1; // Will sync on first broadcast
      }
    }

    notifyListeners();
  }

  /// Load all saved sessions from storage.
  Future<void> _loadSavedSessions() async {
    _savedSessions = await SessionStorage.loadAllSessions();
    notifyListeners();
  }

  // ============================================================
  // Session Management
  // ============================================================

  /// Start a new session.
  ///
  /// If there's an existing session with shots, it will be saved first.
  /// Returns true if successful, false if previous session save failed.
  Future<bool> startNewSession() async {
    // Auto-save current session if it has shots
    if (_currentSession != null && _currentSession!.shotCount > 0) {
      final saved = await SessionStorage.saveSession(_currentSession!);
      if (!saved) {
        // Failed to save current session - abort to prevent data loss
        debugPrint('Error: Failed to save current session, aborting new session');
        notifyListeners();
        return false;
      }
      await _loadSavedSessions();
    }

    // Create new session with unique ID
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentSession = Session(
      id: sessionId,
      createdAt: DateTime.now(),
      bulletWeightGrains: _bulletWeightGrains,
      shots: [],
    );

    // Reset shot counter for new session
    _lastShotCounter = -1;

    // Save current session ID for recovery
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentSessionIdKey, sessionId);

    notifyListeners();
    return true;
  }

  /// Clear current session without saving.
  Future<void> clearCurrentSession() async {
    _currentSession = null;
    _lastShotCounter = -1;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentSessionIdKey);

    notifyListeners();
  }

  /// Record a new shot with the given velocity.
  ///
  /// Called internally when a new shot is detected from device broadcasts.
  /// [previousCounter] is the counter value before this shot, used for revert on failure.
  /// Returns true if shot was successfully recorded and persisted.
  Future<bool> _recordShot(int velocityFps, int previousCounter) async {
    // Prevent concurrent recording (could happen with rapid broadcasts)
    if (_isRecordingShot) {
      debugPrint('Warning: Shot recording already in progress, skipping');
      // Revert counter so this shot can be retried
      _lastShotCounter = previousCounter;
      return false;
    }

    _isRecordingShot = true;
    try {
      if (_currentSession == null) {
        // Auto-start session on first shot
        await startNewSession();
      }

      // Add shot to session
      final previousSession = _currentSession;
      _currentSession = _currentSession!.addShot(velocityFps);

      // Auto-save session after each shot
      final saved = await SessionStorage.saveSession(_currentSession!);

      if (!saved) {
        // Persistence failed - revert session state AND counter
        debugPrint('Warning: Failed to persist shot, reverting state');
        _currentSession = previousSession;
        _lastShotCounter = previousCounter;
        notifyListeners(); // Notify to remove ghost shot from UI
        return false;
      }

      // Refresh saved sessions list so history page shows updates
      await _loadSavedSessions();

      notifyListeners();
      return true;
    } finally {
      _isRecordingShot = false;
    }
  }

  /// Record a shot manually (for demo/testing purposes).
  ///
  /// Unlike _recordShot which is called from BLE broadcasts,
  /// this method doesn't track shot counters.
  Future<bool> recordShot(int velocityFps) async {
    return _recordShot(velocityFps, -1);
  }

  /// Delete a saved session by ID.
  Future<void> deleteSession(String sessionId) async {
    await SessionStorage.deleteSession(sessionId);
    await _loadSavedSessions();
  }

  /// Get a saved session by ID.
  Session? getSavedSession(String sessionId) {
    try {
      return _savedSessions.firstWhere((s) => s.id == sessionId);
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // Device Connection (via Broadcasts)
  // ============================================================

  /// Set scanning state.
  void setScanning(bool scanning) {
    _isScanning = scanning;
    notifyListeners();
  }

  /// Process a broadcast data packet from a scan result.
  ///
  /// This is called from the BLE scanning code when a valid chronograph
  /// broadcast is detected.
  ///
  /// [remoteId] - Bluetooth device ID
  /// [name] - Device name from advertisement
  /// [rssi] - Signal strength
  /// [broadcastData] - Parsed broadcast data
  void processBroadcast(
    String remoteId,
    String name,
    int rssi,
    BroadcastData broadcastData,
  ) {
    if (!broadcastData.isValid) return;

    // Check if this is a different device or device was lost
    final isDeviceChange = _lastDeviceId != null && _lastDeviceId != remoteId;
    final wasLost = _connectedDevice?.isLost ?? false;

    // Update connected device info
    _connectedDevice = ChronographDevice(
      remoteId: remoteId,
      name: name.isNotEmpty ? name : broadcastData.deviceName,
      deviceType: broadcastData.uuidVersion == 4
          ? ChronographDeviceType.pocketD1
          : ChronographDeviceType.pocketV2,
      rssi: rssi,
      batteryPercent: broadcastData.batteryPercent,
      signalStrength: broadcastData.signalStrength,
      lastSeen: DateTime.now(),
    );

    // Ensure device loss timer is running (creates once, checks every second)
    _ensureDeviceLossTimer();

    // Reset shot counter sync on device change or after device was lost
    // This prevents false shots when switching devices or after reconnection
    if (isDeviceChange || wasLost) {
      _lastShotCounter = -1;
    }
    _lastDeviceId = remoteId;

    // Detect new shot by shot counter change
    // Note: If no session exists, _recordShot will auto-start one
    final newCounter = broadcastData.shotCounter;
    if (_lastShotCounter >= 0 && broadcastData.velocityFps > 0) {
      final counterDelta = newCounter - _lastShotCounter;

      // Determine if this is a valid shot:
      // - counterDelta > 0: normal increment (1 or more shots)
      // - 16-bit counter wrap: previous counter near max AND new counter small
      // - Any other negative delta: device reset/reboot, skip recording
      //
      // Wrap detection: Only treat as wrap if previous counter was >= 65000
      // AND new counter is < 1000. This prevents ghost shots from device
      // reboots (e.g., 50000 -> 0 is a reset, not a wrap).
      //
      // Note: If counter jumps by >1, we record only 1 shot since we only
      // have velocity for the current broadcast. Missed shots are logged.
      final isWrap = _lastShotCounter >= 65000 && newCounter < 1000;
      final isValidShot = counterDelta > 0 || isWrap;

      if (isValidShot) {
        if (counterDelta > 1) {
          debugPrint('Warning: Shot counter jumped by $counterDelta, '
              'recording 1 shot (missing velocity for ${counterDelta - 1} shots)');
        }

        // Optimistically update counter IMMEDIATELY to prevent duplicate shots
        // from repeated advertisements while async save is in progress
        final previousCounter = _lastShotCounter;
        _lastShotCounter = newCounter;

        // Record shot async - will revert counter on failure
        _recordShot(broadcastData.velocityFps, previousCounter).catchError((error) {
          debugPrint('Error recording shot: $error');
          // Revert counter so next broadcast can retry
          _lastShotCounter = previousCounter;
          notifyListeners();
          return false; // Return value for catchError
        });

        // Notify with optimistic state (shot added, counter updated)
        notifyListeners();
        return;
      }
      // Small negative delta: device reset - just sync counter below
    }

    // Update shot counter (initial sync or device reset)
    _lastShotCounter = newCounter;

    notifyListeners();
  }

  /// Ensure the device loss timer is running. Called on each broadcast.
  void _ensureDeviceLossTimer() {
    // Clear lost timestamp - device is back
    _deviceLostAt = null;

    // Only create timer if not already running
    if (_deviceLossTimer == null || !_deviceLossTimer!.isActive) {
      _deviceLossTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _checkDeviceLoss(),
      );
    }
  }

  /// Check if device is lost and notify listeners.
  void _checkDeviceLoss() {
    final device = _connectedDevice;
    if (device == null) {
      _deviceLossTimer?.cancel();
      _deviceLossTimer = null;
      return;
    }

    final isLost = device.isLost;

    // Track when device was first lost
    if (isLost && _deviceLostAt == null) {
      _deviceLostAt = DateTime.now();
    }

    // Notify listeners so UI updates
    if (isLost) {
      notifyListeners();
    }
  }

  /// Disconnect from device (stop tracking broadcasts).
  void disconnectDevice() {
    _deviceLossTimer?.cancel();
    _deviceLossTimer = null;
    _connectedDevice = null;
    _lastShotCounter = -1;
    _lastDeviceId = null;
    _deviceLostAt = null;
    notifyListeners();
  }

  /// Clean up resources. Call when AppState is no longer needed.
  @override
  void dispose() {
    _deviceLossTimer?.cancel();
    _deviceLossTimer = null;
    super.dispose();
  }

  /// Set last connected device ID (persisted for auto-reconnect).
  /// Pass null to clear the saved device ID.
  Future<void> setLastConnectedDeviceId(String? deviceId) async {
    _lastConnectedDeviceId = deviceId;
    final prefs = await SharedPreferences.getInstance();
    if (deviceId != null) {
      await prefs.setString(_lastConnectedDeviceIdKey, deviceId);
    } else {
      await prefs.remove(_lastConnectedDeviceIdKey);
    }
  }

  // ============================================================
  // Preference Methods
  // ============================================================

  /// Set bullet weight in grains.
  Future<void> setBulletWeight(double grains) async {
    _bulletWeightGrains = grains.clamp(1.0, 1000.0);

    // Update current session if one exists
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        bulletWeightGrains: _bulletWeightGrains,
      );
      await SessionStorage.saveSession(_currentSession!);
    }

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_bulletWeightKey, _bulletWeightGrains);
  }

  /// Toggle velocity unit (FPS / m/s).
  Future<void> toggleVelocityUnit() async {
    _useFps = !_useFps;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useFpsKey, _useFps);
  }

  /// Toggle energy unit (ft-lbs / Joules).
  Future<void> toggleEnergyUnit() async {
    _useFtLbs = !_useFtLbs;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useFtLbsKey, _useFtLbs);
  }

  // ============================================================
  // Formatting Helpers
  // ============================================================

  /// Format velocity for display based on current unit preference.
  String formatVelocity(int fps) {
    if (_useFps) {
      return fps.toString();
    } else {
      return (fps * 0.3048).toStringAsFixed(0);
    }
  }

  /// Format average velocity for display.
  String formatAverageVelocity(double avgFps) {
    if (_useFps) {
      return avgFps.toStringAsFixed(0);
    } else {
      return (avgFps * 0.3048).toStringAsFixed(0);
    }
  }

  /// Format extreme spread for display.
  String formatExtremeSpread(int esFps) {
    if (_useFps) {
      return esFps.toString();
    } else {
      return (esFps * 0.3048).toStringAsFixed(0);
    }
  }

  /// Format standard deviation for display.
  String formatStandardDeviation(double sdFps) {
    if (_useFps) {
      return sdFps.toStringAsFixed(1);
    } else {
      return (sdFps * 0.3048).toStringAsFixed(1);
    }
  }

  /// Format energy for display based on current unit preference.
  String formatEnergy(int fps) {
    if (_useFtLbs) {
      final ftLbs = (_bulletWeightGrains * fps * fps) / 450240.0;
      return ftLbs.toStringAsFixed(1);
    } else {
      final grams = _bulletWeightGrains * 0.0648;
      final ms = fps * 0.3048;
      final joules = (grams * ms * ms) / 2000.0;
      return joules.toStringAsFixed(1);
    }
  }

  /// Get velocity unit label.
  String get velocityUnitLabel => _useFps ? 'fps' : 'm/s';

  /// Get energy unit label.
  String get energyUnitLabel => _useFtLbs ? 'ft-lbs' : 'J';
}
