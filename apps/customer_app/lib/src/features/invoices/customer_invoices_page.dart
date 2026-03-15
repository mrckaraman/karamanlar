import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';

enum CustomerInvoiceStage { open, overdue, cancelledOrRefunded }

extension CustomerInvoiceStageX on CustomerInvoiceStage {
  String get label {
    switch (this) {
      case CustomerInvoiceStage.open:
        return 'Açık';
      case CustomerInvoiceStage.overdue:
        return 'Geciken';
      case CustomerInvoiceStage.cancelledOrRefunded:
        return 'İptal/İade';
    }
  }

  List<String> get baseStatuses {
    switch (this) {
      case CustomerInvoiceStage.open:
        // Açık faturalar için open / issued statülerini takip et.
        return <String>['open', 'issued'];
      case CustomerInvoiceStage.overdue:
        // Geciken faturalar da aynı statü grubundan gelir,
        // asıl ayrım client-side tarih ile yapılır.
        return <String>['open', 'issued'];
      case CustomerInvoiceStage.cancelledOrRefunded:
        // Customer UI'da iptal edilen faturaları göstermiyoruz.
        return <String>['refunded'];
    }
  }
}

enum CustomerInvoiceDateFilter { all, last7Days, last30Days, thisMonth }

extension CustomerInvoiceDateFilterX on CustomerInvoiceDateFilter {
  String get label {
    switch (this) {
      case CustomerInvoiceDateFilter.all:
        return 'Tümü';
      case CustomerInvoiceDateFilter.last7Days:
        return 'Son 7 gün';
      case CustomerInvoiceDateFilter.last30Days:
        return 'Son 30 gün';
      case CustomerInvoiceDateFilter.thisMonth:
        return 'Bu ay';
    }
  }
}

final _customerInvoiceStageProvider =
    StateProvider<CustomerInvoiceStage>((ref) => CustomerInvoiceStage.open);

final _customerInvoiceSearchProvider = StateProvider<String>((ref) => '');

final _customerInvoiceDateFilterProvider = StateProvider<CustomerInvoiceDateFilter>(
  (ref) => CustomerInvoiceDateFilter.all,
);

final customerInvoicesProvider = FutureProvider.autoDispose<
    List<CustomerInvoiceListEntry>>((ref) async {
  final stage = ref.watch(_customerInvoiceStageProvider);
  final search = ref.watch(_customerInvoiceSearchProvider).trim();
  final dateFilter = ref.watch(_customerInvoiceDateFilterProvider);
  final customerId = ref.watch(customerIdProvider);

  if (customerId == null || customerId.isEmpty) {
    return <CustomerInvoiceListEntry>[];
  }

  final dynamic data = await supabaseClient
      .from('invoices')
      .select()
      .eq('customer_id', customerId)
      .order('invoice_date', ascending: false);

  final invoices = (data as List<dynamic>)
      .map((e) => CustomerInvoiceListEntry.fromMap(
            Map<String, dynamic>.from(e as Map),
          ))
      .toList();

  assert(() {
    if (kDebugMode) {
      final statusCounts = <String, int>{};
      for (final inv in invoices) {
        final s = inv.status.trim().toLowerCase();
        statusCounts[s] = (statusCounts[s] ?? 0) + 1;
      }
      final cancelledCount = statusCounts['cancelled'] ?? 0;
      debugPrint(
        '[CUSTOMER][Invoices] fetched=${invoices.length} '
        'cancelledInResult=$cancelledCount statuses=$statusCounts',
      );
    }
    return true;
  }());

  final today = _today();

  final searchLower = search.toLowerCase();

  // Fetch sonrası filtreleme.
  final visible = invoices
      .where((i) => i.status.toLowerCase() != 'paid')
      .where((i) {
        if (searchLower.isEmpty) return true;
        return i.invoiceNo.toLowerCase().contains(searchLower);
      })
      .where((i) {
        // Sekme filtreleri: statü + (basit) gecikme heuristiği.
        if (stage == CustomerInvoiceStage.cancelledOrRefunded) {
          final s = i.status.toLowerCase();
          return s == 'cancelled' || s == 'refunded';
        }
        return _matchesStage(i, stage, today);
      })
      .toList();

  return _applyDateFilter(visible, dateFilter, today);
});

class CustomerInvoicesPage extends ConsumerWidget {
  const CustomerInvoicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stage = ref.watch(_customerInvoiceStageProvider);
    final dateFilter = ref.watch(_customerInvoiceDateFilterProvider);
    final invoicesAsync = ref.watch(customerInvoicesProvider);

    return AppScaffold(
      title: 'Faturalarım',
      body: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Faturalarım',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                invoicesAsync.maybeWhen(
                  data: (list) {
                    final total = list.fold<double>(
                      0,
                      (prev, e) => prev + e.totalAmount,
                    );
                    if (total <= 0) return const SizedBox.shrink();
                    return Text(
                      'Toplam: ${formatMoney(total)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.8),
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AppSearchField(
                        hintText: 'Fatura no ara',
                        padded: false,
                        onChanged: (value) => ref
                            .read(_customerInvoiceSearchProvider.notifier)
                            .state = value,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    DropdownButton<CustomerInvoiceStage>(
                      value: stage,
                      onChanged: (value) {
                        if (value == null) return;
                        ref
                            .read(_customerInvoiceStageProvider.notifier)
                            .state = value;
                      },
                      items: CustomerInvoiceStage.values
                          .map(
                            (s) => DropdownMenuItem<
                                CustomerInvoiceStage>(
                              value: s,
                              child: Text(s.label),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    DropdownButton<CustomerInvoiceDateFilter>(
                      value: dateFilter,
                      onChanged: (value) {
                        if (value == null) return;
                        ref
                            .read(_customerInvoiceDateFilterProvider.notifier)
                            .state = value;
                      },
                      items: CustomerInvoiceDateFilter.values
                          .map(
                            (f) => DropdownMenuItem<
                                CustomerInvoiceDateFilter>(
                              value: f,
                              child: Text(f.label),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Expanded(
              child: invoicesAsync.when(
                loading: () => const AppLoadingState(),
                error: (e, _) => AppErrorState(
                  message: 'Faturalar yüklenemedi: $e',
                  onRetry: () => ref.invalidate(customerInvoicesProvider),
                ),
                data: (invoices) {
                  if (invoices.isEmpty) {
                    return AppEmptyState(
                      title: 'Henüz fatura yok.',
                      subtitle:
                          'Sipariş tamamlanınca faturalar burada görünür.',
                      icon: Icons.receipt_long_outlined,
                      action: FilledButton.icon(
                        onPressed: () => context.go('/orders'),
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: const Text('Siparişlerime git'),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: invoices.length,
                    padding: const EdgeInsets.only(bottom: AppSpacing.s16),
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.s12),
                    itemBuilder: (context, index) {
                      final invoice = invoices[index];
                      final subtitle = _buildSubtitle(invoice);
                      final isOverdue = _isOverdue(invoice, _today());
                      final isCancelled =
                          invoice.status.trim().toLowerCase() == 'cancelled';

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            context.go('/invoices/${invoice.id}');
                          },
                          child: Padding(
                            padding:
                                const EdgeInsets.all(AppSpacing.s12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        invoice.invoiceNo.isEmpty
                                            ? 'Fatura'
                                            : invoice.invoiceNo,
                                        style: theme
                                            .textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(
                                          height: AppSpacing.s4),
                                      Text(
                                        subtitle,
                                        style: theme
                                            .textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.s12),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatMoney(invoice.totalAmount),
                                      style: theme
                                          .textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(
                                        height: AppSpacing.s4),
                                    if (isCancelled)
                                      const _CancelledInvoiceBadge()
                                    else
                                      _CustomerInvoiceStatusChip(
                                        status: invoice.status,
                                        isOverdue: isOverdue,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
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

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

bool _isOverdue(CustomerInvoiceListEntry invoice, DateTime today) {
  final status = invoice.status.toLowerCase();
  if (status == 'paid' || status == 'cancelled' || status == 'refunded') {
    return false;
  }
  final dateOnly = DateTime(
    invoice.issuedAt.year,
    invoice.issuedAt.month,
    invoice.issuedAt.day,
  );
  return dateOnly.isBefore(today);
}

bool _isCustomerInvoiceOpenLike(String status) {
  final s = status.trim().toLowerCase();
  return s == 'open' || s == 'issued';
}

bool _matchesStage(
  CustomerInvoiceListEntry invoice,
  CustomerInvoiceStage stage,
  DateTime today,
) {
  final status = invoice.status.toLowerCase();

  switch (stage) {
    case CustomerInvoiceStage.open:
      if (_isCustomerInvoiceOpenLike(status)) {
        // Açık sekmesi: due_date >= today AND status in ('open','issued').
        return !_isOverdue(invoice, today);
      }
      return false;
    case CustomerInvoiceStage.overdue:
      if (_isCustomerInvoiceOpenLike(status)) {
        // Geciken sekmesi: due_date < today AND status in ('open','issued').
        return _isOverdue(invoice, today);
      }
      return false;
    case CustomerInvoiceStage.cancelledOrRefunded:
      return status == 'cancelled' || status == 'refunded';
  }
}

List<CustomerInvoiceListEntry> _applyDateFilter(
  List<CustomerInvoiceListEntry> source,
  CustomerInvoiceDateFilter filter,
  DateTime today,
) {
  if (filter == CustomerInvoiceDateFilter.all) {
    return source;
  }

  DateTime toDate(DateTime value) => DateTime(value.year, value.month, value.day);

  switch (filter) {
    case CustomerInvoiceDateFilter.all:
      return source;
    case CustomerInvoiceDateFilter.last7Days:
      final start = today.subtract(const Duration(days: 7));
      return source
          .where((i) => toDate(i.issuedAt).isAfter(start) ||
              toDate(i.issuedAt).isAtSameMomentAs(start))
          .toList();
    case CustomerInvoiceDateFilter.last30Days:
      final start = today.subtract(const Duration(days: 30));
      return source
          .where((i) => toDate(i.issuedAt).isAfter(start) ||
              toDate(i.issuedAt).isAtSameMomentAs(start))
          .toList();
    case CustomerInvoiceDateFilter.thisMonth:
      final start = DateTime(today.year, today.month, 1);
      final end = today.month == 12
        ? DateTime(today.year + 1, 1, 1)
        : DateTime(today.year, today.month + 1, 1);
      return source
          .where((i) =>
              (toDate(i.issuedAt).isAtSameMomentAs(start) ||
                  toDate(i.issuedAt).isAfter(start)) &&
              toDate(i.issuedAt).isBefore(end))
          .toList();
  }
}

String _buildSubtitle(CustomerInvoiceListEntry invoice) {
  final dateText = formatDate(invoice.issuedAt);
  final orderShort = _shortOrder(invoice.orderId);
  if (orderShort.isEmpty) {
    return 'Tarih: $dateText';
  }
  return 'Tarih: $dateText • Sipariş: $orderShort';
}

String _shortOrder(String? orderId) {
  if (orderId == null || orderId.isEmpty) return '';
  if (orderId.length <= 8) return orderId;
  return '#${orderId.substring(0, 4)}…${orderId.substring(orderId.length - 2)}';
}

class _CustomerInvoiceStatusChip extends StatelessWidget {
  const _CustomerInvoiceStatusChip({
    required this.status,
    required this.isOverdue,
  });

  final String status;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = status.trim().toLowerCase();

    String label;
    Color bgColor;
    Color textColor;

    if (s.isEmpty) {
      label = 'Bilinmiyor';
      bgColor = theme.colorScheme.surfaceContainerHighest;
      textColor = theme.colorScheme.onSurfaceVariant;
    } else if (s == 'cancelled' || s == 'refunded') {
      label = 'İptal / İade';
      bgColor = Colors.red.withValues(alpha: 0.06);
      textColor = Colors.red.shade700;
    } else if (s == 'paid') {
      // Kapalı (ödenmiş) faturalar için tek bir helper mantığı.
      label = 'Kapalı';
      bgColor = theme.colorScheme.surfaceContainerHigh;
      textColor = theme.colorScheme.onSurfaceVariant;
    } else if (isOverdue) {
      label = '⏰ Geciken';
      bgColor = Colors.amber.withValues(alpha: 0.12);
      textColor = Colors.amber.shade900;
    } else if (_isCustomerInvoiceOpenLike(s)) {
      // issued / open -> Açık
      label = 'Açık';
      bgColor = theme.colorScheme.primary.withValues(alpha: 0.06);
      textColor = theme.colorScheme.primary;
    } else {
      // Diğer durumlar için genel "Kesildi" etiketi.
      label = 'Kesildi';
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

    final bgColor = theme.colorScheme.error.withValues(alpha: 0.10);
    final textColor = theme.colorScheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'İptal Edildi',
        style: theme.textTheme.bodySmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
