import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters_tr.dart';
import 'widgets/order_status_chip.dart';

final _shipmentListProvider = FutureProvider.autoDispose
    .family<List<AdminOrderDetail>, List<String>>((ref, ids) async {
  if (ids.isEmpty) {
    return const <AdminOrderDetail>[];
  }

  final futures = ids
      .map((id) => adminOrderRepository.fetchOrderDetail(id))
      .toList(growable: false);
  return Future.wait(futures);
});

class ShipmentListPage extends ConsumerWidget {
  const ShipmentListPage({
    super.key,
    required this.orderIds,
  });

  final List<String> orderIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDetails = ref.watch(_shipmentListProvider(orderIds));

    return AppScaffold(
      title: 'Sevk Listesi',
      body: asyncDetails.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(
          message: 'Sevk listesi yüklenemedi: $e',
          onRetry: () => ref.invalidate(_shipmentListProvider(orderIds)),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return const AppEmptyState(
              title: 'Seçili sipariş bulunamadı.',
              subtitle:
                  'Lütfen sevk listesi için en az bir sipariş seçip tekrar deneyin.',
            );
          }

          final now = DateTime.now();
          final dateText = formatDate(now);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sevk Listesi',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        'Tarih: $dateText',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Yazdır özelliği yakında eklenecek.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Yazdır'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              Expanded(
                child: ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final orderNo = order.orderNo;
                    final orderLabel =
                        orderNo != null ? 'Sipariş #$orderNo' : 'Sipariş';
                    final note = order.note?.trim();

                    return Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.s12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    order.customerName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.s8),
                                OrderStatusChip(status: order.status),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s4),
                            Text(
                              orderLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            if (note != null && note.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                note,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.s8),
                            Column(
                              children: [
                                for (final item in order.items)
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(item.name),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          '${formatQtyTr(item.quantity)} ${item.unit}',
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Toplam ${orders.length} sipariş',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
