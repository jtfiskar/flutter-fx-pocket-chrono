import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';
import '../widgets/sparkline.dart';
import 'session_detail_page.dart';

/// Browse saved sessions — title block, summary strip, date filter,
/// and date-bucketed cards with sparklines.
class SessionHistoryPage extends StatefulWidget {
  const SessionHistoryPage({super.key});

  @override
  State<SessionHistoryPage> createState() => _SessionHistoryPageState();
}

enum _Filter { all, last30 }

class _SessionHistoryPageState extends State<SessionHistoryPage> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allSessions = appState.savedSessions;
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 30));
    final filtered = _filter == _Filter.all
        ? allSessions
        : allSessions.where((s) => s.createdAt.isAfter(cutoff)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(context),
            Expanded(
              child: allSessions.isEmpty
                  ? _empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        _summaryStrip(allSessions, appState),
                        const SizedBox(height: 12),
                        _filterChips(),
                        const SizedBox(height: 16),
                        ..._buildBuckets(filtered, appState),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            color: AppColors.textPrimary,
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 8),
          const Text(
            'History',
            style: TextStyle(
              fontFamily: AppFonts.numerals,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.0,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStrip(List<Session> sessions, AppState appState) {
    final totalShots = sessions.fold<int>(0, (sum, s) => sum + s.shotCount);
    final withStats = sessions.where((s) => s.hasStatistics).toList();
    final bestEsFps = withStats.isEmpty
        ? 0
        : withStats
            .map((s) => s.extremeSpreadFps)
            .reduce((a, b) => a < b ? a : b);
    final hasBestEs = withStats.isNotEmpty;
    // BEST ES tracks the user's current velocity unit, same as every
    // other velocity readout in the app.
    final bestEsLabel =
        hasBestEs ? appState.formatExtremeSpread(bestEsFps) : '—';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
                child: _SummaryCell(
                    label: 'SESSIONS', value: '${sessions.length}', unit: '')),
            _Sep(),
            Expanded(
                child: _SummaryCell(
                    label: 'TOTAL SHOTS',
                    value: '$totalShots',
                    unit: '')),
            _Sep(),
            Expanded(
              child: _SummaryCell(
                label: 'BEST ES',
                value: bestEsLabel,
                unit: hasBestEs ? appState.velocityUnitLabel : '',
                accent: AppColors.good,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChips() {
    return Row(
      children: [
        _Chip(
          label: 'All',
          selected: _filter == _Filter.all,
          onTap: () => setState(() => _filter = _Filter.all),
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Last 30 days',
          selected: _filter == _Filter.last30,
          onTap: () => setState(() => _filter = _Filter.last30),
        ),
      ],
    );
  }

  List<Widget> _buildBuckets(List<Session> sessions, AppState appState) {
    if (sessions.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              'No sessions in this range',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          ),
        ),
      ];
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    final Map<String, List<Session>> buckets = {};
    final order = <String>[];

    for (final s in sessions) {
      final ts = s.createdAt;
      String key;
      if (ts.isAfter(weekStart)) {
        key = 'This week';
      } else if (ts.year == now.year && ts.month == now.month) {
        key = 'Earlier in ${_monthName(ts.month)}';
      } else {
        key = '${_monthName(ts.month)} ${ts.year}';
      }
      if (!buckets.containsKey(key)) {
        buckets[key] = [];
        order.add(key);
      }
      buckets[key]!.add(s);
    }

    final widgets = <Widget>[];
    for (final key in order) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8, left: 4),
          child: Text(
            key.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
              letterSpacing: 1.4,
            ),
          ),
        ),
      );
      for (final s in buckets[key]!) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SessionCard(
              session: s,
              useFps: appState.useFps,
              useFtLbs: appState.useFtLbs,
              formatVelocity: appState.formatVelocity,
              velocityUnit: appState.velocityUnitLabel,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SessionDetailPage(sessionId: s.id),
                  ),
                );
              },
              onDelete: () => _confirmDelete(context, s),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.folder_open, size: 56, color: AppColors.textTertiary),
          SizedBox(height: 14),
          Text(
            'No saved sessions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Record shots in a session to see them here',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Session session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete Session?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Delete ${session.displayTitle} with ${session.shotCount} shots?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppState>().deleteSession(session.id);
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

  String _monthName(int m) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[m - 1];
  }
}

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color? accent;

  const _SummaryCell({
    required this.label,
    required this.value,
    required this.unit,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
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
}

class _Sep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: AppColors.border);
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.background : AppColors.textPrimary,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final Session session;
  final bool useFps;
  final bool useFtLbs;
  final String Function(int fps) formatVelocity;
  final String velocityUnit;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.useFps,
    required this.useFtLbs,
    required this.formatVelocity,
    required this.velocityUnit,
    required this.onTap,
    required this.onDelete,
  });

  Color? _flagColor() {
    if (!session.hasStatistics) return null;
    final ratio = session.averageFps > 0
        ? session.standardDeviationFps / session.averageFps
        : 0;
    if (session.extremeSpreadFps > 30) return AppColors.warn;
    if (ratio > 0.015) return AppColors.accent;
    return null;
  }

  String _duration() {
    if (session.shots.length < 2) return '—';
    final first = session.shots.first.timestamp;
    final last = session.shots.last.timestamp;
    final diff = last.difference(first);
    if (diff.inMinutes < 1) return '${diff.inSeconds}s';
    if (diff.inHours < 1) return '${diff.inMinutes}m ${diff.inSeconds % 60}s';
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  String _date() {
    final d = session.createdAt;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final flag = _flagColor();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: flag ?? Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_date()} · ${_duration()}',
                                  style: const TextStyle(
                                    fontFamily: AppFonts.mono,
                                    fontSize: 10,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  session.displayTitle,
                                  style: const TextStyle(
                                    fontFamily: AppFonts.numerals,
                                    fontSize: 18,
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
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${session.shotCount}',
                                style: const TextStyle(
                                  fontFamily: AppFonts.numerals,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  height: 1.0,
                                ),
                              ),
                              const Text(
                                'shots',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textTertiary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: AppColors.textTertiary,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            onPressed: onDelete,
                          ),
                        ],
                      ),
                      if (session.shots.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Sparkline(
                                values:
                                    session.shots.map((s) => s.velocityFps).toList(),
                                mean: session.averageFps,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'AVG ${formatVelocity(session.averageFps.round())} $velocityUnit',
                              style: const TextStyle(
                                fontFamily: AppFonts.mono,
                                fontSize: 10,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (session.hasStatistics) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _MiniStat(
                                  label: 'AVG',
                                  value: formatVelocity(
                                      session.averageFps.round()),
                                  unit: velocityUnit,
                                ),
                              ),
                              Expanded(
                                child: _MiniStat(
                                  label: 'ES',
                                  value: formatVelocity(
                                      session.extremeSpreadFps),
                                  unit: velocityUnit,
                                  accent: AppColors.accentSoft,
                                ),
                              ),
                              Expanded(
                                child: _MiniStat(
                                  label: 'SD',
                                  value: useFps
                                      ? session.standardDeviationFps
                                          .toStringAsFixed(1)
                                      : (session.standardDeviationFps * 0.3048)
                                          .toStringAsFixed(1),
                                  unit: velocityUnit,
                                  accent: AppColors.good,
                                ),
                              ),
                              Expanded(
                                child: _MiniStat(
                                  label: 'ENERGY',
                                  value: useFtLbs
                                      ? session.averageEnergyFtLbs
                                          .toStringAsFixed(1)
                                      : session.averageEnergyJoules
                                          .toStringAsFixed(1),
                                  unit: useFtLbs ? 'ft·lbs' : 'J',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color? accent;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.unit,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppFonts.numerals,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: accent ?? AppColors.textPrimary,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}
