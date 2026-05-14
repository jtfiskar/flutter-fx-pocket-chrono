/// Application configuration constants.
///
/// Compile-time flags for enabling/disabling features.
class AppConfig {
  /// Enable demo mode for testing without a physical chronograph.
  /// Set to true for development, false for production builds.
  static const bool kDemoMode = true;

  // Demo mode velocity configuration (airgun)
  static const int demoMinVelocityFps = 800;
  static const int demoMaxVelocityFps = 950;
  static const double demoStdDevPercent = 1.5;
}
