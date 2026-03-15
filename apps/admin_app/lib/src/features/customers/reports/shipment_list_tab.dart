import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/formatters_tr.dart';
import '../../orders/widgets/order_status_chip.dart';
import 'shipment_list_provider.dart';

final _shipmentSearchProvider = StateProvider.autoDispose<String>((ref) => '');
final _shipmentDateRangeProvider =
    StateProvider.autoDispose<DateTimeRange?>((ref) => null);
final _shipmentPageProvider = StateProvider.autoDispose<int>((ref) => 0);

class ShipmentListTab extends ConsumerStatefulWidget {
  const ShipmentListTab({super.key});

  @override
  ConsumerState<ShipmentListTab> createState() => _ShipmentListTabState();
}

class _ShipmentListTabState extends ConsumerState<ShipmentListTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  final Set<String> _optimisticHiddenIds = <String>{};
  final Set<String> _shippingIds = <String>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  DateTime? _dateFromInclusive(DateTimeRange? r) {
    if (r == null) return null;
    final start = r.start;
    return DateTime(start.year, start.month, start.day);
  }

  DateTime? _dateToInclusive(DateTimeRange? r) {
    if (r == null) return null;
    final end = r.end;
    return DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
  }

  Future<void> _pickDateRange() async {
    final current = ref.read(_shipmentDateRangeProvider);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: current,
      helpText: 'Tarih aralığı seç',
      cancelText: 'İptal',
      confirmText: 'Uygula',
    );

    if (!mounted) return;
    if (picked == null) return;

    ref.read(_shipmentDateRangeProvider.notifier).state = picked;
    ref.read(_shipmentPageProvider.notifier).state = 0;
  }

  void _resetFilters() {
    _searchController.clear();
    ref.read(_shipmentSearchProvider.notifier).state = '';
    ref.read(_shipmentDateRangeProvider.notifier).state = null;
    ref.read(_shipmentPageProvider.notifier).state = 0;

    setState(() {
      _optimisticHiddenIds.clear();
      _shippingIds.clear();
    });

    ref.invalidate(shipmentListProvider);
    ref.invalidate(shipmentCountProvider);
  }

  Future<void> _markShipped(AdminShipmentListRow row) async {
    if (_shippingIds.contains(row.id)) return;

    setState(() {
      _shippingIds.add(row.id);
      _optimisticHiddenIds.add(row.id);
    });

    final result = await AsyncValue.guard(
      () => adminOrderRepository.updateOrderStatus(
        orderId: row.id,
        status: 'shipped',
      ),
    );

    if (mounted) {
      if (result.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sevk işlemi başarısız: ${AppException.messageOf(result.error!)}',
            ),
          ),
        );

        setState(() {
          _optimisticHiddenIds.remove(row.id);
        });
      } else {
        ref.invalidate(shipmentListProvider);
        ref.invalidate(shipmentCountProvider);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sipariş sevk edildi olarak işaretlendi.')),
        );
      }

      setState(() {
        _shippingIds.remove(row.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final search = ref.watch(_shipmentSearchProvider);
    final dateRange = ref.watch(_shipmentDateRangeProvider);
    final page = ref.watch(_shipmentPageProvider);

    final dateFrom = _dateFromInclusive(dateRange);
    final dateTo = _dateToInclusive(dateRange);

    final countAsync = ref.watch(
      shipmentCountProvider((
        search: search,
        dateFrom: dateFrom,
        dateTo: dateTo,
      )),
    );

    final listAsync = ref.watch(
      shipmentListProvider((
        search: search,
        dateFrom: dateFrom,
        dateTo: dateTo,
        page: page,
      )),
    );

    final effectiveRows = (listAsync.valueOrNull ?? const <AdminShipmentListRow>[])
        .where((r) => !_optimisticHiddenIds.contains(r.id))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FiltersHeader(
          searchController: _searchController,
          dateRange: dateRange,
          totalCountAsync: countAsync,
          onSearchChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              ref.read(_shipmentSearchProvider.notifier).state = value;
              ref.read(_shipmentPageProvider.notifier).state = 0;
            });
          },
          onPickDateRange: _pickDateRange,
          onReset: _resetFilters,
        ),
        const SizedBox(height: AppSpacing.s12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FB),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: listAsync.when(
              loading: () => const _ShipmentListSkeleton(),
              error: (e, _) => _InlineError(
                message:
                    'Sevkiyat listesi yüklenemedi: ${AppException.messageOf(e)}',
                onRetry: () => ref.invalidate(shipmentListProvider),
              ),
              data: (_) {
                if (effectiveRows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: AppEmptyState(
                      title: 'Sevk bekleyen sipariş bulunamadı',
                      subtitle: 'Filtreleri değiştirerek tekrar deneyin.',
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in effectiveRows) ...[
                      _ShipmentCard(
                        row: row,
                        isShipping: _shippingIds.contains(row.id),
                        onMarkShipped: () => _markShipped(row),
                      ),
                      const SizedBox(height: AppSpacing.s12),
                    ],
                    _PaginationBar(
                      page: page,
                      pageSize: 20,
                      rowsOnPage: effectiveRows.length,
                      totalCountAsync: countAsync,
                      onPrev: page > 0
                          ? () => ref.read(_shipmentPageProvider.notifier).state =
                              page - 1
                          : null,
                      onNext: () {
                        ref.read(_shipmentPageProvider.notifier).state = page + 1;
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _FiltersHeader extends StatelessWidget {
  const _FiltersHeader({
    required this.searchController,
    required this.dateRange,
    required this.totalCountAsync,
    required this.onSearchChanged,
    required this.onPickDateRange,
    required this.onReset,
  });

  final TextEditingController searchController;
  final DateTimeRange? dateRange;
  final AsyncValue<int> totalCountAsync;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onPickDateRange;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final rangeText = dateRange == null
        ? 'Tarih: Tümü'
        : '${formatDate(dateRange!.start)} - ${formatDate(dateRange!.end)}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sevkiyat Listesi',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              totalCountAsync.when(
                loading: () => const _CountBadgeSkeleton(),
                error: (_, __) => const _CountBadge(count: null),
                data: (count) => _CountBadge(count: count),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;

              final searchField = TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Cari ara',
                  hintText: 'Müşteri adı…',
                ),
              );

              final dateButton = OutlinedButton.icon(
                onPressed: onPickDateRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(rangeText),
              );

              final resetButton = TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Filtreleri Sıfırla'),
              );

              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    searchField,
                    const SizedBox(height: AppSpacing.s12),
                    SizedBox(
                      width: double.infinity,
                      child: dateButton,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: resetButton,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: searchField),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(flex: 2, child: dateButton),
                  const SizedBox(width: AppSpacing.s12),
                  resetButton,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CountBadgeSkeleton extends StatelessWidget {
  const _CountBadgeSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 120,
      height: 28,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = count == null ? 'Toplam: -' : 'Toplam: $count';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(fontWeight: FontWeight.w700, color: cs.primary),
      ),
    );
  }
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({
    required this.row,
    required this.isShipping,
    required this.onMarkShipped,
  });

  final AdminShipmentListRow row;
  final bool isShipping;
  final VoidCallback onMarkShipped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final orderNoText = row.orderNo == null ? '-' : '#${row.orderNo}';
    final cityText = (row.city == null || row.city!.trim().isEmpty)
        ? '-'
        : row.city!.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;

                  final header = Text(
                    'Sipariş $orderNoText',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  );

                  final customerName = Text(
                    row.customerName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  );

                  final meta = Text(
                    '$cityText • ${formatDate(row.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  );

                  final total = Text(
                    formatMoney(row.totalAmount),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  );

                  final status = OrderStatusChip(status: row.status);

                  if (isMobile) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: header),
                            const SizedBox(width: AppSpacing.s8),
                            total,
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        customerName,
                        const SizedBox(height: AppSpacing.s4),
                        Wrap(
                          spacing: AppSpacing.s8,
                          runSpacing: AppSpacing.s4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            meta,
                            status,
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            header,
                            const SizedBox(height: AppSpacing.s4),
                            customerName,
                            const SizedBox(height: AppSpacing.s4),
                            meta,
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          total,
                          const SizedBox(height: AppSpacing.s8),
                          status,
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.s12),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: isShipping ? null : onMarkShipped,
                    icon: isShipping
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.local_shipping_outlined),
                    label: const Text('Sevk Edildi'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          Colors.green.shade600.withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.pageSize,
    required this.rowsOnPage,
    required this.totalCountAsync,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int pageSize;
  final int rowsOnPage;
  final AsyncValue<int> totalCountAsync;
  final VoidCallback? onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final total = totalCountAsync.valueOrNull;
    final hasNext = total == null
        ? rowsOnPage == pageSize
        : ((page + 1) * pageSize) < total;

    final start = total == null || total == 0 ? 0 : (page * pageSize) + 1;
    final end = total == null
        ? (page * pageSize) + rowsOnPage
        : ((page * pageSize) + rowsOnPage).clamp(0, total);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == null ? 'Gösterilen: $start-$end' : 'Gösterilen: $start-$end / $total',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          OutlinedButton(
            onPressed: onPrev,
            child: const Text('Önceki'),
          ),
          const SizedBox(width: AppSpacing.s8),
          OutlinedButton(
            onPressed: hasNext ? onNext : null,
            child: const Text('Sonraki'),
          ),
        ],
      ),
    );
  }
}

class _ShipmentListSkeleton extends StatelessWidget {
  const _ShipmentListSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget box({double? w, required double h}) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    Widget skeletonCard() {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(w: 140, h: 14),
                      const SizedBox(height: 10),
                      box(w: 220, h: 14),
                      const SizedBox(height: 10),
                      box(w: 180, h: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    box(w: 90, h: 14),
                    const SizedBox(height: 10),
                    box(w: 90, h: 22),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: box(w: 140, h: 40),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < 8; i++) ...[
          skeletonCard(),
          if (i != 7) const SizedBox(height: AppSpacing.s12),
        ],
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s8),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }
}
