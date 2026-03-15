import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import 'orders_realtime_provider.dart';

final _customerOrderDetailProvider = FutureProvider.autoDispose
    .family<CustomerOrderDetail, String>((ref, orderId) async {
  return customerOrderRepository.fetchCustomerOrderDetail(orderId);
});

final _customerOrderItemsProvider = FutureProvider.autoDispose
    .family<List<CustomerOrderItem>, String>((ref, orderId) async {
  return customerOrderRepository.fetchCustomerOrderItems(orderId);
});

class _CustomerInvoiceLookup {
  const _CustomerInvoiceLookup({
    required this.id,
    required this.status,
  });

  final String id;
  final String status;
}

final _customerInvoiceByOrderProvider = FutureProvider.autoDispose
    .family<_CustomerInvoiceLookup?, String>((ref, orderId) async {
  // Müşteri tarafında read-only amaçla: siparişe bağlı fatura varsa döndür.
  // Not: AdminInvoiceRepository.findInvoiceIdByOrderId open/issued harici
  // statüleri null döndürebiliyor; customer tarafında iptal faturaları da
  // erişilebilir kılmak için burada doğrudan tablo sorgusu yapıyoruz.
  try {
    final dynamic row = await supabaseClient
        .from('invoices')
        .select('id, status')
        .eq('order_id', orderId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;

    final map = Map<String, dynamic>.from(row as Map);
    final id = (map['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    final status = (map['status'] ?? '').toString();

    return _CustomerInvoiceLookup(id: id, status: status);
  } catch (_) {
    return null;
  }
});

bool _isOpenLikeInvoiceStatus(String status) {
  final s = status.trim().toLowerCase();
  return s == 'open' || s == 'issued';
}

class CustomerOrderDetailPage extends ConsumerWidget {
  const CustomerOrderDetailPage({
    super.key,
    required this.orderId,
  });

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mevcut müşteri için realtime aboneliği aktif et.
    ref.watch(customerOrdersRealtimeProvider);

    // Güncellenen sipariş bu detay sayfasındaki id ise, provider'ları yenile.
    ref.listen<String?>(
      customerOrdersRealtimeLastOrderIdProvider,
      (previous, next) {
        if (next == null || next.isEmpty || next != orderId) {
          return;
        }
        ref.invalidate(_customerOrderDetailProvider(orderId));
        ref.invalidate(_customerOrderItemsProvider(orderId));
      },
    );

    final detailAsync = ref.watch(_customerOrderDetailProvider(orderId));
    final itemsAsync = ref.watch(_customerOrderItemsProvider(orderId));
    final invoiceAsync = ref.watch(
      _customerInvoiceByOrderProvider(orderId),
    );

    if (detailAsync.isLoading || itemsAsync.isLoading) {
      return const AppLoadingState();
    }

    if (detailAsync.hasError || itemsAsync.hasError) {
      final error = detailAsync.error ?? itemsAsync.error;
      return AppErrorState(
        message: 'Sipariş detayı yüklenemedi: $error',
        onRetry: () {
          ref.invalidate(_customerOrderDetailProvider(orderId));
          ref.invalidate(_customerOrderItemsProvider(orderId));
        },
      );
    }

    final detail = detailAsync.value;
    final items = itemsAsync.value ?? <CustomerOrderItem>[];
    final invoiceLookup = invoiceAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final invoiceId = invoiceLookup?.id;
    final invoiceStatus = invoiceLookup?.status;

    if (detail == null) {
      return AppErrorState(
        message: 'Sipariş detayı bulunamadı.',
        onRetry: () {
          ref.invalidate(_customerOrderDetailProvider(orderId));
          ref.invalidate(_customerOrderItemsProvider(orderId));
        },
      );
    }

    final theme = Theme.of(context);
    final orderTitle = _orderTitle(detail);
    final isCompleted =
        detail.status.trim().toLowerCase() == 'completed';
    final hasOpenInvoice = invoiceId != null &&
      invoiceId.isNotEmpty &&
      _isOpenLikeInvoiceStatus(invoiceStatus ?? '');

    return AppScaffold(
      title: 'Sipariş Detayı',
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_customerOrderDetailProvider(orderId));
          ref.invalidate(_customerOrderItemsProvider(orderId));
          await Future.wait([
            ref.read(_customerOrderDetailProvider(orderId).future),
            ref.read(_customerOrderItemsProvider(orderId).future),
          ]);
        },
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        orderTitle,
                                        style: theme
                                            .textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (detail.orderNo != null &&
                                        detail.orderNo!.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.copy_outlined,
                                          size: 18,
                                        ),
                                        tooltip:
                                            'Sipariş numarasını kopyala',
                                        onPressed: () async {
                                          final valueToCopy =
                                              detail.orderNo!.trim();
                                          await Clipboard.setData(
                                            ClipboardData(
                                              text: valueToCopy,
                                            ),
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Sipariş numarası kopyalandı.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        visualDensity:
                                            VisualDensity.compact,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.s4),
                                Text(
                                  _formatDate(detail.createdAt),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme
                                        .colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s8),
                          _buildStatusChip(detail.status),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Row(
                        children: [
                          Text(
                            'Toplam',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color:
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s8),
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () {
                              if (invoiceId != null &&
                                  invoiceId.isNotEmpty) {
                                context.go('/invoices/$invoiceId');
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Fatura henüz oluşmadı.'),
                                  ),
                                );
                              }
                            },
                            child: Row(
                              children: [
                                Text(
                                  _formatAmount(detail.totalAmount),
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (invoiceId != null &&
                                    invoiceId.isNotEmpty) ...[
                                  const SizedBox(
                                      width: AppSpacing.s4),
                                  Icon(
                                    Icons.open_in_new,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s8),
                        _StatusTimeline(status: detail.status),
                        if (isCompleted && hasOpenInvoice) ...[
                        const SizedBox(height: AppSpacing.s4),
                        Container(
                          padding:
                              const EdgeInsets.all(AppSpacing.s8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Fatura hazır',
                                      style: theme
                                          .textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(
                                        height: AppSpacing.s4),
                                    Text(
                                      'Fatura kesildi. Cari ekstreye yansıdı.',
                                      style: theme
                                          .textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    if (invoiceId.isNotEmpty) ...[
                                      const SizedBox(
                                          height: AppSpacing.s8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            context.go(
                                                '/invoices/$invoiceId');
                                          },
                                          icon: const Icon(
                                            Icons.open_in_new,
                                            size: 18,
                                          ),
                                          label:
                                              const Text('Faturayı Gör'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (detail.note != null &&
                          detail.note!.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          'Not',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          detail.note!.trim(),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                'Kalemler',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Expanded(
                child: items.isEmpty
                    ? const AppEmptyState(
                        title: 'Bu siparişte kalem bulunmuyor.',
                      )
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final qtyText =
                              _formatQuantity(item.quantity);
                          final unit = item.unitName.trim();
                          final unitPart =
                              unit.isEmpty ? qtyText : '$qtyText $unit';
                          final unitPriceText =
                              _formatAmount(item.unitPrice);
                          final lineTotalText =
                              _formatAmount(item.lineTotal);

                          return ListTile(
                            title: Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$unitPart × $unitPriceText',
                            ),
                            trailing: Text(
                              lineTotalText,
                              style: theme
                                  .textTheme.bodyMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _orderTitle(CustomerOrderDetail detail) {
  final orderNo = detail.orderNo;
  if (orderNo != null && orderNo.isNotEmpty) {
    return 'Sipariş #$orderNo';
  }
  return 'Sipariş';
}

String _formatAmount(double value) {
  return formatMoney(value);
}

String _formatDate(DateTime date) {
  return formatDate(date);
}

String _formatQuantity(double value) {
  if (value % 1 == 0) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(2);
}

Widget _buildStatusChip(String status) {
  final s = status.trim().toLowerCase();

  if (s.isEmpty) {
    return const AppStatusChip.inactive();
  }

  switch (s) {
    case 'cancelled':
      return const AppStatusChip.inactive();
    case 'completed':
    case 'approved':
    case 'shipped':
    case 'preparing':
    case 'new':
      return const AppStatusChip.active();
    default:
      return const AppStatusChip.active();
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = status.trim().toLowerCase();

    const steps = <String>[
      'new',
      'approved',
      'preparing',
      'shipped',
      'completed',
    ];

    final currentIndex = steps.indexOf(normalized);

    String labelFor(String key) {
      switch (key) {
        case 'new':
          return 'Yeni';
        case 'approved':
          return 'Onaylandı';
        case 'preparing':
          return 'Hazırlanıyor';
        case 'shipped':
          return 'Sevk';
        case 'completed':
          return 'Tamamlandı';
        default:
          return key;
      }
    }

    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= currentIndex
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          Column(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= currentIndex && currentIndex != -1
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: i <= currentIndex && currentIndex != -1
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                labelFor(steps[i]),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: i <= currentIndex && currentIndex != -1
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
