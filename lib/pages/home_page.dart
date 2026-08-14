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
import '../services/pocket_pro_client.dart';
import '../services/true_ballistic_client.dart';
import '../models/chronograph_device.dart';
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

  // Pocket Pro and True Ballistic are GATT-connected (not broadcast) so
  // each gets its own client. At most one link is active at a time; the
  // streams are wired into AppState and the client owns the
  // BluetoothDevice connection.
  final PocketProClient _pocketProClient = PocketProClient();
  final TrueBallisticClient _trueBallisticClient = TrueBallisticClient();
  StreamSubscription? _gattShotSub;
  StreamSubscription<BluetoothConnectionState>? _gattConnectionSub;
  // Device type per remoteId for adverts we've identified as GATT
  // chronographs, so the selection callback can tell them from
  // broadcast devices without re-running advert parsing.
  final Map<String, ChronographDeviceType> _gattDeviceKinds =
      <String, ChronographDeviceType>{};

  /// Monotonic id for GATT connect attempts. Setup spans several awaits,
  /// so a disconnect or a switch to another device mid-setup must be able
  /// to invalidate the attempt already in flight — otherwise it resumes
  /// after the teardown it was supposed to lose to, and wires its streams
  /// (or connects) against a device the user has moved on from.
  int _gattAttemptSeq = 0;

  /// True while either GATT chronograph link is up or being established.
  bool get _gattBusy =>
      _pocketProClient.isConnected ||
      _pocketProClient.isConnecting ||
      _trueBallisticClient.isConnected ||
      _trueBallisticClient.isConnecting;

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
    _gattShotSub?.cancel();
    _gattConnectionSub?.cancel();
    _pocketProClient.dispose();
    _trueBallisticClient.dispose();
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterBluePlus.stopScan();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    // Drop the Pocket Pro GATT link as soon as the user backgrounds (or
    // hides) the app — saves battery on both phone and chronograph and
    // avoids a stale "connected" status when we resume. The resume
    // branch below re-establishes it via the scan / advert path.
    //
    // `inactive` deliberately excluded: on iOS it fires for tiny
    // transitions (notification banner, Control Center peek) and
    // disconnecting on each would thrash the link.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_gattBusy) {
        _disconnectGattChrono();
      }
      return;
    }

    // iOS pauses BLE scans when backgrounded (we have no service UUID to
    // filter by, so we can't run in the background). Android can throttle
    // long-running scans to opportunistic mode. On resume, restart the scan
    // unless the user explicitly paused it via Disconnect/Forget — or a
    // Pocket Pro GATT link is up, which deliberately keeps the scan off.
    if (state == AppLifecycleState.resumed &&
        !_userPausedScan &&
        !_gattBusy) {
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
      // A live GATT chronograph link deliberately keeps the scan off —
      // concurrent scan + GATT degrades both on Android. The link-drop
      // handler restarts the scan when the connection goes away.
      if (_gattBusy) return;
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

    final deviceId = result.device.remoteId.str;
    final advData = result.advertisementData;
    final localName = advData.advName.isNotEmpty
        ? advData.advName
        : result.device.platformName;

    final nordicData = advData.manufacturerData[0x0059];
    final isBroadcastPocket =
        nordicData != null && BroadcastParser.isPocketDevice(nordicData);
    // Pocket Pro doesn't use manufacturer data — it advertises the VRS
    // service UUID (and/or an "FX Pocket Pro" local name).
    final isPocketPro = BroadcastParser.isPocketProAdvertisement(
      serviceUuids: advData.serviceUuids.map((g) => g.str.toLowerCase()),
      localName: localName,
    );
    // True Ballistic doesn't advertise its data service — it's matched
    // by the vendor's obfuscated name prefix.
    final isTrueBallistic = !isPocketPro &&
        TrueBallisticClient.matchesAd(
          advData.serviceUuids.map((g) => g.str.toLowerCase()),
          localName,
        );

    if (isBroadcastPocket) {
      final broadcastData = BroadcastParser.parse(nordicData);
      if (!broadcastData.isValid) return;

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

      _upsertScanResult(result);
    } else if (isPocketPro || isTrueBallistic) {
      final kind = isPocketPro
          ? ChronographDeviceType.pocketPro
          : ChronographDeviceType.trueBallistic;
      _gattDeviceKinds[deviceId] = kind;
      final appState = context.read<AppState>();

      // Unlike V2/D1 (passive broadcast listening), a GATT connection
      // occupies the chronograph itself — so these devices are only
      // listed in the pairing drawer until the user explicitly picks
      // one there. Auto-connect fires solely for the device the user
      // already selected, this session or persisted from a previous one.
      final targetDeviceId =
          _selectedDeviceId ?? appState.lastConnectedDeviceId;
      final shouldAutoConnect =
          targetDeviceId == deviceId && !_gattBusy;

      if (shouldAutoConnect) {
        // Reconnecting to the saved device on a fresh launch — adopt
        // it as this session's selection so the drawer reflects it.
        _selectedDeviceId ??= deviceId;
        _connectGattChrono(deviceId, _gattDisplayName(kind, localName), kind);
      }

      _upsertScanResult(result);
    }
  }

  /// Display name for a GATT chronograph. The True Ballistic advertises
  /// an obfuscated vendor string ("vXfS3c6k…") that would be noise in
  /// the UI — substitute the product name.
  static String _gattDisplayName(ChronographDeviceType kind, String advName) {
    if (kind == ChronographDeviceType.trueBallistic) {
      return 'FX True Ballistic';
    }
    return advName;
  }

  /// Replace, don't just append — otherwise a device that goes silent
  /// keeps its stale RSSI and timestamp in the list forever. Consumers
  /// filter by ScanResult.timeStamp to decide which entries are still
  /// in range.
  void _upsertScanResult(ScanResult result) {
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

  // ============= GATT CHRONOGRAPHS (Pocket Pro / True Ballistic) =============

  /// Establish a GATT link to a connected-type chronograph, wire its
  /// shot stream into AppState, and stop the BLE scan (concurrent scan
  /// + GATT degrades both on Android).
  ///
  /// Silent by design: failures are logged and the scan restarts so
  /// the next advertisement retries — no error UI.
  Future<void> _connectGattChrono(
    String deviceId,
    String name,
    ChronographDeviceType kind,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final isTb = kind == ChronographDeviceType.trueBallistic;
    final alreadyConnected = isTb
        ? _trueBallisticClient.isConnected &&
            _trueBallisticClient.remoteId == deviceId
        : _pocketProClient.isConnected &&
            _pocketProClient.remoteId == deviceId;
    if (alreadyConnected) return;

    // Claim this attempt. Any later connect or disconnect bumps the
    // sequence, and the `stale` checks after each await below make this
    // attempt abandon itself rather than race the newer one.
    final attempt = ++_gattAttemptSeq;
    bool stale() => !mounted || attempt != _gattAttemptSeq;

    final appState = context.read<AppState>();
    appState.setGattConnected(
      true,
      remoteId: deviceId,
      name: name,
      deviceType: kind,
    );

    // Stop the broadcast scan while GATT is up. Unlike _stopScan this
    // is not a user-paused state — the watchdog stays parked because it
    // checks the clients' connection state, and the link-drop handler
    // below restarts the scan when the connection goes away.
    //
    // Awaited: stopScan can sit on the scan mutex or the platform
    // channel, and connecting while the radio is still scanning is
    // exactly what this is meant to prevent on Android.
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {
      // No active scan; ignore.
    }
    if (stale()) return;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    appState.setScanning(false);

    // Wire streams (cancel any previous wiring first).
    await _gattShotSub?.cancel();
    await _gattConnectionSub?.cancel();
    if (stale()) return;

    if (isTb) {
      _gattShotSub = _trueBallisticClient.shotStream.listen((shot) {
        if (stale()) return;
        context.read<AppState>().processGattVelocity(
              remoteId: deviceId,
              name: name,
              fps: shot.velocityFps.round(),
              deviceType: kind,
              batteryPercent: _trueBallisticClient.batteryPercent,
              firmwareVersion: _trueBallisticClient.firmwareVersion,
            );
      });
    } else {
      _gattShotSub = _pocketProClient.velocityStream.listen((v) {
        if (stale()) return;
        context.read<AppState>().processGattVelocity(
              remoteId: deviceId,
              name: name,
              fps: v.velocityFps.round(),
              deviceType: kind,
            );
      });
    }

    // Track whether this connect attempt has ever reached `connected`.
    // BluetoothDevice.connectionState replays its current value on
    // subscribe, which is `disconnected` before connect() completes —
    // we must not treat that initial emission as a dropped link, or
    // we'd restart the scan we just stopped and re-enter the connect
    // flow on the next advert.
    var everConnected = false;
    final connectionStream = isTb
        ? _trueBallisticClient.connectionStateStream
        : _pocketProClient.connectionStateStream;
    _gattConnectionSub = connectionStream.listen((state) {
      if (stale()) return;
      final connected = state == BluetoothConnectionState.connected;
      if (connected) everConnected = true;
      context.read<AppState>().setGattConnected(
            connected,
            remoteId: connected ? deviceId : null,
            name: connected ? name : null,
            deviceType: kind,
          );
      if (!connected && everConnected) {
        // Link dropped after we'd reached connected at least once —
        // restart the broadcast scan so we can rediscover the device
        // when it comes back, and let the existing reconnecting → lost
        // timeout flow surface the recovery UI.
        _startScan();
      }
    });

    try {
      final device = BluetoothDevice.fromId(deviceId);
      if (isTb) {
        await _trueBallisticClient.connect(device);
        if (stale()) return;
        // Battery and firmware were read once during discovery — push
        // them onto the connected-device card now rather than waiting
        // for the first shot.
        context.read<AppState>().updateGattDeviceInfo(
              batteryPercent: _trueBallisticClient.batteryPercent,
              firmwareVersion: _trueBallisticClient.firmwareVersion,
            );
      } else {
        await _pocketProClient.connect(device);
      }
    } on StateError catch (e) {
      // Permanent validation failure — the clients throw StateError only
      // when a connected device turns out not to expose the expected
      // chronograph service/characteristic (e.g. a device that matched
      // the True Ballistic name prefix by accident). Keeping it selected
      // and persisted would silently retry it on every advertisement and
      // every future launch, so forget it entirely.
      debugPrint('GATT chronograph rejected: $e');
      // A newer attempt owns the state now — it must not be clobbered
      // by this abandoned one's error handling.
      if (stale()) return;
      if (_selectedDeviceId == deviceId) {
        setState(() => _selectedDeviceId = null);
      }
      if (appState.lastConnectedDeviceId == deviceId) {
        appState.setLastConnectedDeviceId(null);
      }
      // Clears the placeholder device and the GATT flag in one go, so
      // the status pill doesn't sit in "reconnecting" toward a device
      // that can never work.
      appState.disconnectDevice();
      _startScan();
    } catch (e) {
      debugPrint('GATT chronograph connect failed: $e');
      if (stale()) return;
      appState.setGattConnected(false);
      // Transient failure (out of range, link flap) — resume scanning
      // so the next advertisement retries.
      _startScan();
    }
  }

  /// Tear down any GATT chronograph link and clear AppState's
  /// GATT-connected flag. Safe to call when not connected.
  Future<void> _disconnectGattChrono() async {
    // Invalidate any connect attempt still working through its awaits,
    // so it can't resume and re-wire streams after this teardown.
    _gattAttemptSeq++;
    await _gattShotSub?.cancel();
    _gattShotSub = null;
    await _gattConnectionSub?.cancel();
    _gattConnectionSub = null;
    await _pocketProClient.disconnect();
    await _trueBallisticClient.disconnect();
    if (!mounted) return;
    context.read<AppState>().setGattConnected(false);
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
          isDeviceLost: appState.isDeviceLost,
          onStartScan: _startScan,
          onStopScan: _stopScan,
          onSelectDevice: (deviceId) async {
            final gattKind = _gattDeviceKinds[deviceId];
            String? gattName;
            if (gattKind != null) {
              for (final r in _scanResults) {
                if (r.device.remoteId.str == deviceId) {
                  gattName = _gattDisplayName(
                    gattKind,
                    r.advertisementData.advName.isNotEmpty
                        ? r.advertisementData.advName
                        : r.device.platformName,
                  );
                  break;
                }
              }
            }
            setState(() {
              _selectedDeviceId = deviceId;
            });
            appState.setLastConnectedDeviceId(deviceId);
            Navigator.pop(sheetCtx);
            // Release any existing GATT link before switching devices.
            await _disconnectGattChrono();
            if (gattKind != null && mounted) {
              await _connectGattChrono(deviceId, gattName ?? '', gattKind);
            } else if (gattKind == null && mounted && !appState.isScanning) {
              // Switching from a GATT chronograph (whose link had
              // stopped the scan) to a broadcast device — restart the
              // scan or the V2/D1 can never deliver data. Reuse the
              // appState captured above: sheetCtx is deactivated once
              // the pop animation finishes.
              _startScan();
            }
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
      _gattDeviceKinds.clear();
      _userPausedScan = true;
    });
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterBluePlus.stopScan();
    }
    appState.setScanning(false);
    appState.disconnectDevice();
    // Tear down any GATT chronograph link as well — disconnectDevice
    // only clears AppState's view of it, not the platform connection.
    _disconnectGattChrono();
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
                    isConnected: appState.isConnected,
                    isLost: appState.isDeviceLost,
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
