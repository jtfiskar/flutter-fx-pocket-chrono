/// Unit conversion utilities for temperature and velocity.
class UnitConverters {
  UnitConverters._();

  /// Convert Celsius to Fahrenheit
  static double celsiusToFahrenheit(double celsius) => celsius * 9 / 5 + 32;

  /// Convert Fahrenheit to Celsius
  static double fahrenheitToCelsius(double fahrenheit) =>
      (fahrenheit - 32) * 5 / 9;

  /// Convert meters per second to feet per second
  static double msToFps(double ms) => ms * 3.28084;

  /// Convert feet per second to meters per second
  static double fpsToMs(double fps) => fps / 3.28084;
}
