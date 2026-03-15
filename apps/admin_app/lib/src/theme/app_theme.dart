import 'package:flutter/material.dart';

import 'tokens/app_radius.dart';

/// Karamanlar Ticaret admin uygulaması için light-only kurumsal tema.
class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    const primary = Color(0xFF22A38C);
    const primaryHover = Color(0xFF1B8572);
    const scaffoldBg = Color(0xFFF8FAFC);
    const cardBg = Colors.white;
    const borderColor = Color(0xFFE5E7EB);

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'NotoSans',
      scaffoldBackgroundColor: scaffoldBg,
      disabledColor: Colors.black38,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: primary,
        surface: cardBg,
        // background alanı deprecated, surface kullanımıyla aynı ton korunuyor.
        surfaceContainerHighest: scaffoldBg,
        error: Color(0xFFDC2626),
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      cardTheme: base.cardTheme.copyWith(
        color: cardBg,
        surfaceTintColor: cardBg,
        elevation: 0.5,
        shadowColor: const Color(0x1F111827),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: borderColor, width: 1),
        ),
      ),
      dividerColor: borderColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Color(0xFF111827),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: Color(0xFF111827),
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: Color(0xFF111827),
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
        bodyLarge: TextStyle(
          color: Colors.black,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.black,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: Color(0xFF6B7280),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: false,
        filled: true,
        fillColor: Colors.white,
        constraints: const BoxConstraints(minHeight: 56),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: Colors.black54,
          fontSize: 13,
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Colors.black,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(0, 44)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return primaryHover;
            }
            return primary;
          }),
          elevation: WidgetStateProperty.all(0),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(0, 44)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          side: WidgetStateProperty.all(
            const BorderSide(color: borderColor, width: 1),
          ),
          foregroundColor:
              WidgetStateProperty.all(const Color(0xFF111827)),
        ),
      ),
      iconTheme: const IconThemeData(
        color: Color(0xFF6B7280),
      ),
      dataTableTheme: const DataTableThemeData(),
    );
  }
}
