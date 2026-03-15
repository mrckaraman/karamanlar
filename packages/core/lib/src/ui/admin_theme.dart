import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Admin uygulaması için kırmızı odaklı profesyonel tema.
class AdminTheme {
  const AdminTheme._();

  static ThemeData get light {
    // Ortak AppTheme üzerine koyu lacivert/slate tonlarıyla admin odaklı tema.
    final base = AppTheme.lightFromSeed(const Color(0xFF0F172A));
    final colorScheme = base.colorScheme.copyWith(
      primary: const Color(0xFF0F172A),
      onPrimary: Colors.white,
      secondary: const Color(0xFF334155),
    );

    return base.copyWith(
      colorScheme: colorScheme,
      // Admin için de nötr arka plan; ciddiyet hissi renklerden gelir.
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      cardTheme: base.cardTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.04),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(40),
          side: BorderSide(color: colorScheme.primary),
          foregroundColor: colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.resolveWith(
          (states) => colorScheme.primary.withValues(alpha: 0.04),
        ),
      ),
    );
  }

  /// Admin uygulaması için koyu tema.
  ///
  /// Login sayfasındaki koyu arka plan ile uyumlu olacak şekilde
  /// lacivert/siyah tonları kullanır.
  static ThemeData get dark {
    final seed = const Color(0xFF0F172A);
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    final colorScheme = baseScheme.copyWith(
      primary: seed,
      secondary: const Color(0xFF38BDF8),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF020617),
    );

    return base.copyWith(
      cardTheme: base.cardTheme.copyWith(
        color: const Color(0xFF020617),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
