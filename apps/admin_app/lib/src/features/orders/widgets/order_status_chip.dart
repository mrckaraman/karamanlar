import 'package:flutter/material.dart';

String orderStatusLabel(String status) {
  final s = status.toLowerCase();
  switch (s) {
    case 'new':
      return 'Yeni';
    case 'approved':
      return 'Onaylandı';
    case 'preparing':
      return 'Hazırlanıyor';
    case 'shipped':
      return 'Sevk edildi';
    case 'completed':
      return 'Tamamlandı';
    case 'cancelled':
      return 'İptal';
    default:
      if (s.isEmpty) return 'Bilinmiyor';
      return status;
  }
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status.trim().toLowerCase();
    final label = orderStatusLabel(status);
    final scheme = theme.colorScheme;

    Color bgColor;
    Color textColor;

    if (s.isEmpty) {
      bgColor = scheme.surfaceContainerHighest;
      textColor = scheme.onSurfaceVariant;
    } else if (s == 'cancelled') {
      bgColor = scheme.error.withAlpha(15); // ~0.06
      textColor = scheme.error;
    } else if (s == 'shipped') {
      final base = scheme.secondary;
      bgColor = base.withAlpha(15); // ~0.06
      textColor = base;
    } else if (s == 'approved') {
      final base = scheme.primary;
      bgColor = base.withAlpha(15); // ~0.06
      textColor = base;
    } else if (s == 'new') {
      final base = scheme.primary;
      bgColor = scheme.surfaceContainerHighest.withAlpha(102); // ~0.4
      textColor = base;
    } else if (s == 'preparing') {
      final base = scheme.tertiary;
      bgColor = base.withAlpha(20); // ~0.08
      textColor = base;
    } else {
      bgColor = scheme.surfaceContainerHighest;
      textColor = scheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
