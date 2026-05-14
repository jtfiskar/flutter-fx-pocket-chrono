/// Represents a single shot/velocity measurement in a session.
class Shot {
  /// Shot number within the session (1-based)
  final int number;

  /// Velocity in feet per second (raw measurement)
  final int velocityFps;

  /// Timestamp when shot was recorded
  final DateTime timestamp;

  const Shot({
    required this.number,
    required this.velocityFps,
    required this.timestamp,
  });

  /// Velocity in meters per second
  double get velocityMs => velocityFps * 0.3048;

  /// Calculate energy in foot-pounds given bullet weight in grains
  double energyFtLbs(double grains) {
    return (grains * velocityFps * velocityFps) / 450240.0;
  }

  /// Calculate energy in Joules given bullet weight in grains
  double energyJoules(double grains) {
    final grams = grains * 0.0648;
    final ms = velocityMs;
    return (grams * ms * ms) / 2000.0;
  }

  /// Create from JSON (for persistence)
  factory Shot.fromJson(Map<String, dynamic> json) {
    return Shot(
      number: json['number'] as int,
      velocityFps: json['velocityFps'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Convert to JSON (for persistence)
  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'velocityFps': velocityFps,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'Shot(#$number: $velocityFps fps)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Shot &&
        other.number == number &&
        other.velocityFps == velocityFps &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(number, velocityFps, timestamp);
}
