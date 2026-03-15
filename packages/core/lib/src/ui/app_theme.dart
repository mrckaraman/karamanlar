import 'package:flutter/material.dart';

/// Uygulamanın ortak tasarım sistemi.
///
/// Admin ve Customer uygulamaları aynı DNA'yı paylaşır; sadece seedColor
/// gibi küçük vurgu farklılıklarıyla ayrışır.
class AppTheme {
  const AppTheme._();

  /// Müşteri uygulaması için açık tema.
  static ThemeData get light => lightFromSeed(const Color(0xFF2563EB));

  /// Admin uygulaması için açık tema.
  static ThemeData get adminLight => lightFromSeed(const Color(0xFF0F172A));

  /// Ortak Material 3 tema tanımı.
  static ThemeData lightFromSeed(Color seedColor) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    // Ortak renk sistemi: nötr arka plan + beyaz kartlar.
    final colorScheme = baseScheme.copyWith(
      primary: seedColor,
      onPrimary: Colors.white,
      secondary: const Color(0xFF16A34A), // CTA / success vurgusu
      surface: Colors.white,
      error: const Color(0xFFDC2626),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      disabledColor: Colors.black38,

      // Yumuşak nötr arka plan.
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),

      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        isDense: false,
        filled: true,
        fillColor: Colors.white,
        constraints: const BoxConstraints(minHeight: 56),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: StadiumBorder(
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        labelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        space: 1,
        thickness: 1,
      ),
    );

    return base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        hintStyle: const TextStyle(color: Colors.black54),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Colors.black,
      ),
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(color: Colors.black),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: Colors.black),
        titleMedium: base.textTheme.titleMedium?.copyWith(color: Colors.black),
      ),
    );
  }
}
