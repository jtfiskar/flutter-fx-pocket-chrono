import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';
import '../widgets/histogram.dart';
import '../widgets/trend_chart.dart';
import '../widgets/shot_list.dart';
import '../services/session_storage.dart';

/// Format a single shot's energy using a session's saved bullet weight.
///
/// `AppState.formatEnergy` calculates with the *current* global weight,
/// which is wrong when viewing a saved session whose weight was different.
String _formatSessionEnergy(int fps, Session session, bool useFtLbs) {
  final grains = session.bulletWeightGrains;
  if (useFtLbs) {
    return ((grains * fps * fps) / 450240.0).toStringAsFixed(1);
  }
  final grams = grains * 0.0648;
  final ms = fps * 0.3048;
  return ((grams * ms * ms) / 2000.0).toStringAsFixed(1);
}

/// Detailed view of a saved session: header card, average velocity hero,
/// 6-cell stats panel, histogram, trend chart, full shot table, and
/// export/share actions.
class SessionDetailPage extends StatelessWidget {
  final String sessionId;

  const SessionDetailPage({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final session = appState.getSavedSession(sessionId);

    if (session == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Session')),
        body: const Center(
          child: Text(
            'Session not found',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final values = session.shots.map((s) => s.velocityFps).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topNav(context, session, appState),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _headerCard(session),
                  const SizedBox(height: 12),
                  _avgVelocityHero(session, appState),
                  const SizedBox(height: 12),
                  _statsPanel(session, appState),
                  if (session.shots.length >= 2) ...[
                    const SizedBox(height: 12),
                    _chartCard(
                      'Velocity distribution',
                      '${session.shotCount} shots',
                      Histogram(
                        values: values,
                        mean: session.averageFps,
                        sd: session.standardDeviationFps,
                        useFps: appState.useFps,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _chartCard(
                      'Trend over time',
                      _trendMeta(session, appState),
                      TrendChart(
                        shots: session.shots,
                        meanFps: session.averageFps,
                        sdFps: session.standardDeviationFps,
                        useFps: appState.useFps,
                        unitLabel: appState.velocityUnitLabel,
                        maxShots: 25,
                        height: 168,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _shotTableCard(session, appState),
                  const SizedBox(height: 14),
                  _actionRow(context, session),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topNav(BuildContext context, Session session, AppState appState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'SESSION',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                    letterSpacing: 1.4,
                  ),
                ),
                Text(
                  session.displayTitle,
                  style: const TextStyle(
                    fontFamily: AppFonts.numerals,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
            color: AppColors.surfaceElevated,
            onSelected: (value) {
              if (value == 'delete') {
                _confirmDelete(context, appState, session);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete session',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerCard(Session session) {
    final duration = _duration(session);
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 56,
            margin: const EdgeInsets.only(right: 14),
            decoration: const BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(2)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatDate(session.createdAt)} · $duration',
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  session.displayTitle,
                  style: const TextStyle(
                    fontFamily: AppFonts.numerals,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _chip(Icons.tag, '${session.shotCount} shots'),
                    _chip(
                      Icons.fitness_center,
                      '${session.bulletWeightGrains.toStringAsFixed(1)} gr',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textTertiary),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avgVelocityHero(Session session, AppState appState) {
    final primary = appState.useFps
        ? session.averageFps.toStringAsFixed(0)
        : session.averageMs.toStringAsFixed(0);
    final alt = appState.useFps
        ? session.averageMs.toStringAsFixed(1)
        : session.averageFps.toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AVG VELOCITY',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                primary,
                style: const TextStyle(
                  fontFamily: AppFonts.numerals,
                  fontSize: 60,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                  height: 0.95,
                  shadows: [
                    Shadow(color: AppColors.accentGlow, blurRadius: 14),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  appState.velocityUnitLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      alt,
                      style: const TextStyle(
                        fontFamily: AppFonts.numerals,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appState.useFps ? 'm/s' : 'fps',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsPanel(Session session, AppState appState) {
    final hasStats = session.hasStatistics;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _cell(
                    'ES',
                    hasStats
                        ? appState
                            .formatExtremeSpread(session.extremeSpreadFps)
                        : '—',
                    appState.velocityUnitLabel,
                    accent: AppColors.accentSoft,
                  ),
                ),
                _sep(),
                Expanded(
                  child: _cell(
                    'SD',
                    hasStats
                        ? appState
                            .formatStandardDeviation(session.standardDeviationFps)
                        : '—',
                    appState.velocityUnitLabel,
                    accent: AppColors.good,
                  ),
                ),
                _sep(),
                Expanded(
                  child: _cell(
                    'ENERGY',
                    session.shots.isNotEmpty
                        ? (appState.useFtLbs
                            ? session.averageEnergyFtLbs.toStringAsFixed(1)
                            : session.averageEnergyJoules.toStringAsFixed(1))
                        : '—',
                    appState.energyUnitLabel,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _cell(
                    'MIN',
                    session.shots.isNotEmpty
                        ? appState.formatVelocity(session.minFps)
                        : '—',
                    appState.velocityUnitLabel,
                  ),
                ),
                _sep(),
                Expanded(
                  child: _cell(
                    'MAX',
                    session.shots.isNotEmpty
                        ? appState.formatVelocity(session.maxFps)
                        : '—',
                    appState.velocityUnitLabel,
                  ),
                ),
                _sep(),
                Expanded(
                  child: _cell(
                    'MEDIAN',
                    session.shots.isNotEmpty
                        ? appState
                            .formatAverageVelocity(session.medianFps)
                        : '—',
                    appState.velocityUnitLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, String value, String unit, {Color? accent}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
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
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: AppFonts.numerals,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: accent ?? AppColors.textPrimary,
                  height: 1.0,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _sep() => Container(width: 1, color: AppColors.border);

  Widget _chartCard(String title, String meta, Widget chart) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                meta,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          chart,
        ],
      ),
    );
  }

  String _trendMeta(Session session, AppState appState) {
    if (session.shots.length < 2) return '';
    final first = session.shots.first.velocityFps;
    final last = session.shots.last.velocityFps;
    final drift = last - first;
    final sign = drift > 0 ? '+' : drift < 0 ? '−' : '±';
    final magnitude =
        appState.useFps ? drift.abs() : (drift.abs() * 0.3048).round();
    return 'drift $sign$magnitude ${appState.velocityUnitLabel}';
  }

  Widget _shotTableCard(Session session, AppState appState) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Text(
                  'ALL SHOTS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: 1.4,
                  ),
                ),
                const Spacer(),
                Text(
                  '${session.shotCount}',
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
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
              shots: session.shots,
              formatVelocity: appState.formatVelocity,
              // Use the session's stored bullet weight, not the global
              // AppState weight — the user may have changed grain since
              // this session was recorded.
              formatEnergy: (fps) =>
                  _formatSessionEnergy(fps, session, appState.useFtLbs),
              velocityUnit: appState.velocityUnitLabel,
              energyUnit: appState.energyUnitLabel,
              averageFps: session.averageFps,
              standardDeviationFps: session.standardDeviationFps,
              sessionStart: session.createdAt,
              useFps: appState.useFps,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(BuildContext context, Session session) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _exportSession(context, session),
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('EXPORT CSV'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _shareCsv(context, session),
            icon: const Icon(Icons.ios_share, size: 16),
            label: const Text('SHARE'),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year} · '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _duration(Session session) {
    if (session.shots.length < 2) return '—';
    final first = session.shots.first.timestamp;
    final last = session.shots.last.timestamp;
    final diff = last.difference(first);
    if (diff.inMinutes < 1) return '${diff.inSeconds}s';
    if (diff.inHours < 1) {
      return '${diff.inMinutes}m ${diff.inSeconds % 60}s';
    }
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  void _exportSession(BuildContext context, Session session) {
    final csv = SessionStorage.exportToCsv(session);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Export CSV',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                csv,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csv));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied CSV to clipboard')),
              );
              Navigator.pop(context);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('COPY'),
          ),
        ],
      ),
    );
  }

  void _shareCsv(BuildContext context, Session session) {
    final csv = SessionStorage.exportToCsv(session);
    Clipboard.setData(ClipboardData(text: csv));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV copied to clipboard — paste into your share target'),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, AppState appState, Session session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete Session?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'This will permanently delete this session with ${session.shotCount} shots.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              appState.deleteSession(session.id);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
