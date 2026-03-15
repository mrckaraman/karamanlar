import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';

final _adminSalesListProvider = FutureProvider.autoDispose
    .family<List<AdminSaleListEntry>, String?>((ref, batchId) async {
  return adminSalesRepository.fetchSales(batchId: batchId);
});

class SalesListPage extends ConsumerWidget {
  const SalesListPage({super.key, this.batchId});

  final String? batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(_adminSalesListProvider(batchId));

    return AppScaffold(
      title: 'Satışlar',
      body: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Satış Listesi',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                if (batchId != null && batchId!.isNotEmpty)
                  InputChip(
                    label: Text('Batch: $batchId'),
                    onDeleted: () {
                      // Batch filtresini temizleyerek tüm satışları göster.
                      context.go('/sales');
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Expanded(
              child: salesAsync.when(
                loading: () => const AppLoadingState(),
                error: (e, _) => AppErrorState(
                  message: 'Satışlar yüklenemedi: $e',
                  onRetry: () {
                    ref.invalidate(_adminSalesListProvider(batchId));
                  },
                ),
                data: (sales) {
                  if (sales.isEmpty) {
                    return const AppEmptyState(
                      title: 'Gösterilecek satış yok',
                      subtitle:
                          'Filtre kriterlerine göre henüz satış kaydı bulunamadı.',
                    );
                  }

                  return ListView.separated(
                    itemCount: sales.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final sale = sales[index];
                      final dateText = _formatDate(sale.createdAt);
                      final totalText = _formatAmount(sale.totalAmount);

                      return AppListTile(
                        title: sale.customerName,
                        subtitle: '$dateText • Toplam: $totalText',
                        // İleride detay sayfası eklenecekse burada navigation
                        // bağlanabilir.
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return formatDate(date);
}

String _formatAmount(double value) {
  return formatMoney(value);
}
