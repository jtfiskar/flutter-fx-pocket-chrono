import 'package:flutter/material.dart';

/// Design tokens lifted from the Open Design prototype:
/// amber-on-OLED, hairline borders, four-step elevation. Every screen
/// pulls from these — change `accent` here to recolor the whole app.
class AppColors {
  // Canvas + elevation
  static const Color background = Color(0xFF0A0E14);
  static const Color surface = Color(0xFF121823);
  static const Color surfaceElevated = Color(0xFF1A212E);
  static const Color surfaceHigh = Color(0xFF242E3E);
  static const Color border = Color(0xFF232B39);
  static const Color borderStrong = Color(0xFF3A4763);

  // Foreground tiers
  static const Color textPrimary = Color(0xFFF1F4F9);
  static const Color textSecondary = Color(0xFFA8B3C6);
  static const Color textTertiary = Color(0xFF6B768C);
  static const Color textMuted = Color(0xFF4A5468);

  // Signal amber (replaces blue brand)
  static const Color accent = Color(0xFFFFC14A);
  static const Color accentSoft = Color(0xFFFFD680);
  static const Color accentDeep = Color(0xFFD99C1F);
  static const Color accentGlow = Color(0x38FFC14A); // ~22% alpha
  static const Color accentLine = Color(0x66FFC14A); // ~40% alpha
  static const Color accentBand = Color(0x1AFFC14A); // ~10% alpha

  // Semantic colors — reserved meanings, do not reuse for decoration
  static const Color good = Color(0xFF7FC88A);
  static const Color warn = Color(0xFFFFAA3F);
  static const Color danger = Color(0xFFFF6464);
  static const Color info = Color(0xFF5FA8FF);

  // Back-compat aliases — existing code references these names.
  // Routes new amber accent + semantic colors through the old identifiers
  // so screens not yet redesigned still inherit the refreshed palette.
  static const Color primary = accent;
  static const Color primaryDark = accentDeep;
  static const Color success = good;
  static const Color warning = warn;
  static const Color error = danger;
  static const Color toggleHint = accent;
  static const Color signalGood = good;
  static const Color signalMedium = warn;
  static const Color signalPoor = danger;

  // Wind call direction (unused by Chrono Lite but kept for API stability)
  static const Color leftAdjust = Color(0xFF06B6D4);
  static const Color rightAdjust = Color(0xFFF97316);
  static const Color holdZero = textTertiary;
}

/// Typography families. SairaCondensed for numerics (instrument-cluster feel),
/// JetBrainsMono for timestamps and MAC strings, system UI font for body text.
class AppFonts {
  static const String numerals = 'SairaCondensed';
  static const String mono = 'JetBrainsMono';
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      colorScheme: const ColorScheme.dark(
        surface: AppColors.background,
        primary: AppColors.accent,
        onPrimary: AppColors.background,
        secondary: AppColors.accentDeep,
        onSecondary: AppColors.textPrimary,
        error: AppColors.danger,
        onError: AppColors.textPrimary,
        onSurface: AppColors.textPrimary,
      ),

      scaffoldBackgroundColor: AppColors.background,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.background,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surface,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 22,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accent;
          }
          return AppColors.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accent.withValues(alpha: 0.3);
          }
          return AppColors.border;
        }),
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.accent,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.8),
        unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceElevated,
        selectedColor: AppColors.accent.withValues(alpha: 0.18),
        labelStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.border,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accent.withValues(alpha: 0.2),
      ),
    );
  }
}

/// Text styles for wind-call display — preserved from earlier wind-call screens.
/// Not currently rendered by Chrono Lite but kept to avoid breaking external
/// references during the OSS publish.
class WindCallTextStyles {
  static const TextStyle value = TextStyle(
    fontFamily: AppFonts.numerals,
    fontSize: 72,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    height: 1.0,
  );

  static const TextStyle unit = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle direction = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle dataValue = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle dataLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    letterSpacing: 1.0,
  );

  static const TextStyle chipText = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );
}
