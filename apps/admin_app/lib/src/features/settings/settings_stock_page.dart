import 'package:core/core.dart';
import 'package:flutter/material.dart';

class SettingsStockPage extends StatelessWidget {
  const SettingsStockPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      title: 'Stok Tanımları',
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Birimler, stok grupları ve KDV oranı tanımları burada yönetilecek.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s24),
            const Center(
              child: Text('Stok tanımları - Yakında'),
            ),
          ],
        ),
      ),
    );
  }
}
