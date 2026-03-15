import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters_tr.dart';
import '../pdf/pdf_builders.dart';
import '../pdf/pdf_share.dart';

final _customerInvoiceDetailProvider = FutureProvider.autoDispose
    .family<AdminInvoiceDetail, String>((ref, invoiceId) async {
  DateTime? parseDt(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return DateTime.tryParse(value.toString());
  }

  final dynamic row = await supabaseClient
      .from('invoices')
      .select()
      .eq('id', invoiceId)
      .maybeSingle();

  if (row == null) {
    throw Exception('Invoice not found');
  }

  final map = Map<String, dynamic>.from(row as Map);

  assert(() {
    if (kDebugMode) {
      debugPrint(
        '[CUSTOMER][InvoiceDetail] id=$invoiceId status=${map['status']} '
        'invoice_no=${map['invoice_no']} customer_id=${map['customer_id']} '
        'total=${map['total_amount']} paid=${map['paid_amount']}',
      );
    }
    return true;
  }());

  final dynamic rawOrderId = map['order_id'];
  final String? orderId = rawOrderId == null
      ? null
      : rawOrderId.toString().trim().isEmpty
          ? null
          : rawOrderId.toString();

  final dynamic rawCustomerId = map['customer_id'];
  final String? customerId = rawCustomerId == null
      ? null
      : rawCustomerId.toString().trim().isEmpty
          ? null
          : rawCustomerId.toString();

  return AdminInvoiceDetail(
    id: (map['id'] ?? '').toString(),
    invoiceNo: (map['invoice_no'] ?? '').toString(),
    status: (map['status'] ?? '').toString(),
    totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
    paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0,
    invoiceDate: parseDt(map['invoice_date']),
    issuedAt: parseDt(map['issued_at']),
    createdAt: parseDt(map['created_at']),
    orderId: orderId,
    customerId: customerId,
  );
});

final _customerInvoiceItemsProvider = FutureProvider.autoDispose
    .family<List<AdminInvoiceItemEntry>, String>((ref, invoiceId) async {
  final dynamic data = await supabaseClient
      .from('invoice_items')
      .select()
      .eq('invoice_id', invoiceId);

  final rows = (data as List<dynamic>)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  assert(() {
    if (kDebugMode) {
      debugPrint(
        '[CUSTOMER][InvoiceItems] invoiceId=$invoiceId rows=${rows.length}',
      );
      if (rows.isNotEmpty) {
        final sample = rows.first;
        debugPrint(
          '[CUSTOMER][InvoiceItems] sample keys=${sample.keys.toList()}',
        );
      }
    }
    return true;
  }());

  return rows.map((row) {
    final stockId = (row['stock_id'] as String?) ?? '';
    final stockName = (row['stock_name'] as String?) ?? 'Bilinmeyen Stok';
    final qty = (row['qty'] as num?)?.toDouble() ?? 0;
    final unitName = (row['unit_name'] as String?) ?? '';
    final unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0;
    final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;

    return AdminInvoiceItemEntry(
      stockId: stockId,
      stockName: stockName,
      qty: qty,
      unitName: unitName,
      unitPrice: unitPrice,
      lineTotal: lineTotal,
    );
  }).toList();
});

final _invoicePdfLoadingProvider =
    StateProvider.autoDispose.family<bool, String>((ref, invoiceId) => false);

class CustomerInvoiceDetailPage extends ConsumerWidget {
  const CustomerInvoiceDetailPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(_customerInvoiceDetailProvider(invoiceId));
    final itemsAsync = ref.watch(_customerInvoiceItemsProvider(invoiceId));
    final isPdfLoading = ref.watch(_invoicePdfLoadingProvider(invoiceId));

    if (detailAsync.isLoading || itemsAsync.isLoading) {
      return const AppLoadingState();
    }

    if (detailAsync.hasError || itemsAsync.hasError) {
      final error = detailAsync.error ?? itemsAsync.error;
      return AppErrorState(
        message: 'Fatura detayı yüklenemedi: $error',
        onRetry: () {
          ref.invalidate(_customerInvoiceDetailProvider(invoiceId));
          ref.invalidate(_customerInvoiceItemsProvider(invoiceId));
        },
      );
    }

    final detail = detailAsync.value;
    final items = itemsAsync.value ?? <AdminInvoiceItemEntry>[];

    if (detail == null) {
      return AppErrorState(
        message: 'Fatura detayı bulunamadı.',
        onRetry: () {
          ref.invalidate(_customerInvoiceDetailProvider(invoiceId));
          ref.invalidate(_customerInvoiceItemsProvider(invoiceId));
        },
      );
    }

    final status = detail.status.trim().toLowerCase();
    final isCancelled = status == 'cancelled';

    final theme = Theme.of(context);
    final dateText = formatDate(detail.effectiveDate);
    final totalText = formatMoney(detail.totalAmount);
    final paidText = formatMoney(detail.paidAmount);
    final remainingText =
        formatMoney(detail.remainingAmount.clamp(0, double.infinity));

    Future<void> shareInvoicePdf({required String text}) async {
      if (isPdfLoading) return;
      if (isCancelled) return;

      final notifier =
          ref.read(_invoicePdfLoadingProvider(invoiceId).notifier);
      notifier.state = true;
      try {
        final header = InvoicePdfHeader(
          invoiceNo: detail.invoiceNo,
          date: detail.effectiveDate,
          total: detail.totalAmount,
          paid: detail.paidAmount,
          remaining: detail.remainingAmount,
        );

        final pdfItems = items
            .map(
              (e) => InvoicePdfItem(
                name: e.stockName,
                qty: e.qty,
                unitName: e.unitName,
                unitPrice: e.unitPrice,
                lineTotal: e.lineTotal,
              ),
            )
            .toList();

        final bytes = await buildInvoicePdf(
          header,
          pdfItems,
          'Cari',
        );

        final fileName =
            'fatura_${detail.invoiceNo.isEmpty ? detail.id : detail.invoiceNo}.pdf';

        await saveAndSharePdf(
          bytes,
          fileName,
          subject: detail.invoiceNo.isEmpty
              ? 'Fatura'
              : 'Fatura ${detail.invoiceNo}',
          text: text,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF oluşturulamadı: ${e.toString()}'),
          ),
        );
      } finally {
        notifier.state = false;
      }
    }

    return AppScaffold(
      title: 'Fatura Detayı',
      actions: [
        IconButton(
          tooltip: 'PDF paylaş',
          onPressed: (isPdfLoading || isCancelled)
              ? null
              : () => shareInvoicePdf(text: 'Faturanızın PDF kopyası.'),
          icon: isPdfLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
        ),
        IconButton(
          tooltip: 'WhatsApp ile paylaş',
          onPressed: (isPdfLoading || isCancelled)
              ? null
              : () => shareInvoicePdf(
                    text:
                        'Faturanızın PDF kopyası. Paylaşım ekranından WhatsApp seçebilirsiniz.',
                  ),
          icon: const Icon(Icons.chat_outlined),
        ),
      ],
      body: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCancelled) ...[
              const _CancelledInvoiceBadge(),
              const SizedBox(height: AppSpacing.s12),
            ],
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        'Tarih: $dateText',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _CustomerInvoiceStatusChip(status: detail.status),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      totalText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: 'Toplam',
                    value: totalText,
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: _MetricCard(
                    title: 'Ödenen',
                    value: paidText,
                    icon: Icons.payments_outlined,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: _MetricCard(
                    title: 'Kalan',
                    value: remainingText,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Kalemler',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            if (items.isEmpty)
              const AppEmptyState(
                title: 'Bu fatura için kalem bulunamadı.',
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.s12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final qtyText =
                      '${_formatQuantity(item.qty)} ${item.unitName}';
                    final unitPriceText = _formatAmount(item.unitPrice);
                    final lineTotalText = _formatAmount(item.lineTotal);

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: AppSpacing.cardPadding,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.stockName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s4),
                                  Text(
                                    '$qtyText × $unitPriceText',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: theme
                                          .colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s12),
                            Text(
                              lineTotalText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerInvoiceStatusChip extends StatelessWidget {
  const _CustomerInvoiceStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status.trim().toLowerCase();

    String label;
    if (s == 'cancelled' || s == 'refunded') {
      label = 'İptal / İade';
    } else {
      // Müşteri tarafında "Ödendi" ifadesi kullanılmaz,
      // tüm aktif faturalar "Kesildi" olarak gösterilir.
      label = 'Kesildi';
    }

    Color bgColor;
    Color textColor;

    if (s == 'cancelled' || s == 'refunded') {
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

class _CancelledInvoiceBadge extends StatelessWidget {
  const _CancelledInvoiceBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cancel_outlined,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              'Bu fatura iptal edilmiştir',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatAmount(double value) {
  return formatMoney(value);
}

String _formatQuantity(num value) {
  final doubleVal = value.toDouble();
  if (doubleVal == doubleVal.roundToDouble()) {
    return doubleVal.toInt().toString();
  }
  return doubleVal.toStringAsFixed(2);
}
