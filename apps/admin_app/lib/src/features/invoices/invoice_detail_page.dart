import 'package:core/core.dart' hide isValidUuid;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import '../../utils/uuid_utils.dart';
import '../customers/customer_finance_providers.dart' as finance;
import 'invoice_providers.dart';

class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isValidUuid(invoiceId)) {
      return const AppScaffold(
        title: 'Fatura Detayı',
        body: Center(
          child: Text('Geçersiz fatura ID bilgisi.'),
        ),
      );
    }

    final detailAsync = ref.watch(invoiceDetailProvider(invoiceId));
    final detailForActions = detailAsync.asData?.value;
    final customerIdForActions = detailForActions?.customerId;
    final canOpenStatement =
        detailForActions != null &&
        customerIdForActions != null &&
        customerIdForActions.isNotEmpty;

    return AppScaffold(
      title: 'Fatura Detayı',
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: canOpenStatement
              ? () {
                  context.go(
                    '/customers/$customerIdForActions/statement',
                  );
                }
              : null,
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Cari Ekstre'),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () async {
            final updated = await context.push<bool>(
              '/invoices/$invoiceId/edit',
            );

            if (updated == true) {
              final detail = await ref.refresh(
                invoiceDetailProvider(invoiceId).future,
              );

              final refreshedItems = await ref.refresh(
                invoiceItemsProvider(invoiceId).future,
              );

              // refreshedItems'i kullanmıyoruz ama sonuç alınmış oluyor
              if (refreshedItems.isEmpty && detail.id.isEmpty) {
                // no-op, sadece lint'i susturmak için erişim
              }

              final customerId = detail.customerId;
              if (customerId != null && customerId.isNotEmpty) {
                ref.invalidate(finance.customerBalanceProvider(customerId));
              }
            }
          },
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('Düzenle'),
        ),
      ],
      body: detailAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(
          message: 'Fatura detayı yüklenemedi: $e',
          onRetry: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
        ),
        data: (detail) {
          final itemsAsync = ref.watch(invoiceItemsProvider(detail.id));

          final dateText = formatDate(detail.effectiveDate);
          final totalText = formatMoney(detail.totalAmount);
          final paidText = formatMoney(detail.paidAmount);
          final remainingText =
              formatMoney(detail.remainingAmount.clamp(0, double.infinity));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.invoiceNo.isEmpty
                                ? 'Fatura'
                                : 'Fatura ${detail.invoiceNo}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            'Tarih: $dateText',
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
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _InvoiceStatusChip(status: detail.status),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          totalText,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: AppSpacing.cardPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Toplam',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                totalText,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: AppSpacing.cardPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ödenen',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                paidText,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: AppSpacing.cardPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kalan',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                remainingText,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                if (detail.orderId != null && detail.orderId!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: () {
                        context.go('/orders/${detail.orderId}');
                      },
                      child: const Text('Siparişi aç'),
                    ),
                  ),
                if (detail.orderId != null && detail.orderId!.isNotEmpty)
                  const SizedBox(height: AppSpacing.s12),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kalemler',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          itemsAsync.when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            error: (e, _) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kalemler yüklenemedi.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                ),
                                const SizedBox(height: AppSpacing.s4),
                                Text(
                                  '$e',
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: AppSpacing.s8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => ref.invalidate(
                                      invoiceItemsProvider(detail.id),
                                    ),
                                    child: const Text('Tekrar dene'),
                                  ),
                                ),
                              ],
                            ),
                            data: (items) {
                              if (items.isEmpty) {
                                return const Text(
                                  'Bu fatura için kalem bulunamadı.',
                                );
                              }

                              return Expanded(
                                child: ListView.separated(
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final item = items[index];
                                    final qtyText =
                                        '${formatQtyTr(item.qty)} ${item.unitName}';
                                    final lineTotalText =
                                        formatMoney(item.lineTotal);

                                    return ListTile(
                                      title: Text(item.stockName),
                                      subtitle: Text(qtyText),
                                      trailing: Text(lineTotalText),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InvoiceStatusChip extends StatelessWidget {
  const _InvoiceStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status.trim().toLowerCase();
    final label = _statusLabel(status);

    Color bgColor;
    Color textColor;

    if (s.isEmpty) {
      bgColor = theme.colorScheme.surfaceContainerHighest;
      textColor = theme.colorScheme.onSurfaceVariant;
    } else if (s == 'cancelled' || s == 'refunded') {
      bgColor = Colors.red.withValues(alpha: 0.06);
      textColor = Colors.red.shade700;
    } else {
      bgColor = theme.colorScheme.primary.withValues(alpha: 0.06);
      textColor = theme.colorScheme.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _statusLabel(String status) {
  final s = status.toLowerCase();
  switch (s) {
    case 'issued':
      return 'Kesildi';
    case 'sent':
      return 'Kesildi';
    case 'paid':
      return 'Kesildi';
    case 'cancelled':
      return 'İptal';
    case 'refunded':
      return 'İade';
    default:
      if (s.isEmpty) return 'Bilinmiyor';
      return status;
  }
}
