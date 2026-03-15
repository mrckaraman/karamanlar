import 'package:flutter/widgets.dart';

/// Uygulama genelinde kullanılan responsive breakpoint ve yardımcıları.
///
/// Breakpoints:
/// - <600  : mobile
/// - 600-1024 : tablet
/// - >1024 : desktop
class AppResponsive {
  const AppResponsive._();

  static const double mobileMax = 600;
  static const double tabletMax = 1024;

  static bool isMobileWidth(double width) => width < mobileMax;
  static bool isTabletWidth(double width) => width >= mobileMax && width <= tabletMax;
  static bool isDesktopWidth(double width) => width > tabletMax;

  static bool isMobile(BuildContext context) =>
      isMobileWidth(MediaQuery.sizeOf(context).width);

  static bool isTablet(BuildContext context) =>
      isTabletWidth(MediaQuery.sizeOf(context).width);

  static bool isDesktop(BuildContext context) =>
      isDesktopWidth(MediaQuery.sizeOf(context).width);

  /// İçerik padding standardı:
  /// - Mobile: 16
  /// - Tablet: 24
  /// - Desktop: 32
  static EdgeInsets screenPaddingForWidth(double width) {
    if (isMobileWidth(width)) return const EdgeInsets.all(16);
    if (isTabletWidth(width)) return const EdgeInsets.all(24);
    return const EdgeInsets.all(32);
  }

  static EdgeInsets screenPadding(BuildContext context) =>
      screenPaddingForWidth(MediaQuery.sizeOf(context).width);

  /// Desktop'ta içerik maksimum genişliği.
  static const double maxContentWidth = 1200;

  /// Grid kolon sayısını responsive belirler.
  ///
  /// Varsayılanlar:
  /// - mobile: 1
  /// - tablet: 2
  /// - desktop: 3
  static int gridColumnsForWidth(
    double width, {
    int mobile = 1,
    int tablet = 2,
    int desktop = 3,
  }) {
    if (isMobileWidth(width)) return mobile;
    if (isTabletWidth(width)) return tablet;
    return desktop;
  }

  static int gridColumns(
    BuildContext context, {
    int mobile = 1,
    int tablet = 2,
    int desktop = 3,
  }) =>
      gridColumnsForWidth(
        MediaQuery.sizeOf(context).width,
        mobile: mobile,
        tablet: tablet,
        desktop: desktop,
      );

  /// Başlık fontları için ekran boyutuna bağlı ölçek.
  static double titleScaleForWidth(double width) {
    if (isMobileWidth(width)) return 1.0;
    if (isTabletWidth(width)) return 1.06;
    return 1.12;
  }
}
