import 'package:flutter/material.dart';

import '../app_responsive.dart';

/// MaterialApp.builder içinde kullanılmak üzere responsive tema sarmalayıcısı.
///
/// - TextScaleFactor / TextScaler: aşırı büyümelerde taşmayı azaltmak için clamp
/// - Başlık stillerini ekran genişliğine göre hafif ölçekler
class AppResponsiveTheme extends StatelessWidget {
  const AppResponsiveTheme({
    super.key,
    required this.child,
    this.minTextScale = 1.0,
    this.maxTextScale = 1.15,
  });

  final Widget child;
  final double minTextScale;
  final double maxTextScale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final titleScale = AppResponsive.titleScaleForWidth(width);

        final mediaQuery = MediaQuery.of(context);
        final minScale = minTextScale.isFinite ? minTextScale : 1.0;
        final maxScale = maxTextScale.isFinite ? maxTextScale : 1.15;

        final clampedScaler = (maxScale > minScale)
            ? mediaQuery.textScaler.clamp(
                minScaleFactor: minScale,
                maxScaleFactor: maxScale,
              )
            : TextScaler.linear(minScale);

        final theme = Theme.of(context);
        final tt = theme.textTheme;

        TextStyle? scale(TextStyle? s) {
          if (s == null) return null;
          final size = s.fontSize;
          if (size == null) return s;
          return s.copyWith(fontSize: size * titleScale);
        }

        final scaledTextTheme = tt.copyWith(
          displaySmall: scale(tt.displaySmall),
          headlineLarge: scale(tt.headlineLarge),
          headlineMedium: scale(tt.headlineMedium),
          headlineSmall: scale(tt.headlineSmall),
          titleLarge: scale(tt.titleLarge),
        );

        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedScaler),
          child: Theme(
            data: theme.copyWith(textTheme: scaledTextTheme),
            child: child,
          ),
        );
      },
    );
  }
}
