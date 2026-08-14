import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/broadcast_data.dart';
import '../models/chronograph_device.dart';
import '../services/broadcast_parser.dart';
import '../services/true_ballistic_client.dart';
import '../theme/app_theme.dart';

/// Drawer-style device selector, launched as a modal bottom sheet from
/// the live screen. Shows the connected device (if any) with telemetry
/// the BLE advertising protocol actually exposes — battery, RSSI,
/// firmware — and a Nearby / Saved tab pair for switching device.
class PairingDrawer extends StatefulWidget {
  final List<ScanResult> scanResults;
  final bool isScanning;
  final String? selectedDeviceId;
  final String? savedDeviceId;
  final ChronographDevice? connectedDevice;

  /// Authoritative loss state from AppState — GATT-aware, unlike
  /// [ChronographDevice.isLost] which lags a dropped link by up to the
  /// 3 s lastSeen window. Drives the LIVE/STALE pill.
  final bool isDeviceLost;
  final VoidCallback onStartScan;
  final VoidCallback onStopScan;
  final ValueChanged<String> onSelectDevice;

  /// Stop using the currently-connected device. The handler in home_page
  /// also stops the BLE scan so no advertisement re-pairs immediately.
  /// Saved device id is preserved — to remove it use [onForget].
  final VoidCallback onDisconnect;

  /// Clear the saved device id (and disconnect if currently using it).
  /// After Forget there's nothing to auto-reconnect to on next Scan.
  final VoidCallback onForget;

  const PairingDrawer({
    super.key,
    required this.scanResults,
    required this.isScanning,
    required this.selectedDeviceId,
    required this.savedDeviceId,
    required this.connectedDevice,
    required this.isDeviceLost,
    required this.onStartScan,
    required this.onStopScan,
    required this.onSelectDevice,
    required this.onDisconnect,
    required this.onForget,
  });

  @override
  State<PairingDrawer> createState() => _PairingDrawerState();
}

enum _Tab { nearby, saved }

class _PairingDrawerState extends State<PairingDrawer> {
  _Tab _tab = _Tab.nearby;
  Timer? _refreshTicker;

  @override
  void initState() {
    super.initState();
    // When a device goes silent, AppState stops notifying — but the
    // freshness filters below depend on the wall clock. Tick every
    // second while the drawer is open so stale entries fall out of
    // the list and the IN-RANGE pill flips to OUT OF RANGE.
    _refreshTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: media.size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + media.padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 4, bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _header(),
            const SizedBox(height: 14),
            if (widget.connectedDevice != null) ...[
              _connectedCard(widget.connectedDevice!),
              const SizedBox(height: 14),
            ],
            _segments(),
            const SizedBox(height: 12),
            Flexible(
              child: _tab == _Tab.nearby ? _nearbyList() : _savedList(),
            ),
            const SizedBox(height: 10),
            _footerHint(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Text(
          'Devices',
          style: TextStyle(
            fontFamily: AppFonts.numerals,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.0,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 22),
          color: AppColors.textSecondary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _segments() {
    final hasSaved = widget.savedDeviceId != null;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _seg('Nearby', null, _tab == _Tab.nearby,
                () => setState(() => _tab = _Tab.nearby)),
          ),
          Expanded(
            // Only show the count badge once there's actually a saved device.
            // "Saved · 0" is noise.
            child: _seg('Saved', hasSaved ? 1 : null, _tab == _Tab.saved,
                () => setState(() => _tab = _Tab.saved)),
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, int? count, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.background : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: active
              ? const [
                  BoxShadow(
                      color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.textPrimary : AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _connectedCard(ChronographDevice d) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.good.withValues(alpha: 0.4)),
        gradient: const RadialGradient(
          center: Alignment.topLeft,
          radius: 1.5,
          colors: [Color(0x227FC88A), AppColors.surface],
          stops: [0.0, 0.8],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.bluetooth_connected,
                  size: 22,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.name,
                      style: const TextStyle(
                        fontFamily: AppFonts.numerals,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${d.remoteId}${d.firmwareVersion != null ? ' · fw ${d.firmwareVersion}' : ''}',
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(widget.isDeviceLost),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                // Pocket Pro doesn't expose battery over its VRS
                // service; True Ballistic reads it once during connect,
                // so a GATT device with 0% simply has no reading yet.
                child: d.deviceType.isBroadcast || d.batteryPercent > 0
                    ? _telemetryCell(
                        'BATTERY',
                        '${d.batteryPercent}',
                        '%',
                        color: _batteryColor(d.batteryPercent),
                      )
                    : _telemetryCell('BATTERY', '—', ''),
              ),
              _vSep(),
              Expanded(
                // GATT chronographs don't surface RSSI after connecting.
                child: !d.deviceType.isBroadcast && d.rssi == 0
                    ? _telemetryCell('SIGNAL', '—', '')
                    : _telemetryCell(
                        'SIGNAL',
                        '${d.rssi}',
                        'dBm',
                      ),
              ),
              _vSep(),
              Expanded(
                child: _telemetryCell(
                  'TYPE',
                  _typeLabel(d.deviceType),
                  '',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Disconnect is the only action — Rescan was redundant given the
          // continuous BLE scan, and a real Disconnect (one that stops the
          // radio) leaves no useful per-device "refresh" gesture.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onDisconnect,
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('DISCONNECT'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _telemetryCell(String label, String value, String unit,
      {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: AppFonts.numerals,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color ?? AppColors.textPrimary,
                height: 1.0,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _statusPill(bool isLost) {
    final color = isLost ? AppColors.warn : AppColors.good;
    final label = isLost ? 'STALE' : 'LIVE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vSep() => Container(width: 1, height: 30, color: AppColors.border);

  /// Treat scan entries older than this as out of range. Matches the
  /// 3-second window the live screen uses to decide a device is "lost".
  static const _scanResultFreshness = Duration(seconds: 5);

  /// Pocket Pro advertises the VRS service UUID (or its local name)
  /// instead of Nordic manufacturer data — recognize it directly from
  /// the advert so the list can render it without a broadcast payload.
  static bool _isPocketPro(ScanResult r) {
    return BroadcastParser.isPocketProAdvertisement(
      serviceUuids:
          r.advertisementData.serviceUuids.map((g) => g.str.toLowerCase()),
      localName: _advName(r),
    );
  }

  /// True Ballistic is matched by the vendor's obfuscated name prefix
  /// (it doesn't advertise its data service).
  static bool _isTrueBallistic(ScanResult r) {
    return TrueBallisticClient.matchesAd(
      r.advertisementData.serviceUuids.map((g) => g.str.toLowerCase()),
      _advName(r),
    );
  }

  static String _advName(ScanResult r) =>
      r.advertisementData.advName.isNotEmpty
          ? r.advertisementData.advName
          : r.device.platformName;

  Widget _nearbyList() {
    // Filter to Pocket-protocol advertisements (V2/D1 manufacturer data
    // or a Pocket Pro VRS advert), drop the currently connected device
    // (already shown in the card above), and drop stale entries whose
    // last advertisement is too old to trust.
    final connectedId = widget.connectedDevice?.remoteId;
    final now = DateTime.now();
    final filtered = widget.scanResults.where((r) {
      final data = r.advertisementData.manufacturerData[0x0059];
      final isBroadcastPocket =
          data != null && BroadcastParser.isPocketDevice(data);
      if (!isBroadcastPocket && !_isPocketPro(r) && !_isTrueBallistic(r)) {
        return false;
      }
      if (connectedId != null && r.device.remoteId.str == connectedId) {
        return false;
      }
      if (now.difference(r.timeStamp) > _scanResultFreshness) return false;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _scanIcon(),
            const SizedBox(width: 8),
            Text(
              widget.isScanning
                  ? 'Scanning · found ${filtered.length}'
                  : 'Stopped',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed:
                  widget.isScanning ? widget.onStopScan : widget.onStartScan,
              child: Text(
                widget.isScanning ? 'STOP' : 'SCAN',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Flexible(
          child: filtered.isEmpty
              ? _emptyList(widget.isScanning
                  ? 'Listening for FX Pocket advertisements…'
                  : 'Scan paused. Tap SCAN to look for chronographs.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final r = filtered[index];
                    return _deviceRow(r);
                  },
                ),
        ),
      ],
    );
  }

  Widget _savedList() {
    if (widget.savedDeviceId == null) {
      return _emptyList(
          'No saved device yet. Connect on Nearby to remember one.');
    }
    // Only treat the saved device as in range if its last advertisement is
    // fresh — _scanResults is replace-on-update but consumers can still
    // see entries that haven't been refreshed for a while.
    final now = DateTime.now();
    final hit = widget.scanResults
        .where((s) =>
            s.device.remoteId.str == widget.savedDeviceId &&
            now.difference(s.timeStamp) <= _scanResultFreshness)
        .toList();
    final inRange = hit.isNotEmpty;
    final isActive = widget.savedDeviceId == widget.connectedDevice?.remoteId;
    final name = inRange
        ? (_isTrueBallistic(hit.first)
            ? 'FX True Ballistic'
            : hit.first.device.platformName.isNotEmpty
                ? hit.first.device.platformName
                : _isPocketPro(hit.first)
                    ? 'FX Pocket Pro'
                    : (BroadcastParser.parse(hit
                            .first
                            .advertisementData
                            .manufacturerData[0x0059] ??
                        const []))
                        .deviceName)
        : (widget.connectedDevice?.name ?? 'Last connected device');
    final rssiText =
        inRange ? '${hit.first.rssi} dBm' : 'last seen — not advertising';

    return ListView(
      shrinkWrap: true,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? AppColors.good : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      inRange ? Icons.bluetooth : Icons.bluetooth_disabled,
                      size: 18,
                      color: inRange
                          ? AppColors.accent
                          : AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontFamily: AppFonts.numerals,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.savedDeviceId} · $rssiText',
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _savedStatusPill(inRange: inRange, isActive: isActive),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (inRange && !isActive)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            widget.onSelectDevice(widget.savedDeviceId!),
                        child: const Text('CONNECT'),
                      ),
                    )
                  else
                    const Spacer(),
                  if (inRange && !isActive) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onForget,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('FORGET'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _savedStatusPill({required bool inRange, required bool isActive}) {
    final (color, label) = isActive
        ? (AppColors.good, 'ACTIVE')
        : inRange
            ? (AppColors.accentSoft, 'IN RANGE')
            : (AppColors.warn, 'OUT OF RANGE');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _deviceRow(ScanResult r) {
    final nordicData = r.advertisementData.manufacturerData[0x0059];
    final broadcastData = nordicData != null
        ? BroadcastParser.parse(nordicData)
        : BroadcastData.invalid();
    final deviceId = r.device.remoteId.str;
    final isSelected = deviceId == widget.selectedDeviceId;
    final isPro = _isPocketPro(r);
    final isTb = !isPro && _isTrueBallistic(r);
    // True Ballistic advertises an obfuscated vendor string — show the
    // product name instead of the gibberish.
    final name = isTb
        ? 'FX True Ballistic'
        : r.device.platformName.isNotEmpty
            ? r.device.platformName
            : (isPro ? 'FX Pocket Pro' : broadcastData.deviceName);
    final bars = _rssiBars(r.rssi);
    // GATT chronographs carry no battery in their advert — showing the
    // parsed 0% would just look like a dead cell.
    final subtitle = isPro || isTb
        ? '$deviceId · ${r.rssi} dBm'
        : '$deviceId · ${broadcastData.batteryPercent}% · ${r.rssi} dBm';

    return InkWell(
      onTap: () => widget.onSelectDevice(deviceId),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.center_focus_strong,
                  size: 18, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontFamily: AppFonts.numerals,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _SignalBars(bars: bars),
            const SizedBox(width: 10),
            isSelected
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.good.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.good,
                        letterSpacing: 1.0,
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: const Text(
                      'CONNECT',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _emptyList(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.isScanning
                  ? Icons.bluetooth_searching
                  : Icons.bluetooth_disabled,
              size: 36,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanIcon() {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: widget.isScanning
            ? AppColors.accent.withValues(alpha: 0.2)
            : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.isScanning
                ? AppColors.accent
                : AppColors.textTertiary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _footerHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border,
          width: 1,
          style: BorderStyle.solid,
        ),
        color: AppColors.surfaceElevated,
      ),
      child: Row(
        children: const [
          Icon(Icons.help_outline, size: 16, color: AppColors.textTertiary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Can\'t find your chronograph? Make sure it\'s powered on and Bluetooth is enabled on the phone.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _batteryColor(int pct) {
    if (pct > 50) return AppColors.good;
    if (pct > 20) return AppColors.warn;
    return AppColors.danger;
  }

  /// Compact type label for the telemetry cell — the full "True
  /// Ballistic" doesn't fit a third-width cell at telemetry size.
  static String _typeLabel(ChronographDeviceType type) {
    switch (type) {
      case ChronographDeviceType.pocketV2:
        return 'V2';
      case ChronographDeviceType.pocketD1:
        return 'D1';
      case ChronographDeviceType.pocketPro:
        return 'Pro';
      case ChronographDeviceType.trueBallistic:
        return 'True';
    }
  }

  int _rssiBars(int rssi) {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    return 1;
  }
}

class _SignalBars extends StatelessWidget {
  final int bars;
  const _SignalBars({required this.bars});

  @override
  Widget build(BuildContext context) {
    final color = bars >= 4
        ? AppColors.good
        : bars >= 3
            ? AppColors.accentSoft
            : bars >= 2
                ? AppColors.warn
                : AppColors.danger;
    return SizedBox(
      width: 22,
      height: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          final filled = i < bars;
          final h = 4.0 + i * 3.5;
          return Container(
            width: 3,
            height: h,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: filled ? color : AppColors.border,
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }
}
