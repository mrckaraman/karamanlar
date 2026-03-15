import 'package:flutter/material.dart';

/// Uygulama genelinde kullanılan layout sabitleri.
class AppLayout {
  const AppLayout._();

  /// Üst app bar yüksekliği.
  static const double appBarHeight = 64;

  /// Masaüstü/web için sabit sidebar genişliği.
  static const double sidebarWidth = 250;

  /// İçerik alanı yatay/dikey padding.
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 24,
  );
}
