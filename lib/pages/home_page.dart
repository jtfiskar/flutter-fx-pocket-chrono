import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/velocity_display.dart';
import '../widgets/energy_display.dart';
import '../widgets/statistics_row.dart';
import '../widgets/shot_list.dart';
import '../widgets/device_status_bar.dart';
import '../widgets/pairing_drawer.dart';
import '../widgets/trend_chart.dart';
import '../widgets/weight_input.dart';
import '../services/broadcast_parser.dart';
import '../utils/responsive.dart';
import '../config/app_config.dart';
import '../utils/demo_velocity_generator.dart';
import 'session_history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _deviceLossTimer;
  Timer? _scanWatchdog;

  String? _selectedDeviceId;

  /// True after explicit Disconnect/Forget/Stop, or when _startScan bails
  /// because permissions were denied or Bluetooth is off. Suppresses the
  /// watchdog and the lifecycle hook from silently restarting the radio
  /// (and re-prompting the user) until they tap Scan again.
  bool _userPausedScan = false;

  /// True while a [_startScan] call is awaiting permission or adapter
  /// state. Prevents the watchdog (and the resume hook) from re-entering
  /// _startScan while permission_handler/flutter_blue_plus calls are in
  /// flight, which can race or stack permission dialogs.
  bool _scanStarting = false;

  final DemoVelocityGenerator? _demoGenerator =
      AppConfig.kDemoMode ? DemoVelocityGenerator() : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDeviceLossTimer();
    _startScanWatchdog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanSubscription?.cancel();
    _deviceLossTimer?.cancel();
    _scanWatchdog?.cancel();
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterBluePlus.stopScan();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS pauses BLE scans when backgrounded (we have no service UUID to
    // filter by, so we can't run in the background). Android can throttle
    // long-running scans to opportunistic mode. On resume, restart the scan
    // unless the user explicitly paused it via Disconnect/Forget.
    if (state == AppLifecycleState.resumed &&
        !_userPausedScan &&
        mounted) {
      _startScan();
    }
  }

  void _startDeviceLossTimer() {
    _deviceLossTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          final appState = context.read<AppState>();
          if (appState.isDeviceLost) {
            setState(() {});
          }
        }
      },
    );
  }

  /// Periodically nudge the BLE radio back on if it has stopped while the
  /// user expects it to be running. Android throttles scans after roughly
  /// 30 minutes; flutter_blue_plus' isScanningNow goes false silently. We
  /// re-issue startScan when that happens.
  void _startScanWatchdog() {
    _scanWatchdog = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      if (_userPausedScan) return;
      // Don't trample an in-flight permission/adapter check. Otherwise the
      // watchdog can re-enter _startScan while the user is still looking
      // at the OS permission dialog from the initial call.
      if (_scanStarting) return;
      if (!(Platform.isAndroid || Platform.isIOS)) return;
      if (FlutterBluePlus.isScanningNow) return;
      debugPrint('Scan watchdog: radio idle while we want it on — restarting');
      _startScan();
    });
  }

  Future<void> _startScan() async {
    // An in-flight call (permission dialog open, adapter check pending)
    // must not be re-entered — concurrent permission_handler/scan calls
    // can race.
    if (_scanStarting) return;
    _scanStarting = true;
    try {
      // Any explicit attempt to start the scan clears the paused flag so
      // the watchdog and lifecycle hook are allowed to keep it alive.
      _userPausedScan = false;
      if (!Platform.isAndroid && !Platform.isIOS) {
        debugPrint('BLE scanning not supported on this platform');
        return;
      }

      if (Platform.isAndroid) {
        final locationStatus = await Permission.locationWhenInUse.request();
        final bluetoothScan = await Permission.bluetoothScan.request();
        final bluetoothConnect = await Permission.bluetoothConnect.request();

        if (!mounted) return;

        if (locationStatus != PermissionStatus.granted ||
            bluetoothScan != PermissionStatus.granted ||
            bluetoothConnect != PermissionStatus.granted) {
          // Park the scan-paused flag so the watchdog and lifecycle hook
          // don't retry every 10 s and re-prompt the user. They re-arm by
          // tapping SCAN in the pairing drawer.
          _userPausedScan = true;
          _showPermissionError();
          return;
        }
      } else if (Platform.isIOS) {
        final bluetoothStatus = await Permission.bluetooth.request();
        if (!mounted) return;
        if (bluetoothStatus != PermissionStatus.granted) {
          _userPausedScan = true;
          _showPermissionError();
          return;
        }
      }

      final adapterState = await FlutterBluePlus.adapterState
          .firstWhere((state) => state != BluetoothAdapterState.unknown)
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => BluetoothAdapterState.unknown,
          );
      if (!mounted) return;

      if (adapterState != BluetoothAdapterState.on) {
        // Same reasoning as the permission branches above — bail out of the
        // watchdog cycle until the user explicitly re-arms scanning.
        _userPausedScan = true;
        _showBluetoothOffError();
        return;
      }

      final appState = context.read<AppState>();
      appState.setScanning(true);
      _scanResults.clear();

      await _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        (results) {
          for (final result in results) {
            _processScanResult(result);
          }
        },
        onError: (e) {
          debugPrint('Scan error: $e');
        },
      );

      await FlutterBluePlus.startScan(continuousUpdates: true);
    } finally {
      _scanStarting = false;
    }
  }

  void _stopScan() {
    // Explicit STOP from the drawer is a user-paused state — keep the
    // radio off until they tap SCAN again, even if the app is resumed
    // or the watchdog ticks.
    _userPausedScan = true;
    FlutterBluePlus.stopScan();
    context.read<AppState>().setScanning(false);
  }

  void _processScanResult(ScanResult result) {
    final msSinceAdvert =
        DateTime.now().difference(result.timeStamp).inMilliseconds;
    if (msSinceAdvert > 3000) return;

    final manufacturerData = result.advertisementData.manufacturerData;
    final nordicData = manufacturerData[0x0059];

    if (nordicData != null && BroadcastParser.isPocketDevice(nordicData)) {
      final broadcastData = BroadcastParser.parse(nordicData);

      if (broadcastData.isValid) {
        final deviceId = result.device.remoteId.str;
        final appState = context.read<AppState>();

        final savedDeviceId = appState.lastConnectedDeviceId;
        final targetDeviceId = _selectedDeviceId ?? savedDeviceId;
        final shouldConnect =
            targetDeviceId == null || targetDeviceId == deviceId;

        if (shouldConnect) {
          appState.processBroadcast(
            deviceId,
            result.device.platformName,
            result.rssi,
            broadcastData,
          );

          if (_selectedDeviceId == null) {
            _selectedDeviceId = deviceId;
            if (savedDeviceId != deviceId) {
              appState.setLastConnectedDeviceId(deviceId);
            }
          }
        }

        // Replace, don't just append — otherwise a device that goes silent
        // keeps its stale RSSI and timestamp in the list forever. Consumers
        // filter by ScanResult.timeStamp to decide which entries are still
        // in range.
        final existingIndex = _scanResults
            .indexWhere((r) => r.device.remoteId == result.device.remoteId);
        setState(() {
          if (existingIndex >= 0) {
            _scanResults[existingIndex] = result;
          } else {
            _scanResults.add(result);
          }
        });
      }
    }
  }

  void _showPermissionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bluetooth and location permissions are required'),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  void _showBluetoothOffError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please turn on Bluetooth'),
        backgroundColor: AppColors.warn,
      ),
    );
  }

  void _showDeviceDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      isScrollControlled: true,
      builder: (sheetCtx) {
        final appState = sheetCtx.watch<AppState>();
        return PairingDrawer(
          scanResults: _scanResults,
          isScanning: appState.isScanning,
          selectedDeviceId: _selectedDeviceId,
          savedDeviceId: appState.lastConnectedDeviceId,
          connectedDevice: appState.connectedDevice,
          onStartScan: _startScan,
          onStopScan: _stopScan,
          onSelectDevice: (deviceId) {
            setState(() {
              _selectedDeviceId = deviceId;
            });
            appState.setLastConnectedDeviceId(deviceId);
            Navigator.pop(sheetCtx);
          },
          onDisconnect: () {
            _disconnectAndPauseScan(appState);
            Navigator.pop(sheetCtx);
          },
          onForget: () {
            _disconnectAndPauseScan(appState);
            appState.setLastConnectedDeviceId(null);
            Navigator.pop(sheetCtx);
          },
        );
      },
    );
  }

  /// The real Disconnect — stop the BLE radio AND clear connected state.
  /// Without stopping the scan, _processScanResult would re-pair to the
  /// very next advertisement and the user would never see "disconnected".
  ///
  /// _userPausedScan = true tells the watchdog and the lifecycle hook to
  /// leave the radio off until the user explicitly taps SCAN again.
  void _disconnectAndPauseScan(AppState appState) {
    setState(() {
      _selectedDeviceId = null;
      _scanResults.clear();
      _userPausedScan = true;
    });
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterBluePlus.stopScan();
    }
    appState.setScanning(false);
    appState.disconnectDevice();
  }

  void _showWeightDialog() {
    final appState = context.read<AppState>();
    showDialog(
      context: context,
      builder: (context) => WeightInputDialog(
        initialGrains: appState.bulletWeightGrains,
        onConfirm: (grains) => appState.setBulletWeight(grains),
      ),
    );
  }

  void _confirmNewSession(AppState appState) {
    if (!appState.hasActiveSession || appState.shotCount == 0) {
      appState.startNewSession();
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Start New Session?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Current session will be saved with ${appState.shotCount} shots.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              appState.startNewSession();
            },
            child: const Text('Start New'),
          ),
        ],
      ),
    );
  }

  void _recordDemoShot(AppState appState) {
    if (_demoGenerator == null) return;
    final velocity = _demoGenerator!.generateVelocity();
    appState.recordShot(velocity);
  }

  String _altVelocity(AppState appState) {
    final fps = appState.lastVelocityFps;
    if (fps <= 0) return '';
    if (appState.useFps) {
      return (fps * 0.3048).toStringAsFixed(0);
    }
    return fps.toString();
  }

  String _ftLbsValue(AppState appState) {
    final fps = appState.lastVelocityFps;
    if (fps <= 0) return '';
    return ((appState.bulletWeightGrains * fps * fps) / 450240.0)
        .toStringAsFixed(1);
  }

  String _joulesValue(AppState appState) {
    final fps = appState.lastVelocityFps;
    if (fps <= 0) return '';
    final grams = appState.bulletWeightGrains * 0.0648;
    final ms = fps * 0.3048;
    return ((grams * ms * ms) / 2000.0).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isCompact = Responsive.isCompact(context);
    final listMaxHeight = isCompact ? 180.0 : 240.0;
    final blockGap = isCompact ? 12.0 : 14.0;
    final session = appState.currentSession;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top status row — BLE pill left, app brand right
            Padding(
              padding: EdgeInsets.fromLTRB(16, isCompact ? 8 : 12, 16,
                  isCompact ? 4 : 6),
              child: Row(
                children: [
                  DeviceStatusBar(
                    device: appState.connectedDevice,
                    isScanning: appState.isScanning,
                    isReconnecting:
                        appState.isDeviceLost && _selectedDeviceId != null,
                    isTimedOut: appState.isReconnectTimedOut,
                    onTap: _showDeviceDrawer,
                  ),
                  const Spacer(),
                  const Text(
                    'CHRONO',
                    style: TextStyle(
                      fontFamily: AppFonts.numerals,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LITE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding:
                    EdgeInsets.fromLTRB(16, isCompact ? 8 : 10, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VelocityDisplay(
                      primaryValue: appState.lastVelocityFps > 0
                          ? appState.formatVelocity(appState.lastVelocityFps)
                          : '',
                      primaryUnit: appState.velocityUnitLabel,
                      altValue: _altVelocity(appState),
                      altUnit: appState.useFps ? 'm/s' : 'fps',
                      shotIndex: appState.shotCount,
                      shotTotal: appState.shotCount,
                      isConnected: appState.isConnected,
                      hasShots: appState.shotCount > 0,
                      averageFps: appState.averageFps,
                      standardDeviationFps: appState.standardDeviationFps,
                      velocityFps: appState.lastVelocityFps,
                      useFps: appState.useFps,
                      onTap: () => appState.toggleVelocityUnit(),
                    ),
                    SizedBox(height: blockGap),
                    EnergyDisplay(
                      ftLbsValue: _ftLbsValue(appState),
                      joulesValue: _joulesValue(appState),
                      useFtLbs: appState.useFtLbs,
                      weightLabel:
                          '${appState.bulletWeightGrains.toStringAsFixed(1)}gr',
                      onTap: () => appState.toggleEnergyUnit(),
                      onWeightTap: _showWeightDialog,
                    ),

                    if (session != null && session.shots.isNotEmpty) ...[
                      SizedBox(height: blockGap),
                      Container(
                        padding: EdgeInsets.all(isCompact ? 12 : 14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8, left: 2),
                              child: Text(
                                'TREND',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textTertiary,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ),
                            TrendChart(
                              shots: session.shots,
                              meanFps: appState.averageFps,
                              sdFps: appState.standardDeviationFps,
                              useFps: appState.useFps,
                              unitLabel: appState.velocityUnitLabel,
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: blockGap),
                    StatisticsRow(
                      average: appState
                          .formatAverageVelocity(appState.averageFps),
                      extremeSpread: appState
                          .formatExtremeSpread(appState.extremeSpreadFps),
                      standardDeviation: appState
                          .formatStandardDeviation(appState.standardDeviationFps),
                      minValue: appState.formatVelocity(appState.minFps),
                      maxValue: appState.formatVelocity(appState.maxFps),
                      count: appState.shotCount,
                      unit: appState.velocityUnitLabel,
                      showStats: appState.hasStatistics,
                      shotCount: appState.shotCount,
                    ),

                    SizedBox(height: blockGap),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                            child: Row(
                              children: [
                                const Text(
                                  'RECENT SHOTS',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textTertiary,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const Spacer(),
                                if (appState.hasActiveSession)
                                  Text(
                                    '${appState.shotCount} total',
                                    style: const TextStyle(
                                      fontFamily: AppFonts.mono,
                                      fontSize: 10,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(13),
                              bottomRight: Radius.circular(13),
                            ),
                            child: ShotList(
                              shots: session?.shots ?? const [],
                              formatVelocity: appState.formatVelocity,
                              formatEnergy: appState.formatEnergy,
                              velocityUnit: appState.velocityUnitLabel,
                              energyUnit: appState.energyUnitLabel,
                              averageFps: appState.averageFps,
                              standardDeviationFps:
                                  appState.standardDeviationFps,
                              sessionStart: session?.createdAt,
                              useFps: appState.useFps,
                              maxHeight: listMaxHeight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom action bar
            Container(
              padding: EdgeInsets.fromLTRB(
                  16, 10, 16, isCompact ? 10 : 14),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 360;
                  final spacing = isNarrow ? 8.0 : 10.0;

                  final newSessionButton = ElevatedButton.icon(
                    onPressed: () => _confirmNewSession(appState),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('NEW'),
                  );
                  final historyButton = OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SessionHistoryPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('HISTORY'),
                  );
                  Widget? demoButton;
                  if (AppConfig.kDemoMode && _demoGenerator != null) {
                    demoButton = OutlinedButton.icon(
                      onPressed: () => _recordDemoShot(appState),
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: const Text('DEMO'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warn,
                        side: const BorderSide(color: AppColors.warn),
                      ),
                    );
                  }

                  if (isNarrow) {
                    return Column(
                      children: [
                        SizedBox(width: double.infinity, child: newSessionButton),
                        SizedBox(height: spacing),
                        SizedBox(width: double.infinity, child: historyButton),
                        if (demoButton != null) ...[
                          SizedBox(height: spacing),
                          SizedBox(width: double.infinity, child: demoButton),
                        ],
                      ],
                    );
                  }

                  if (demoButton != null) {
                    return Row(
                      children: [
                        Expanded(child: newSessionButton),
                        SizedBox(width: spacing),
                        Expanded(child: historyButton),
                        SizedBox(width: spacing),
                        Expanded(child: demoButton),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: newSessionButton),
                      SizedBox(width: spacing),
                      Expanded(child: historyButton),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
