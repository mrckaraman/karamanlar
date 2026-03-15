import 'package:flutter/material.dart';

import 'app_action_card.dart';

/// Admin menü ve dashboard kartları için ortak widget.
class AdminDashboardCard extends StatelessWidget {
  const AdminDashboardCard({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? value;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppActionCard(
      icon: icon,
      title: title,
      value: value,
      hint: subtitle,
      onTap: onTap,
    );
  }
}
