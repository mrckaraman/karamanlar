import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters_tr.dart';
import 'customer_finance_providers.dart';

class CustomerAgingTab extends ConsumerWidget {
  const CustomerAgingTab({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agingAsync = ref.watch(customerAgingProvider(customerId));

    return agingAsync.when(
      loading: () => const AppLoadingState(),
      error: (e, _) => AppErrorState(
        message: 'Vade / aging bilgileri yüklenemedi: ${AppException.messageOf(e)}',
        onRetry: () => ref.invalidate(customerAgingProvider(customerId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const AppEmptyState(
            title: 'Vade bilgisi yok',
            subtitle: 'Bu cari için açık bakiye bulunmuyor.',
          );
        }

        final overdueAmount = rows
            .where((r) => r.bucket != '0-7')
            .fold<double>(0, (sum, r) => sum + r.amount);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.s8,
                mainAxisSpacing: AppSpacing.s8,
                children: rows
                    .map(
                      (r) => Card(
                        child: Padding(
                          padding: AppSpacing.cardPadding,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.bucket,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                _formatAmount(r.amount),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text('${r.count} adet'),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Toplam vadesi geçmiş'),
                    Text(
                      _formatAmount(overdueAmount),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _formatAmount(double value) {
  return formatMoney(value);
}
