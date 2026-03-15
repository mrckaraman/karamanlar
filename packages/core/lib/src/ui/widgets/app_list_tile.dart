import 'package:flutter/material.dart';

import '../spacing.dart';

class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.subtitleMaxLines,
    this.subtitleOverflow,
    this.onTap,
    this.dense = false,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final int? subtitleMaxLines;
  final TextOverflow? subtitleOverflow;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.s4 : AppSpacing.s8,
        // Daha kompakt görünüm için dikey boşluğu azalt
        vertical: dense ? 2 : AppSpacing.s4,
      ),
      child: ListTile(
        visualDensity:
            dense ? const VisualDensity(horizontal: 0, vertical: -2) : null,
        contentPadding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 16,
          vertical: dense ? 4 : 8,
        ),
        leading: leading,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: subtitleMaxLines,
                overflow: subtitleOverflow,
              )
            : null,
        trailing: trailing == null
            ? null
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1,
                  child: trailing,
                ),
              ),
        onTap: onTap,
      ),
    );
  }
}
