import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _InvoiceCustomerFilter {
  all,
  withInvoice,
}

extension on _InvoiceCustomerFilter {
  String get label {
    switch (this) {
      case _InvoiceCustomerFilter.all:
        return 'Tümü';
      case _InvoiceCustomerFilter.withInvoice:
        return 'Son faturası olanlar';
    }
  }
}

final _invoiceCustomerSearchProvider = StateProvider.autoDispose<String>((ref) {
  return '';
});

final _invoiceCustomerFilterProvider =
    StateProvider.autoDispose<_InvoiceCustomerFilter>((ref) {
  return _InvoiceCustomerFilter.all;
});

final _invoiceCustomersFutureProvider =
    FutureProvider.autoDispose<List<AdminInvoiceCustomerPickEntry>>((ref) {
  final search = ref.watch(_invoiceCustomerSearchProvider);
  return adminInvoiceCustomerRepository.fetchCustomersWithLastInvoice(
    search: search.isEmpty ? null : search,
    limit: 100,
  );
});

class InvoiceCreatePage extends ConsumerWidget {
  const InvoiceCreatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(_invoiceCustomerSearchProvider);
    final filter = ref.watch(_invoiceCustomerFilterProvider);
    final customersAsync = ref.watch(_invoiceCustomersFutureProvider);

    return AppScaffold(
      title: 'Yeni Fatura',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _buildSearchCard(context, ref, search, filter),
            const SizedBox(height: 16),
            Expanded(
              child: customersAsync.when(
                loading: () => const AppLoadingState(),
                error: (error, stackTrace) => AppErrorState(
                  message: error.toString(),
                ),
                data: (data) {
                  final filtered = _applyFilter(data, filter);
                  if (filtered.isEmpty) {
                    if (search.isEmpty && filter == _InvoiceCustomerFilter.all) {
                      return const AppEmptyState(
                        title: 'Cari bulunamadı',
                        subtitle:
                            'Henüz cari tanımlı değil veya görüntüleme yetkiniz yok.',
                      );
                    }
                    return const AppEmptyState(
                      title: 'Sonuç bulunamadı',
                      subtitle:
                          'Arama kriterlerinize uygun cari veya fatura bulunamadı.',
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      return _InvoiceCustomerCard(entry: entry);
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

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fatura için cari seçin',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Fatura kesmek istediğiniz cariyi seçin. Her kartta son kesilen fatura bilgisi görünür.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchCard(
    BuildContext context,
    WidgetRef ref,
    String search,
    _InvoiceCustomerFilter filter,
  ) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: AppSearchField(
                hintText: 'Cari adı / telefon / kod / fatura no ara',
                initialValue: search,
                onChanged: (value) {
                  ref
                      .read(_invoiceCustomerSearchProvider.notifier)
                      .state = value;
                },
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<_InvoiceCustomerFilter>(
              value: filter,
              onChanged: (value) {
                if (value == null) return;
                ref
                    .read(_invoiceCustomerFilterProvider.notifier)
                    .state = value;
              },
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              items: _InvoiceCustomerFilter.values
                  .map(
                    (f) => DropdownMenuItem<_InvoiceCustomerFilter>(
                      value: f,
                      child: Text(f.label),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  List<AdminInvoiceCustomerPickEntry> _applyFilter(
    List<AdminInvoiceCustomerPickEntry> source,
    _InvoiceCustomerFilter filter,
  ) {
    if (filter == _InvoiceCustomerFilter.all) {
      return source;
    }

    return source
        .where((e) => (e.lastInvoiceNo ?? '').trim().isNotEmpty)
        .toList();
  }
}

class _InvoiceCustomerCard extends StatelessWidget {
  const _InvoiceCustomerCard({
    required this.entry,
  });

  final AdminInvoiceCustomerPickEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastInvoiceText = entry.lastInvoiceNo == null ||
            entry.lastInvoiceNo!.trim().isEmpty
        ? '—'
        : entry.lastInvoiceNo!;

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.go('/invoices/new?customerId=${entry.customerId}');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if ((entry.customerCode ?? '').isNotEmpty) ...[
                          Text(
                            entry.customerCode!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                        if ((entry.customerCode ?? '').isNotEmpty &&
                            (entry.phone ?? '').isNotEmpty)
                          const SizedBox(width: 8),
                        if ((entry.phone ?? '').isNotEmpty)
                          Text(
                            entry.phone!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Son Fatura',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary
                          .withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      lastInvoiceText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
