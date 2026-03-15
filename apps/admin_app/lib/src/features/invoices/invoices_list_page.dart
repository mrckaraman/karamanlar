import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';

enum AdminInvoiceStageTab { open, overdue, cancelledOrRefunded }

extension AdminInvoiceStageTabX on AdminInvoiceStageTab {
  String get label {
    switch (this) {
      case AdminInvoiceStageTab.open:
        return 'Açık';
      case AdminInvoiceStageTab.overdue:
        return 'Geciken';
      case AdminInvoiceStageTab.cancelledOrRefunded:
        return 'İptal/İade';
    }
  }

  /// Server-side sorgu için kullanılacak temel status listesi
  List<String> get baseStatuses {
    switch (this) {
      case AdminInvoiceStageTab.open:
        // ASSUMPTIONS: Açık fatura statüleri backend'de 'open' ve 'issued'
        // olarak tutuluyor. Hem açık hem de henüz tamamen kapanmamış
        // (issued) faturaları aynı sekmede listelemek için ikisini de
        // sorguluyoruz.
        return <String>['open', 'issued'];
      case AdminInvoiceStageTab.overdue:
        // Vadesi geçenler de open/issued statülerinden gelir,
        // asıl ayrım client-side tarih (şimdilik issuedAt) ile yapılır.
        return <String>['open', 'issued'];
      case AdminInvoiceStageTab.cancelledOrRefunded:
        return <String>['cancelled', 'refunded'];
    }
  }
}

enum AdminInvoiceDateFilter { all, today, thisWeek, thisMonth }

extension AdminInvoiceDateFilterX on AdminInvoiceDateFilter {
  String get label {
    switch (this) {
      case AdminInvoiceDateFilter.all:
        return 'Tümü';
      case AdminInvoiceDateFilter.today:
        return 'Bugün';
      case AdminInvoiceDateFilter.thisWeek:
        return 'Bu hafta';
      case AdminInvoiceDateFilter.thisMonth:
        return 'Bu ay';
    }
  }
}

final _adminInvoiceStageProvider =
    StateProvider<AdminInvoiceStageTab>((ref) => AdminInvoiceStageTab.open);

final _adminInvoiceSearchProvider = StateProvider<String>((ref) => '');

final _adminInvoiceDateFilterProvider =
    StateProvider<AdminInvoiceDateFilter>((ref) => AdminInvoiceDateFilter.all);

/// Dışarıdan manuel olarak tetiklenebilen, listeyi yeniden yüklemeye yarayan token.
/// Her arttığında, fatura listesi ve sayaç provider'ları yeniden çalışır.
final adminInvoicesReloadTokenProvider =
  StateProvider<int>((ref) => 0);

final _adminInvoicesForStageProvider = FutureProvider.autoDispose
    .family<List<AdminInvoiceListEntry>, AdminInvoiceStageTab>(
        (ref, stage) async {
  // Harici yenileme tetikleyicisine bağımlı ol.
  ref.watch(adminInvoicesReloadTokenProvider);
  final search = ref.watch(_adminInvoiceSearchProvider).trim();
  final dateFilter = ref.watch(_adminInvoiceDateFilterProvider);

  final statuses = stage.baseStatuses;
  final invoices = await adminInvoiceRepository.fetchInvoices(
    statuses: statuses,
    search: search.isEmpty ? null : search,
  );

  final today = _todayDate();
  final byStage = invoices
      // Defansif: paid statüleri hiçbir sekmede göstermeyelim.
      .where((invoice) =>
          invoice.status.toLowerCase() != 'paid')
      .where((invoice) => _matchesStage(invoice, stage, today))
      .toList();

  return _applyDateFilter(byStage, dateFilter, today);
});

final _adminInvoiceCountProvider = FutureProvider.autoDispose
    .family<int, AdminInvoiceStageTab>((ref, stage) async {
  // Harici yenileme tetikleyicisine bağımlı ol.
  ref.watch(adminInvoicesReloadTokenProvider);
  final search = ref.watch(_adminInvoiceSearchProvider).trim();
  final dateFilter = ref.watch(_adminInvoiceDateFilterProvider);

  final statuses = stage.baseStatuses;
  final invoices = await adminInvoiceRepository.fetchInvoices(
    statuses: statuses,
    search: search.isEmpty ? null : search,
  );

  final today = _todayDate();
  final byStage = invoices
    .where((invoice) =>
      invoice.status.toLowerCase() != 'paid')
    .where((invoice) => _matchesStage(invoice, stage, today))
    .toList();
  final filtered = _applyDateFilter(byStage, dateFilter, today);
  return filtered.length;
});

class InvoicesListPage extends ConsumerWidget {
  const InvoicesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentStage = ref.watch(_adminInvoiceStageProvider);
    final search = ref.watch(_adminInvoiceSearchProvider).trim();
    final dateFilter = ref.watch(_adminInvoiceDateFilterProvider);

    final invoicesAsync =
        ref.watch(_adminInvoicesForStageProvider(currentStage));

    return AppScaffold(
      title: 'Faturalar',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Üst başlık + toplam tutar
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Faturalar',
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
                      'Toplam: ${_formatAmount(total)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.8),
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Fatura iş akışı',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: AdminInvoiceStageTab.values.map((stage) {
                  final countAsync =
                      ref.watch(_adminInvoiceCountProvider(stage));
                  final count = countAsync.maybeWhen(
                    data: (value) => value,
                    orElse: () => null,
                  );
                  final selected = currentStage == stage;
                  final label = count == null
                      ? '${stage.label} (…)'
                      : '${stage.label} ($count)';

                  return Padding(
                    padding:
                        const EdgeInsets.only(right: AppSpacing.s8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) {
                        ref
                            .read(_adminInvoiceStageProvider.notifier)
                            .state = stage;
                      },
                    ),
                  );
                }).toList(),
              ),
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
                        hintText: 'Cari / fatura no ara',
                        padded: false,
                        onChanged: (value) => ref
                            .read(_adminInvoiceSearchProvider.notifier)
                            .state = value,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    DropdownButton<AdminInvoiceDateFilter>(
                      value: dateFilter,
                      onChanged: (value) {
                        if (value == null) return;
                        ref
                            .read(_adminInvoiceDateFilterProvider.notifier)
                            .state = value;
                      },
                      items: AdminInvoiceDateFilter.values
                          .map(
                            (f) => DropdownMenuItem<AdminInvoiceDateFilter>(
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
                  message: 'Fatura listesi yüklenemedi: $e',
                  onRetry: () {
                    ref.invalidate(
                        _adminInvoicesForStageProvider(currentStage));
                    for (final stage in AdminInvoiceStageTab.values) {
                      ref.invalidate(
                        _adminInvoiceCountProvider(stage),
                      );
                    }
                  },
                ),
                data: (invoices) {
                  if (invoices.isEmpty) {
                    final isDefaultOpen = currentStage ==
                            AdminInvoiceStageTab.open &&
                        search.isEmpty &&
                        dateFilter == AdminInvoiceDateFilter.all;

                    if (isDefaultOpen) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: AppSpacing.s12),
                            const AppEmptyState(
                              title: 'Henüz fatura yok.',
                              subtitle:
                                  'Fatura kesildiğinde burada listelenecek.',
                            ),
                          ],
                        ),
                      );
                    }

                    return const AppEmptyState(
                      title: 'Fatura bulunamadı.',
                      subtitle:
                          'Filtreleri değiştirerek tekrar deneyebilirsiniz.',
                    );
                  }

                  return ListView.separated(
                    itemCount: invoices.length,
                    padding:
                      const EdgeInsets.only(bottom: AppSpacing.s16),
                    separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.s12),
                    itemBuilder: (context, index) {
                      final invoice = invoices[index];
                        final subtitle = _buildSubtitle(invoice);
                      final isOverdue =
                        _isOverdue(invoice, _todayDate());

                      return Card(
                        elevation: 1.5,
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
                            padding: const EdgeInsets.all(AppSpacing.s12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        invoice.customerName,
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
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
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
                                      _formatAmount(
                                          invoice.totalAmount),
                                      style: theme
                                          .textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(
                                        height: AppSpacing.s4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildStatusChip(
                                          context,
                                          invoice.status,
                                          isOverdue: isOverdue,
                                        ),
                                      ],
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
    );
  }
}

DateTime _todayDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool _isOverdue(AdminInvoiceListEntry invoice, DateTime today) {
  final status = invoice.status.toLowerCase();
  if (status == 'paid' || status == 'cancelled' || status == 'refunded') {
    return false;
  }
  // Şimdilik basit mantık: fatura tarihi (invoice_date/issued_at/created_at)
  // bugünden küçükse ve ödenmemişse "vadesi geçen" kabul edilir.
  final invoiceDate = _dateOnly(invoice.issuedAt);
  return invoiceDate.isBefore(today);
}

/// Açık benzeri (open-like) statü yardımıcı fonksiyonu.
///
/// Backend tarafında canonical olarak 'open' ve 'issued' statüleri
/// "açık" kabul edilir ve hem Açık hem de Geciken sekmelerinde
/// kullanılacak filtreler bu helper üzerinden geçer.
bool _isOpenLike(String status) {
  final s = status.trim().toLowerCase();
  return s == 'open' || s == 'issued';
}

bool _matchesStage(
  AdminInvoiceListEntry invoice,
  AdminInvoiceStageTab stage,
  DateTime today,
) {
  final status = invoice.status.toLowerCase();

  switch (stage) {
    case AdminInvoiceStageTab.open:
      // Açık sekmesi: due_date >= today AND status in ('open','issued').
      // Şimdilik due_date yerine issuedAt tarihi kullanılıyor.
      if (_isOpenLike(status)) {
        return !_isOverdue(invoice, today);
      }
      return false;
    case AdminInvoiceStageTab.overdue:
      // Geciken sekmesi: due_date < today AND status in ('open','issued').
      // Şimdilik due_date yerine issuedAt tarihi kullanılıyor.
      if (_isOpenLike(status)) {
        return _isOverdue(invoice, today);
      }
      return false;
    case AdminInvoiceStageTab.cancelledOrRefunded:
      return status == 'cancelled' || status == 'refunded';
  }
}

List<AdminInvoiceListEntry> _applyDateFilter(
  List<AdminInvoiceListEntry> source,
  AdminInvoiceDateFilter filter,
  DateTime today,
) {
  if (filter == AdminInvoiceDateFilter.all) {
    return source;
  }

  DateTime toDate(DateTime value) => _dateOnly(value);

  switch (filter) {
    case AdminInvoiceDateFilter.today:
      return source
          .where((i) => toDate(i.issuedAt) == today)
          .toList();
    case AdminInvoiceDateFilter.thisWeek:
      final weekday = today.weekday; // 1 = Mon
      final start = today.subtract(Duration(days: weekday - 1));
      final end = start.add(const Duration(days: 7));
      return source
          .where((i) =>
            toDate(i.issuedAt).isAtSameMomentAs(start) ||
            (toDate(i.issuedAt).isAfter(start) &&
              toDate(i.issuedAt).isBefore(end)))
          .toList();
    case AdminInvoiceDateFilter.thisMonth:
      final start = DateTime(today.year, today.month, 1);
      final end = DateTime(today.year, today.month + 1, 1);
      return source
          .where((i) =>
            toDate(i.issuedAt).isAtSameMomentAs(start) ||
            (toDate(i.issuedAt).isAfter(start) &&
              toDate(i.issuedAt).isBefore(end)))
          .toList();
    case AdminInvoiceDateFilter.all:
      return source;
  }
}

String _buildSubtitle(AdminInvoiceListEntry invoice) {
  final issuedText = _formatDate(invoice.issuedAt);
  final invoiceNo = invoice.invoiceNo.isEmpty ? '-' : invoice.invoiceNo;
  // Fatura tarihi olarak invoice_date/issued_at/created_at önceliklendirilmiş
  // tarih değeri gösterilir.
  return 'Fatura: $invoiceNo • Tarih: $issuedText';
}

String _formatDate(DateTime date) {
  return formatDate(date);
}

String _formatAmount(double value) {
  return formatMoney(value);
}

String _statusLabel(String status) {
  final s = status.toLowerCase();
  switch (s) {
    case 'issued':
      return 'Kesildi';
    case 'sent':
      return 'Kesildi';
    case 'cancelled':
      return 'İptal / İade';
    case 'refunded':
      return 'İptal / İade';
    default:
      if (s.isEmpty) return 'Bilinmiyor';
      return status;
  }
}

Widget _buildStatusChip(
  BuildContext context,
  String status, {
  bool isOverdue = false,
}) {
  final theme = Theme.of(context);
  final s = status.trim().toLowerCase();
  String label = _statusLabel(status);

  Color bgColor;
  Color textColor;

  if (s.isEmpty) {
    bgColor = theme.colorScheme.surfaceContainerHighest;
    textColor = theme.colorScheme.onSurfaceVariant;
  } else if (s == 'cancelled' || s == 'refunded') {
    bgColor = Colors.red.withValues(alpha: 0.06);
    textColor = Colors.red.shade700;
  } else {
    if (isOverdue) {
      label = '⏰ Geciken';
      bgColor = Colors.amber.withValues(alpha: 0.12);
      textColor = Colors.amber.shade900;
    } else {
      bgColor = theme.colorScheme.primary.withValues(alpha: 0.06);
      textColor = theme.colorScheme.primary;
    }
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
