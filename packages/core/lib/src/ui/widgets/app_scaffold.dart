import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_responsive.dart';

/// Uygulama genelinde kullanilan standart scaffold.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.title,
    this.titleWidget,
    this.titleTextStyle,
    this.actions,
    this.floatingActionButton,
    this.bottom,
    this.showBackButton = true,
    this.resizeToAvoidBottomInset = true,
    required this.body,
  });

  final String? title;
  final Widget? titleWidget;
  final TextStyle? titleTextStyle;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottom;
  final bool showBackButton;
  final bool resizeToAvoidBottomInset;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final screenPadding = AppResponsive.screenPaddingForWidth(width);

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: AppBar(
        title: titleWidget ??
            (title != null
                ? Text(
                    title!,
                    style: titleTextStyle,
                  )
                : null),
        leading: _buildLeading(context),
        actions: actions,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppResponsive.maxContentWidth),
          child: Padding(
            padding: screenPadding,
            child: body,
          ),
        ),
      ),
      bottomNavigationBar: bottom,
      floatingActionButton: floatingActionButton,
    );
  }

  Widget? _buildLeading(BuildContext context) {
    if (!showBackButton) {
      return null;
    }

    final navigator = Navigator.of(context);
    final canNavigatorPop = navigator.canPop();

    final router = GoRouter.maybeOf(context);
    final canRouterPop = router?.canPop() ?? false;
    final logicalBackLocation = _logicalBackLocation(context);

    final canPop = canNavigatorPop || canRouterPop || logicalBackLocation != null;
    if (!canPop) {
      // Root ekranda geri ok görünmesin.
      return null;
    }

    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () async {
        // Önce klasik Navigator yığını üzerinden geri dönmeyi dene.
        if (navigator.canPop()) {
          await navigator.maybePop();
          return;
        }

        // Olmazsa GoRouter stack'inde geri git veya mantıksal parent'a dön.
        final r = GoRouter.maybeOf(context);
        if (r != null) {
          if (r.canPop()) {
            r.pop();
            return;
          }

          final backLocation = _logicalBackLocation(context);
          if (backLocation != null) {
            r.go(backLocation);
          }
        }
      },
    );
  }

  String? _logicalBackLocation(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return null;

    final state = GoRouterState.of(context);
    final path = state.uri.path;

    // Login ve ana dashboard için geri ok gösterme.
    if (path == '/login' || path == '/dashboard' || path == '/home/dashboard' || path == '/') {
      return null;
    }

    // Segmentleri ayır: '' + 'stocks' + '123' + 'edit' -> ['stocks','123','edit']
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return null;
    }

    // Tek segmentli yollar (ör: /stocks, /customers, /sales ...) için dashboard'a dön.
    if (segments.length == 1) {
      return '/dashboard';
    }

    // Daha derin yollar için son segmenti at ve parent path'e dön.
    final parentSegments = segments.sublist(0, segments.length - 1);
    final parentPath = '/${parentSegments.join('/')}';
    return parentPath;
  }
}
