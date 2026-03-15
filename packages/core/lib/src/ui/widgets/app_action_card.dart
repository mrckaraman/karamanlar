import 'package:flutter/material.dart';

import '../spacing.dart';

/// Ortak KPI / aksiyon kartı.
///
/// - Başlık
/// - Opsiyonel büyük değer
/// - Kısa açıklama / ipucu
/// - İsteğe bağlı tıklanabilirlik (chevron + hover + cursor)
class AppActionCard extends StatefulWidget {
  const AppActionCard({
    super.key,
    this.icon,
    required this.title,
    this.value,
    this.hint,
    this.onTap,
    this.accentColor,
  });

  final IconData? icon;
  final String title;
  final String? value;
  final String? hint;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  State<AppActionCard> createState() => _AppActionCardState();
}

class _AppActionCardState extends State<AppActionCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isClickable = widget.onTap != null;
    final accent = widget.accentColor ?? colorScheme.primary;

    final borderColor = _hovering && isClickable
        ? accent.withValues(alpha: 0.25)
        : const Color(0xFFE5E7EB);

    return MouseRegion(
      cursor:
          isClickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (!isClickable) return;
        setState(() {
          _hovering = true;
        });
      },
      onExit: (_) {
        if (!isClickable) return;
        setState(() {
          _hovering = false;
        });
      },
      child: Card(
        elevation: _hovering && isClickable ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.icon,
                          color: accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                    ],
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isClickable)
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.outline,
                      ),
                  ],
                ),
                if (widget.value != null && widget.value!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    widget.value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                if (widget.hint != null && widget.hint!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    widget.hint!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
