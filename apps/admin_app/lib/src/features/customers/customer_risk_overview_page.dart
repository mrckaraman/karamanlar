import 'package:core/core.dart';
import 'package:flutter/material.dart';

class CustomerRiskOverviewPage extends StatelessWidget {
  const CustomerRiskOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Risk & Limit',
      icon: Icons.warning,
      subtitle: 'Cari risk ve limit özet ekranı hazırlanıyor',
      child: Center(
        child: Text(
          'Risk & Limit ekranı hazırlanıyor.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
