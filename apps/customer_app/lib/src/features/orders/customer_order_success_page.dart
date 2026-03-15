import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CustomerOrderSuccessPage extends StatelessWidget {
  const CustomerOrderSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Siparişiniz Alındı',
      body: Center(
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 64,
              ),
              const SizedBox(height: AppSpacing.s12),
              const Text(
                'Siparişiniz başarıyla alındı.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s8),
              const Text(
                'Fatura kesildiğinde "Faturalarım" ve "Cari / Ekstre" ekranlarından takip edebilirsiniz.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.s20),
              PrimaryButton(
                label: 'Faturalarımı Gör',
                icon: Icons.receipt_long_outlined,
                onPressed: () => context.go('/invoices'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
