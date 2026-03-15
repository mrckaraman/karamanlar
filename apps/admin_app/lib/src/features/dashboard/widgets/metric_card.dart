import 'package:flutter/material.dart';

enum MetricTrendDirection { up, down }

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.description,
    this.trendDirection,
    this.trendText,
  });

  final String label;
  final String value;
  final String description;
  final MetricTrendDirection? trendDirection;
  final String? trendText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color? badgeBg;
    Color? badgeFg;
    IconData? badgeIcon;

    if (trendDirection != null && trendText != null) {
      if (trendDirection == MetricTrendDirection.up) {
        badgeBg = const Color(0xFFDCFCE7);
        badgeFg = const Color(0xFF166534);
        badgeIcon = Icons.arrow_upward_rounded;
      } else {
        badgeBg = const Color(0xFFFEE2E2);
        badgeFg = const Color(0xFFB91C1C);
        badgeIcon = Icons.arrow_downward_rounded;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                if (badgeBg != null &&
                    badgeFg != null &&
                    badgeIcon != null)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          badgeIcon,
                          size: 14,
                          color: badgeFg,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          trendText!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: badgeFg,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
