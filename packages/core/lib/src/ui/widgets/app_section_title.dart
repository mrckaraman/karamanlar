import 'package:flutter/material.dart';

import '../spacing.dart';

class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w600);

    return Padding(
      padding: AppSpacing.symmetric(horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: style)),
          if (action != null) action!,
        ],
      ),
    );
  }
}
