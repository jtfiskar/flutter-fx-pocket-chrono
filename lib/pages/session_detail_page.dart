import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';
import '../widgets/statistics_row.dart';
import '../widgets/shot_list.dart';
import '../services/session_storage.dart';

/// Page showing details of a saved session.
class SessionDetailPage extends StatelessWidget {
  final String sessionId;

  const SessionDetailPage({
    super.key,
    required this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final session = appState.getSavedSession(sessionId);

    if (session == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text('Session'),
        ),
        body: const Center(
          child: Text(
            'Session not found',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          session.displayTitle,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _exportSession(context, session),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, appState, session),
          ),
        ],
      ),
      body: Column(
        children: [
          // Session header info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date and weight info
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(session.createdAt),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Icon(
                      Icons.fitness_center,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${session.bulletWeightGrains.toStringAsFixed(1)} gr',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Statistics
                StatisticsRow(
                  average: appState.useFps
                      ? session.averageFps.toStringAsFixed(0)
                      : session.averageMs.toStringAsFixed(0),
                  extremeSpread: appState.useFps
                      ? session.extremeSpreadFps.toString()
                      : (session.extremeSpreadFps * 0.3048).toStringAsFixed(0),
                  standardDeviation: appState.useFps
                      ? session.standardDeviationFps.toStringAsFixed(1)
                      : (session.standardDeviationFps * 0.3048).toStringAsFixed(1),
                  unit: appState.velocityUnitLabel,
                  showStats: session.hasStatistics,
                  shotCount: session.shotCount,
                ),

                const SizedBox(height: 16),

                // Additional stats
                if (session.hasStatistics) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatColumn(
                        label: 'MIN',
                        value: appState.useFps
                            ? '${session.minFps}'
                            : '${(session.minFps * 0.3048).toStringAsFixed(0)}',
                        unit: appState.velocityUnitLabel,
                      ),
                      _StatColumn(
                        label: 'MAX',
                        value: appState.useFps
                            ? '${session.maxFps}'
                            : '${(session.maxFps * 0.3048).toStringAsFixed(0)}',
                        unit: appState.velocityUnitLabel,
                      ),
                      _StatColumn(
                        label: 'SHOTS',
                        value: '${session.shotCount}',
                        unit: '',
                      ),
                      _StatColumn(
                        label: 'ENERGY',
                        value: appState.useFtLbs
                            ? session.averageEnergyFtLbs.toStringAsFixed(1)
                            : session.averageEnergyJoules.toStringAsFixed(1),
                        unit: appState.energyUnitLabel,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Shot list header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text(
                  'Shot Log',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${session.shotCount} shots',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // Shot list
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ShotList(
                  shots: session.shots,
                  formatVelocity: (fps) => appState.useFps
                      ? fps.toString()
                      : (fps * 0.3048).toStringAsFixed(0),
                  unit: appState.velocityUnitLabel,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _exportSession(BuildContext context, Session session) {
    final csv = SessionStorage.exportToCsv(session);

    // Show export dialog with CSV content
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Export Session',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CSV data (copy to share):',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  csv,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState appState, Session session) {
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
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to history
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
