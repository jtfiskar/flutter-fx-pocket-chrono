/// Utility class for energy calculations and unit conversions.
class EnergyCalculator {
  /// Calculate energy in foot-pounds from FPS and grains.
  /// Formula: E = (grains * fps^2) / 450240
  static double fpsToFtLbs(int fps, double grains) {
    return (grains * fps * fps) / 450240.0;
  }

  /// Calculate energy in Joules from m/s and grams.
  /// Formula: E = (grams * (m/s)^2) / 2000
  static double msToJoules(double ms, double grams) {
    return (grams * ms * ms) / 2000.0;
  }

  /// Calculate energy in Joules from FPS and grains.
  static double fpsGrainsToJoules(int fps, double grains) {
    final ms = fpsToMs(fps);
    final grams = grainsToGrams(grains);
    return msToJoules(ms, grams);
  }

  /// Convert grains to grams.
  /// 1 grain = 0.0648 grams
  static double grainsToGrams(double grains) {
    return grains * 0.0648;
  }

  /// Convert grams to grains.
  static double gramsToGrains(double grams) {
    return grams / 0.0648;
  }

  /// Convert FPS to m/s.
  /// 1 fps = 0.3048 m/s
  static double fpsToMs(int fps) {
    return fps * 0.3048;
  }

  /// Convert m/s to FPS.
  static int msToFps(double ms) {
    return (ms / 0.3048).round();
  }

  /// Convert ft-lbs to Joules.
  /// 1 ft-lb = 1.35582 Joules
  static double ftLbsToJoules(double ftLbs) {
    return ftLbs * 1.35582;
  }

  /// Convert Joules to ft-lbs.
  static double joulesToFtLbs(double joules) {
    return joules / 1.35582;
  }

  /// Format velocity for display.
  static String formatVelocity(int fps, bool useFps) {
    if (useFps) {
      return '$fps';
    } else {
      return fpsToMs(fps).toStringAsFixed(0);
    }
  }

  /// Format energy for display.
  static String formatEnergy(int fps, double grains, bool useFtLbs) {
    if (useFtLbs) {
      return fpsToFtLbs(fps, grains).toStringAsFixed(1);
    } else {
      return fpsGrainsToJoules(fps, grains).toStringAsFixed(1);
    }
  }

  /// Get velocity unit label.
  static String velocityUnit(bool useFps) {
    return useFps ? 'fps' : 'm/s';
  }

  /// Get energy unit label.
  static String energyUnit(bool useFtLbs) {
    return useFtLbs ? 'ft-lbs' : 'J';
  }
}
