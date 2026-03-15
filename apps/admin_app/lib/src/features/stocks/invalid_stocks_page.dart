import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _invalidStocksFutureProvider =
    FutureProvider.autoDispose<List<InvalidStock>>((ref) async {
  return stockRepository.fetchInvalidStocks();
});

class InvalidStocksPage extends ConsumerWidget {
  const InvalidStocksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncInvalidStocks = ref.watch(_invalidStocksFutureProvider);

    return AdminPageScaffold(
      title: 'Bozuk Stoklar',
      icon: Icons.error_outline,
      subtitle: 'Barkodu olan ama paket/koli katsayısı eksik stoklar.',
      child: asyncInvalidStocks.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => const AppErrorState(
          message: 'Bozuk stoklar yüklenemedi. Lütfen tekrar deneyin.',
        ),
        data: (items) {
          if (items.isEmpty) {
            return const AppEmptyState(
              title: 'Bozuk stok yok 🎉',
              subtitle: 'Tüm stokların barkod ve katsayı bilgileri tutarlı.',
            );
          }

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = items[index];

              String buildReason(InvalidStock s) {
                switch (s.invalidReason) {
                  case 'PACK_BARCODE_WITHOUT_PACK_QTY':
                    return 'Paket barkodu var ama paket içi adet eksik.';
                  case 'BOX_BARCODE_WITHOUT_BOX_QTY':
                    return 'Koli barkodu var ama koli içi adet eksik.';
                  default:
                    return s.invalidReason;
                }
              }

              final reasonText = buildReason(s);

              final details = <String>[];
              if ((s.packBarcode ?? '').trim().isNotEmpty) {
                details.add('Paket barkodu: ${s.packBarcode} (adet: ${s.packQty ?? '-'})');
              }
              if ((s.boxBarcode ?? '').trim().isNotEmpty) {
                details.add('Koli barkodu: ${s.boxBarcode} (adet: ${s.boxQty ?? '-'})');
              }

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s8,
                  vertical: AppSpacing.s4,
                ),
                child: ListTile(
                  title: Text('${s.code} - ${s.name}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reasonText),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(details.join('  |  ')),
                      ],
                    ],
                  ),
                  trailing: TextButton.icon(
                    onPressed: () {
                      GoRouter.of(context).go('/stocks/${s.id}/edit');
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Düzenle'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
