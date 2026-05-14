import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/weight_input.dart';
import '../services/broadcast_parser.dart';
import '../models/broadcast_data.dart';
import '../utils/responsive.dart';
import '../config/app_config.dart';
import '../utils/demo_velocity_generator.dart';
import 'session_history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // BLE scanning
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _deviceLossTimer;

  // Track selected device for filtering broadcasts
  String? _selectedDeviceId;

  // Demo mode
  final DemoVelocityGenerator? _demoGenerator =
      AppConfig.kDemoMode ? DemoVelocityGenerator() : null;

  @override
  void initState() {
    super.initState();
    _startDeviceLossTimer();
    // Auto-start scanning after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _deviceLossTimer?.cancel();
    if (Platform.isAndroid || Platform.isIOS) {
      FlutterBluePlus.stopScan();
    }
    super.dispose();
  }

  // ==================== DEVICE LOSS DETECTION ====================

  void _startDeviceLossTimer() {
    _deviceLossTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        // AppState handles device loss detection via lastSeen timestamp
        // This timer just triggers UI updates to show lost state
        if (mounted) {
          final appState = context.read<AppState>();
          if (appState.isDeviceLost) {
            setState(() {});
          }
        }
      },
    );
  }

  // ==================== BLE SCANNING ====================

  Future<void> _startScan() async {
    // BLE scanning only supported on mobile platforms
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint('BLE scanning not supported on this platform');
      return;
    }

    // Request permissions
    if (Platform.isAndroid) {
      final locationStatus = await Permission.locationWhenInUse.request();
      final bluetoothScan = await Permission.bluetoothScan.request();
      final bluetoothConnect = await Permission.bluetoothConnect.request();

      if (!mounted) return;

      if (locationStatus != PermissionStatus.granted ||
          bluetoothScan != PermissionStatus.granted ||
          bluetoothConnect != PermissionStatus.granted) {
        _showPermissionError();
        return;
      }
    } else if (Platform.isIOS) {
      final bluetoothStatus = await Permission.bluetooth.request();

      if (!mounted) return;

      if (bluetoothStatus != PermissionStatus.granted) {
        _showPermissionError();
        return;
      }
    }

    // Check if Bluetooth is on (wait for definitive state, not unknown)
    final adapterState = await FlutterBluePlus.adapterState
        .firstWhere((state) => state != BluetoothAdapterState.unknown)
        .timeout(
          const Duration(seconds: 3),
          onTimeout: () => BluetoothAdapterState.unknown,
        );
    if (!mounted) return;

    if (adapterState != BluetoothAdapterState.on) {
      _showBluetoothOffError();
      return;
    }

    final appState = context.read<AppState>();
    appState.setScanning(true);
    _scanResults.clear();

    // Cancel any existing subscription
    await _scanSubscription?.cancel();

    // Start listening to scan results
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

    // Start scanning with continuous updates to receive repeated advertisements
    // No timeout - scan runs until explicitly stopped or app closes
    await FlutterBluePlus.startScan(
      continuousUpdates: true,
    );
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    context.read<AppState>().setScanning(false);
  }

  void _processScanResult(ScanResult result) {
    // Check if this is a fresh advertisement (received within last 3 seconds)
    final msSinceAdvert = DateTime.now().difference(result.timeStamp).inMilliseconds;
    if (msSinceAdvert > 3000) {
      // Stale cached advertisement, ignore
      return;
    }

    // Check for Nordic manufacturer data (company ID 0x0059)
    final manufacturerData = result.advertisementData.manufacturerData;
    final nordicData = manufacturerData[0x0059];

    if (nordicData != null && BroadcastParser.isPocketDevice(nordicData)) {
      // Parse the broadcast data
      final broadcastData = BroadcastParser.parse(nordicData);

      if (broadcastData.isValid) {
        final deviceId = result.device.remoteId.str;
        final appState = context.read<AppState>();

        // Determine which device to connect to:
        // 1. If we have a selected device, only connect to that one
        // 2. If no selection yet, prefer the saved device ID from last session
        // 3. If no saved device, auto-select this one (first valid device)
        final savedDeviceId = appState.lastConnectedDeviceId;
        final targetDeviceId = _selectedDeviceId ?? savedDeviceId;
        final shouldConnect = targetDeviceId == null || targetDeviceId == deviceId;

        if (shouldConnect) {
          // Process the broadcast in AppState
          appState.processBroadcast(
            deviceId,
            result.device.platformName,
            result.rssi,
            broadcastData,
          );

          // Auto-select and save device ID only when it changes
          if (_selectedDeviceId == null) {
            _selectedDeviceId = deviceId;
            // Save the connected device ID for auto-reconnect (only on new selection)
            if (savedDeviceId != deviceId) {
              appState.setLastConnectedDeviceId(deviceId);
            }
          }
        }

        // Add to scan results for device list
        if (!_scanResults.any((r) => r.device.remoteId == result.device.remoteId)) {
          setState(() {
            _scanResults.add(result);
          });
        }
      }
    }
  }

  void _showPermissionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bluetooth and location permissions are required'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showBluetoothOffError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please turn on Bluetooth'),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  // ==================== DEVICE DRAWER ====================

  void _showDeviceDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _DeviceDrawer(
        scanResults: _scanResults,
        isScanning: context.watch<AppState>().isScanning,
        selectedDeviceId: _selectedDeviceId,
        onStartScan: _startScan,
        onStopScan: _stopScan,
        onSelectDevice: (deviceId) {
          setState(() {
            _selectedDeviceId = deviceId;
          });
          // Save the selected device ID for auto-reconnect
          context.read<AppState>().setLastConnectedDeviceId(deviceId);
          Navigator.pop(context);
        },
        onDisconnect: () {
          setState(() {
            _selectedDeviceId = null;
            _scanResults.clear();
          });
          final appState = context.read<AppState>();
          appState.disconnectDevice();
          // Clear saved device ID on explicit disconnect
          appState.setLastConnectedDeviceId(null);
          Navigator.pop(context);
        },
      ),
    );
  }

  // ==================== WEIGHT DIALOG ====================

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

  // ==================== NEW SESSION CONFIRMATION ====================

  void _confirmNewSession(AppState appState) {
    // Skip confirmation if current session is empty
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

  // ==================== DEMO MODE ====================

  void _recordDemoShot(AppState appState) {
    if (_demoGenerator == null) return;
    final velocity = _demoGenerator!.generateVelocity();
    appState.recordShot(velocity);
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isCompact = Responsive.isCompact(context);
    final listMaxHeight = isCompact ? 160.0 : 220.0;
    final heroSpacing = isCompact ? 16.0 : 24.0;
    final statSpacing = isCompact ? 12.0 : 16.0;
    final buttonSpacing = isCompact ? 8.0 : 12.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Device Status Bar
            DeviceStatusBar(
              device: appState.connectedDevice,
              isScanning: appState.isScanning,
              isReconnecting: appState.isDeviceLost && _selectedDeviceId != null,
              isTimedOut: appState.isReconnectTimedOut,
              onTap: _showDeviceDrawer,
            ),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    SizedBox(height: heroSpacing),

                    // Large velocity display
                    VelocityDisplay(
                      value: appState.lastVelocityFps > 0
                          ? appState.formatVelocity(appState.lastVelocityFps)
                          : '',
                      unit: appState.velocityUnitLabel,
                      isConnected: appState.isConnected,
                      onTap: () => appState.toggleVelocityUnit(),
                    ),

                    // Energy display with weight icon
                    EnergyDisplay(
                      value: appState.lastVelocityFps > 0
                          ? appState.formatEnergy(appState.lastVelocityFps)
                          : '',
                      unit: appState.energyUnitLabel,
                      onTap: () => appState.toggleEnergyUnit(),
                      onWeightTap: _showWeightDialog,
                    ),

                    SizedBox(height: heroSpacing),

                    // Statistics row
                    StatisticsRow(
                      average: appState.formatAverageVelocity(appState.averageFps),
                      extremeSpread: appState.formatExtremeSpread(appState.extremeSpreadFps),
                      standardDeviation: appState.formatStandardDeviation(appState.standardDeviationFps),
                      unit: appState.velocityUnitLabel,
                      showStats: appState.hasStatistics,
                      shotCount: appState.shotCount,
                    ),

                    SizedBox(height: statSpacing),

                    // Shot count indicator
                    if (appState.hasActiveSession) ...[
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 10 : 12,
                          vertical: isCompact ? 5 : 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${appState.shotCount} shot${appState.shotCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      SizedBox(height: statSpacing),
                    ],

                    // Shot history list
                    Container(
                      constraints: BoxConstraints(maxHeight: listMaxHeight),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ShotList(
                          shots: appState.currentSession?.shots ?? [],
                          formatVelocity: appState.formatVelocity,
                          unit: appState.velocityUnitLabel,
                          maxHeight: listMaxHeight,
                        ),
                      ),
                    ),

                    SizedBox(height: heroSpacing),
                  ],
                ),
              ),
            ),

            // Bottom action bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Action buttons
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 360;
                      final spacing = isNarrow ? 8.0 : buttonSpacing;

                      final newSessionButton = ElevatedButton.icon(
                        onPressed: () => _confirmNewSession(appState),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('New Session'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.background,
                        ),
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
                        icon: const Icon(Icons.history, size: 20),
                        label: const Text('History'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          minimumSize: const Size.fromHeight(44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          side: const BorderSide(color: AppColors.border),
                        ),
                      );

                      // Demo button (only shown when kDemoMode is true)
                      Widget? demoButton;
                      if (AppConfig.kDemoMode && _demoGenerator != null) {
                        demoButton = OutlinedButton.icon(
                          onPressed: () => _recordDemoShot(appState),
                          icon: const Icon(Icons.science_outlined, size: 20),
                          label: const Text('Demo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.warning,
                            minimumSize: const Size.fromHeight(44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            side: const BorderSide(color: AppColors.warning),
                          ),
                        );
                      }

                      if (isNarrow) {
                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: newSessionButton,
                            ),
                            SizedBox(height: spacing),
                            SizedBox(
                              width: double.infinity,
                              child: historyButton,
                            ),
                            if (demoButton != null) ...[
                              SizedBox(height: spacing),
                              SizedBox(
                                width: double.infinity,
                                child: demoButton,
                              ),
                            ],
                          ],
                        );
                      }

                      // Wide layout
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== DEVICE DRAWER ====================

class _DeviceDrawer extends StatelessWidget {
  final List<ScanResult> scanResults;
  final bool isScanning;
  final String? selectedDeviceId;
  final VoidCallback onStartScan;
  final VoidCallback onStopScan;
  final ValueChanged<String> onSelectDevice;
  final VoidCallback onDisconnect;

  const _DeviceDrawer({
    required this.scanResults,
    required this.isScanning,
    required this.selectedDeviceId,
    required this.onStartScan,
    required this.onStopScan,
    required this.onSelectDevice,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Devices',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (selectedDeviceId != null)
                TextButton(
                  onPressed: onDisconnect,
                  child: const Text(
                    'Disconnect',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Scan button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isScanning ? onStopScan : onStartScan,
              icon: Icon(
                isScanning ? Icons.stop : Icons.bluetooth_searching,
                size: 20,
              ),
              label: Text(isScanning ? 'Stop Scanning' : 'Scan for Devices'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                backgroundColor:
                    isScanning ? AppColors.error : AppColors.primary,
                foregroundColor: AppColors.background,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Info text
          Text(
            'Scanning for Chrono Litegraph devices...',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),

          // Device list
          Expanded(
            child: scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isScanning
                              ? Icons.bluetooth_searching
                              : Icons.bluetooth_disabled,
                          size: 48,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isScanning
                              ? 'Scanning...'
                              : 'No devices found\nTap scan to search',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: scanResults.length,
                    itemBuilder: (context, index) {
                      final result = scanResults[index];
                      final isSelected =
                          result.device.remoteId.str == selectedDeviceId;

                      // Parse broadcast data for display
                      final nordicData =
                          result.advertisementData.manufacturerData[0x0059];
                      final broadcastData = nordicData != null
                          ? BroadcastParser.parse(nordicData)
                          : BroadcastData.invalid();

                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.success.withOpacity(0.15)
                                : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isSelected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth,
                            color: isSelected
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                        title: Text(
                          result.device.platformName.isNotEmpty
                              ? result.device.platformName
                              : broadcastData.deviceName,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          'RSSI: ${result.rssi} dBm • Battery: ${broadcastData.batteryPercent}%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                              )
                            : null,
                        onTap: () => onSelectDevice(result.device.remoteId.str),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
