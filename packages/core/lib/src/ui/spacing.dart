import 'package:flutter/widgets.dart';

/// 4–32 aralığında 4'lük grid tabanlı spacing sabitleri.
class AppSpacing {
  const AppSpacing._();

  // Temel grid: 4, 8, 12, 16, 20, 24, 32 kullanılır.
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  // Ekran ve kart padding'leri de aynı grid'e oturtulur.
  static const EdgeInsets screenPadding = EdgeInsets.all(s16);
  static const EdgeInsets cardPadding = EdgeInsets.all(s12);

  static const EdgeInsets horizontal16 = EdgeInsets.symmetric(horizontal: s16);
  static const EdgeInsets vertical8 = EdgeInsets.symmetric(vertical: s8);

  static EdgeInsets all(double value) => EdgeInsets.all(value);
  static EdgeInsets symmetric({double horizontal = 0, double vertical = 0}) =>
      EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  static EdgeInsets only({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) =>
      EdgeInsets.only(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      );
}
