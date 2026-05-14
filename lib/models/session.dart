import 'dart:math';
import 'shot.dart';

/// Represents a shooting session with multiple shots and statistics.
class Session {
  /// Unique session identifier
  final String id;

  /// When the session was created
  final DateTime createdAt;

  /// Bullet weight in grains used for energy calculations
  final double bulletWeightGrains;

  /// List of shots in this session
  final List<Shot> shots;

  /// Optional user-provided session name
  final String? name;

  const Session({
    required this.id,
    required this.createdAt,
    required this.bulletWeightGrains,
    required this.shots,
    this.name,
  });

  /// Number of shots in session
  int get shotCount => shots.length;

  /// Whether session has any shots
  bool get isEmpty => shots.isEmpty;

  /// Whether session has enough shots for statistics (2+)
  bool get hasStatistics => shots.length >= 2;

  /// Most recent shot (null if empty)
  Shot? get lastShot => shots.isEmpty ? null : shots.last;

  /// Average velocity in FPS
  double get averageFps {
    if (shots.isEmpty) return 0;
    final sum = shots.fold<int>(0, (sum, shot) => sum + shot.velocityFps);
    return sum / shots.length;
  }

  /// Average velocity in m/s
  double get averageMs => averageFps * 0.3048;

  /// Minimum velocity in FPS
  int get minFps {
    if (shots.isEmpty) return 0;
    return shots.map((s) => s.velocityFps).reduce(min);
  }

  /// Maximum velocity in FPS
  int get maxFps {
    if (shots.isEmpty) return 0;
    return shots.map((s) => s.velocityFps).reduce(max);
  }

  /// Extreme spread (max - min) in FPS
  int get extremeSpreadFps {
    if (shots.length < 2) return 0;
    return maxFps - minFps;
  }

  /// Standard deviation in FPS
  double get standardDeviationFps {
    if (shots.length < 2) return 0;
    final avg = averageFps;
    final sumSquaredDiff = shots.fold<double>(
      0,
      (sum, shot) => sum + pow(shot.velocityFps - avg, 2),
    );
    return sqrt(sumSquaredDiff / shots.length);
  }

  /// Average energy in ft-lbs
  double get averageEnergyFtLbs {
    if (shots.isEmpty) return 0;
    return (bulletWeightGrains * averageFps * averageFps) / 450240.0;
  }

  /// Average energy in Joules
  double get averageEnergyJoules {
    if (shots.isEmpty) return 0;
    final grams = bulletWeightGrains * 0.0648;
    final ms = averageMs;
    return (grams * ms * ms) / 2000.0;
  }

  /// Create a new session with an additional shot
  Session addShot(int velocityFps) {
    final newShot = Shot(
      number: shots.length + 1,
      velocityFps: velocityFps,
      timestamp: DateTime.now(),
    );
    return Session(
      id: id,
      createdAt: createdAt,
      bulletWeightGrains: bulletWeightGrains,
      shots: [...shots, newShot],
      name: name,
    );
  }

  /// Create a copy with updated fields
  Session copyWith({
    String? id,
    DateTime? createdAt,
    double? bulletWeightGrains,
    List<Shot>? shots,
    String? name,
  }) {
    return Session(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      bulletWeightGrains: bulletWeightGrains ?? this.bulletWeightGrains,
      shots: shots ?? this.shots,
      name: name ?? this.name,
    );
  }

  /// Create from JSON (for persistence)
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      bulletWeightGrains: (json['bulletWeightGrains'] as num).toDouble(),
      shots: (json['shots'] as List)
          .map((s) => Shot.fromJson(s as Map<String, dynamic>))
          .toList(),
      name: json['name'] as String?,
    );
  }

  /// Convert to JSON (for persistence)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'bulletWeightGrains': bulletWeightGrains,
      'shots': shots.map((s) => s.toJson()).toList(),
      'name': name,
    };
  }

  /// Format session for display in history list
  String get displayTitle {
    if (name != null && name!.isNotEmpty) return name!;
    return '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'Session($id, $shotCount shots, avg: ${averageFps.toStringAsFixed(0)} fps)';
  }
}
