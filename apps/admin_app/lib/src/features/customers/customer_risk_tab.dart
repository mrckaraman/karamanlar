import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';

import 'customer_finance_providers.dart';
import 'customer_general_tab.dart';

class CustomerRiskTab extends ConsumerWidget {
  const CustomerRiskTab({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(customerBalanceProvider(customerId));
    final detailAsync = ref.watch(customerDetailProvider(customerId));
    final agingAsync = ref.watch(customerAgingProvider(customerId));

    if (balanceAsync.isLoading || detailAsync.isLoading || agingAsync.isLoading) {
      return const AppLoadingState();
    }

    if (balanceAsync.hasError) {
      return AppErrorState(
        message: 'Bakiye bilgisi yüklenemedi: ${balanceAsync.error}',
        onRetry: () => ref.invalidate(customerBalanceProvider(customerId)),
      );
    }
    if (detailAsync.hasError) {
      return AppErrorState(
        message: 'Cari kartı yüklenemedi: ${detailAsync.error}',
        onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
      );
    }
    if (agingAsync.hasError) {
      return AppErrorState(
        message: 'Vade bilgisi yüklenemedi: ${agingAsync.error}',
        onRetry: () => ref.invalidate(customerAgingProvider(customerId)),
      );
    }

    final balance = balanceAsync.value!;
    final customer = detailAsync.value!;
    final agingRows = agingAsync.value ?? const <AgingRow>[];

    final limit = customer.limitAmount ?? 0;
    final net = balance.net;

    final overdueAmount = agingRows
        .where((r) => r.bucket != '0-7')
        .fold<double>(0, (sum, r) => sum + r.amount);

    final hasLimitExceeded = limit > 0 && net > limit;
    final hasOverdue = overdueAmount > 0;

    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bakiye Özeti',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  _SummaryRow(
                    label: 'Toplam borç',
                    value: balance.totalDebit,
                  ),
                  _SummaryRow(
                    label: 'Toplam alacak',
                    value: balance.totalCredit,
                  ),
                  _SummaryRow(
                    label: 'Net bakiye (borç - alacak)',
                    value: net,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  _SummaryRow(
                    label: 'Kredi limiti',
                    value: limit,
                  ),
                  _SummaryRow(
                    label: 'Vade (gün)',
                    value: (customer.dueDays ?? 0).toDouble(),
                    isInteger: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uyarılar',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  if (!hasLimitExceeded && !hasOverdue)
                    const Text('Önemli bir risk uyarısı yok.'),
                  if (hasLimitExceeded)
                    const Text(
                      'Limit aşıldı: Net borç tanımlı kredi limitinin üzerinde.',
                      style: TextStyle(color: Colors.red),
                    ),
                  if (hasOverdue)
                    const Text(
                      'Vadesi geçmiş borç var: 8+ gün bucketlarında bakiye bulunuyor.',
                      style: TextStyle(color: Colors.orange),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Risk notu',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    (customer.riskNote ?? '').isEmpty
                        ? 'Risk notu girilmemiş.'
                        : customer.riskNote!,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        GoRouter.of(context)
                            .go('/customers/${customer.id}/edit');
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Cari kartını düzenle'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isInteger = false,
  });

  final String label;
  final double value;
  final bool isInteger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
              Text(
                isInteger ? value.toInt().toString() : formatMoney(value),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
