import 'dart:async';

import 'package:core/core.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/formatters_tr.dart';
import 'admin_customer_reports_repository.dart';
import 'balance_report_providers.dart';
import 'report_filters.dart';

import '../../stocks/stock_import_export_download_stub.dart'
  if (dart.library.html) '../../stocks/stock_import_export_download_web.dart'
  as download_helper;

class BalanceReportTab extends ConsumerStatefulWidget {
  const BalanceReportTab({super.key});

  @override
  ConsumerState<BalanceReportTab> createState() => _BalanceReportTabState();
}

class _BalanceReportTabState extends ConsumerState<BalanceReportTab> {
  bool _filtersExpanded = true;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final filters = ref.watch(balanceReportFiltersProvider);
    final table = ref.watch(balanceReportTableProvider);
    final selection = ref.watch(balanceSelectionProvider);

    final snapshotAsync = ref.watch(balanceSnapshotProvider);
    final pageAsync = ref.watch(balancePageProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        snapshotAsync.when(
          loading: () => const _SnapshotSkeleton(),
          error: (e, _) => _InlineError(
            message: 'Snapshot yüklenemedi: ${AppException.messageOf(e)}',
            onRetry: () => ref.invalidate(balanceSnapshotProvider),
          ),
          data: (snap) {
            if (kDebugMode) {
              debugPrint(
                'BalanceSnapshot: totalDebt=${snap.totalDebit}, totalCredit=${snap.totalCredit}, netTotal=${snap.netTotal}, rowCount=${snap.rowCount}',
              );
            }

            return _SnapshotPanel(
              totalDebit: snap.totalDebit,
              totalCredit: snap.totalCredit,
              netRisk: snap.netTotal,
              limitExceededCount: snap.limitExceededCount,
            );
          },
        ),
        const SizedBox(height: AppSpacing.s12),
        _FilterPanel(
          expanded: _filtersExpanded,
          onToggle: () => setState(() => _filtersExpanded = !_filtersExpanded),
          filters: filters,
          searchController: _searchController,
        ),
        const SizedBox(height: AppSpacing.s12),
        if (selection.isNotEmpty)
          _BulkActionBar(
            selectedCount: selection.length,
            onClear: () => ref.read(balanceSelectionProvider.notifier).clear(),
            onExportExcel: () async {
              final rows = pageAsync.valueOrNull ?? const <BalanceReportRowDto>[];
              final selected = selection;
              final selectedRows = rows
                  .where((r) => selected.contains(r.customerId))
                  .toList(growable: false);

              if (selectedRows.isEmpty) {
                _snack(context, 'Seçili satır bulunamadı.');
                return;
              }

              final bytes = _buildXlsxBytes(selectedRows);
              if (bytes == null) {
                _snack(context, 'Excel dosyası oluşturulamadı.');
                return;
              }

              final ok = await download_helper.saveBytesFile(
                'cari_bakiye_raporu.xlsx',
                bytes,
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              );
              if (!context.mounted) return;
              _snack(
                context,
                ok
                    ? 'Excel/Sheets açılıyor…'
                    : 'Dosya açılamadı. Excel/Sheets yüklü olmayabilir.',
              );
            },
            onBulkDeactivate: () async {
              final ok = await _confirm(
                context,
                title: 'Toplu Pasif Yap',
                message:
                    '${selection.length} cari pasif yapılacak. Bu işlem hard delete değildir.',
                confirmLabel: 'Pasif Yap',
              );
              if (!context.mounted) return;
              if (!ok) return;

              final rows = pageAsync.valueOrNull ?? const <BalanceReportRowDto>[];
              final selected = selection;
              final selectedRows = rows
                  .where((r) => selected.contains(r.customerId))
                  .toList(growable: false);

              if (selectedRows.isEmpty) {
                _snack(context, 'Seçili satır bulunamadı.');
                return;
              }

              final toDeactivate = selectedRows
                  .where((r) => r.isActive)
                  .toList(growable: false);

              if (toDeactivate.isEmpty) {
                _snack(context, 'Seçili carilerin hepsi zaten pasif.');
                return;
              }

              try {
                await adminCustomerReportsRepository.bulkDeactivateCustomers(
                  customerIds: toDeactivate
                      .map((e) => e.customerId)
                      .toList(growable: false),
                );

                for (final row in toDeactivate) {
                  unawaited(
                    auditService.logChange(
                      entity: 'customers',
                      entityId: row.customerId,
                      action: 'bulk_deactivate',
                      oldValue: <String, dynamic>{
                        'id': row.customerId,
                        'customer_code': row.customerCode,
                        'display_name': row.displayName,
                        'is_active': row.isActive,
                      },
                      newValue: <String, dynamic>{
                        'id': row.customerId,
                        'is_active': false,
                      },
                    ),
                  );
                }

                ref.invalidate(balanceSnapshotProvider);
                ref.invalidate(balancePageProvider);
                ref.read(balanceSelectionProvider.notifier).clear();

                if (!context.mounted) return;
                _snack(
                  context,
                  '${toDeactivate.length} cari pasif yapıldı.',
                );
              } catch (e) {
                if (!context.mounted) return;
                _snack(
                  context,
                  'Toplu pasif yapma başarısız: ${AppException.messageOf(e)}',
                );
              }
            },
            onBulkLimitUpdate: () async {
              final newLimit = await _askNumber(
                context,
                title: 'Toplu Limit Güncelle',
                hint: 'Yeni limit (TL)',
              );
              if (!context.mounted) return;
              if (newLimit == null) return;
              if (newLimit.isNaN || newLimit.isInfinite || newLimit < 0) {
                _snack(context, 'Geçersiz limit değeri.');
                return;
              }

              final ok = await _confirm(
                context,
                title: 'Toplu Limit Güncelle',
                message:
                    '${selection.length} cari için limit ${newLimit.toStringAsFixed(2)} TL olarak güncellenecek.',
                confirmLabel: 'Güncelle',
              );
              if (!context.mounted) return;
              if (!ok) return;

              final rows = pageAsync.valueOrNull ?? const <BalanceReportRowDto>[];
              final selected = selection;
              final selectedRows = rows
                  .where((r) => selected.contains(r.customerId))
                  .toList(growable: false);

              if (selectedRows.isEmpty) {
                _snack(context, 'Seçili satır bulunamadı.');
                return;
              }

              try {
                await adminCustomerReportsRepository.bulkUpdateLimitAmount(
                  customerIds: selectedRows
                      .map((e) => e.customerId)
                      .toList(growable: false),
                  limitAmount: newLimit,
                );

                final changed = selectedRows
                    .where((r) => r.limitAmount != newLimit)
                    .toList(growable: false);

                for (final row in changed) {
                  unawaited(
                    auditService.logChange(
                      entity: 'limits',
                      entityId: row.customerId,
                      action: 'bulk_update',
                      oldValue: <String, dynamic>{
                        'customer_id': row.customerId,
                        'customer_code': row.customerCode,
                        'display_name': row.displayName,
                        'limit_amount': row.limitAmount,
                      },
                      newValue: <String, dynamic>{
                        'customer_id': row.customerId,
                        'limit_amount': newLimit,
                      },
                    ),
                  );
                }

                ref.invalidate(balanceSnapshotProvider);
                ref.invalidate(balancePageProvider);
                ref.read(balanceSelectionProvider.notifier).clear();

                if (!context.mounted) return;
                _snack(
                  context,
                  '${selectedRows.length} cari için limit güncellendi.',
                );
              } catch (e) {
                if (!context.mounted) return;
                _snack(
                  context,
                  'Toplu limit güncelleme başarısız: ${AppException.messageOf(e)}',
                );
              }
            },
            onBulkPdf: () {
              _snack(context, 'Toplu PDF ekstre: sırada.');
            },
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
          child: pageAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: _InlineError(
                message: 'Rapor yüklenemedi: ${AppException.messageOf(e)}',
                onRetry: () => ref.invalidate(balancePageProvider),
              ),
            ),
            data: (rows) {
              final snap = snapshotAsync.valueOrNull;
              final totalCount = snap?.rowCount ?? 0;

              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: _EmptyState(),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWideTable = constraints.maxWidth >= 1200;

                  Widget rowsWidget;
                  if (isWideTable) {
                    rowsWidget = Padding(
                      padding: const EdgeInsets.all(12),
                      child: _PremiumTable(
                        rows: rows,
                        sortField: table.sortField,
                        sortDesc: table.sortDesc,
                        selectedIds: selection,
                        onToggleSelect: (id) => ref
                            .read(balanceSelectionProvider.notifier)
                            .toggle(id),
                        onToggleSelectAll: () {
                          final ids = rows.map((e) => e.customerId);
                          if (selection.length == rows.length) {
                            ref.read(balanceSelectionProvider.notifier).clear();
                          } else {
                            ref
                                .read(balanceSelectionProvider.notifier)
                                .setAll(ids);
                          }
                        },
                        onSort: (field) {
                          ref.read(balanceSelectionProvider.notifier).clear();
                          ref
                              .read(balanceReportTableProvider.notifier)
                              .setSort(field);
                        },
                      ),
                    );
                  } else {
                    rowsWidget = Padding(
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      child: Column(
                        children: [
                          _BalanceTileHeader(
                            allSelected: selection.length == rows.length,
                            selectedCount: selection.length,
                            rowCount: rows.length,
                            onToggleAll: () {
                              final ids = rows.map((e) => e.customerId);
                              if (selection.length == rows.length) {
                                ref
                                    .read(balanceSelectionProvider.notifier)
                                    .clear();
                              } else {
                                ref
                                    .read(balanceSelectionProvider.notifier)
                                    .setAll(ids);
                              }
                            },
                          ),
                          const SizedBox(height: AppSpacing.s12),
                          for (final r in rows) ...[
                            _BalanceRowTile(
                              row: r,
                              selected: selection.contains(r.customerId),
                              onToggleSelect: () => ref
                                  .read(balanceSelectionProvider.notifier)
                                  .toggle(r.customerId),
                            ),
                            const SizedBox(height: AppSpacing.s12),
                          ],
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      rowsWidget,
                      _PaginationBar(
                        pageIndex: table.pageIndex,
                        pageSize: table.pageSize,
                        totalCount: totalCount,
                        onPageSizeChanged: (size) {
                          ref.read(balanceSelectionProvider.notifier).clear();
                          ref
                              .read(balanceReportTableProvider.notifier)
                              .setPageSize(size);
                        },
                        onPrev: table.pageIndex > 0
                            ? () {
                                ref
                                    .read(balanceSelectionProvider.notifier)
                                    .clear();
                                ref
                                    .read(balanceReportTableProvider.notifier)
                                    .setPageIndex(table.pageIndex - 1);
                              }
                            : null,
                        onNext: (table.offset + rows.length) < totalCount
                            ? () {
                                ref
                                    .read(balanceSelectionProvider.notifier)
                                    .clear();
                                ref
                                    .read(balanceReportTableProvider.notifier)
                                    .setPageIndex(table.pageIndex + 1);
                              }
                            : null,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<int>? _buildXlsxBytes(List<BalanceReportRowDto> rows) {
    final excel = xls.Excel.createExcel();
    final sheet = excel.sheets[excel.getDefaultSheet()]!;

    List<xls.CellValue?> textRow(Iterable<dynamic> values) {
      return values
          .map<xls.CellValue?>(
            (v) => xls.TextCellValue((v ?? '').toString()),
          )
          .toList(growable: false);
    }

    const headers = [
      'Cari Kodu',
      'Ünvan',
      'Grup',
      'Net Bakiye',
      'Borç',
      'Alacak',
      'Risk Limiti',
      'Limit Kullanım %',
      'Son Sevkiyat',
      'Son Tahsilat',
      'Durum',
    ];

    sheet.appendRow(textRow(headers));

    for (final r in rows) {
      sheet.appendRow(
        textRow([
          r.customerCode,
          r.displayName.trim().isEmpty ? 'Cari' : r.displayName,
          (r.groupName ?? ''),
          r.netBalance.toStringAsFixed(2),
          r.totalDebit.toStringAsFixed(2),
          r.totalCredit.toStringAsFixed(2),
          r.limitAmount.toStringAsFixed(2),
          r.limitUsagePercent.toStringAsFixed(2),
          r.lastShipmentAt == null ? '' : formatDate(r.lastShipmentAt!),
          r.lastPaymentDate == null ? '' : formatDate(r.lastPaymentDate!),
          _statusLabelForRow(r),
        ]),
      );
    }

    for (var col = 0; col < headers.length; col++) {
      final cell = sheet.cell(
        xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      cell.cellStyle = xls.CellStyle(bold: true);
    }

    return excel.encode();
  }
}

class _SnapshotPanel extends StatelessWidget {
  const _SnapshotPanel({
    required this.totalDebit,
    required this.totalCredit,
    required this.netRisk,
    required this.limitExceededCount,
  });

  final double totalDebit;
  final double totalCredit;
  final double netRisk;
  final int limitExceededCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w < 600 ? 1 : (w < 1024 ? 2 : 4);
        const spacing = AppSpacing.s12;
        final itemWidth = columns == 1
            ? w
            : (w - (spacing * (columns - 1))) / columns;

        final cards = <Widget>[
          _SnapshotCard(
            title: 'Toplam Borç',
            value: totalDebit,
            icon: Icons.call_made_rounded,
          ),
          _SnapshotCard(
            title: 'Toplam Alacak',
            value: totalCredit,
            icon: Icons.call_received_rounded,
          ),
          _SnapshotCard(
            title: 'Net Risk',
            value: netRisk,
            icon: Icons.security_rounded,
            isNet: true,
          ),
          _SnapshotCard(
            title: 'Limit Aşan',
            valueText: '$limitExceededCount',
            subtitle: 'Müşteri Sayısı',
            icon: Icons.warning_amber_rounded,
            badgeColor: const Color(0xFFFFF3E0),
            badgeTextColor: const Color(0xFFB45309),
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final c in cards)
              SizedBox(
                width: itemWidth,
                child: c,
              ),
          ],
        );
      },
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({
    required this.title,
    required this.icon,
    this.value,
    this.valueText,
    this.subtitle,
    this.isNet = false,
    this.badgeColor,
    this.badgeTextColor,
  });

  final String title;
  final IconData icon;
  final double? value;
  final String? valueText;
  final String? subtitle;
  final bool isNet;
  final Color? badgeColor;
  final Color? badgeTextColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    const cardBg = Color(0xFFF7F9FB);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
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
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (value != null)
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: value!),
                      duration: const Duration(milliseconds: 700),
                      builder: (context, v, _) {
                        final text = formatMoney(v);
                        final isNegative = v < 0;
                        final valueColor = isNet && isNegative
                            ? const Color(0xFFDC2626)
                            : cs.onSurface;
                        return Text(
                          text,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: valueColor,
                          ),
                        );
                      },
                    )
                  else
                    Text(
                      valueText ?? '-',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: badgeColor ?? cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: badgeTextColor ?? cs.primary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPanel extends ConsumerWidget {
  const _FilterPanel({
    required this.expanded,
    required this.onToggle,
    required this.filters,
    required this.searchController,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final BalanceReportFilters filters;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final activeChips = <String>[];
    if (filters.minAbsNet > 0) activeChips.add('> ${filters.minAbsNet.toInt()} TL');
    if (filters.status == BalanceStatusFilter.debitOnly) activeChips.add('Sadece Borçlu');
    if (filters.status == BalanceStatusFilter.creditOnly) activeChips.add('Sadece Alacaklı');
    if ((filters.groupName ?? '').isNotEmpty) activeChips.add(filters.groupName!);
    if ((filters.subGroup ?? '').isNotEmpty) activeChips.add(filters.subGroup!);
    if ((filters.altGroup ?? '').isNotEmpty) activeChips.add(filters.altGroup!);
    if ((filters.marketerName ?? '').isNotEmpty) activeChips.add(filters.marketerName!);

    return Container(
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Akıllı Filtreler',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: onToggle,
                  icon: Icon(expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded),
                  label: Text(expanded ? 'Gizle' : 'Göster'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    ref.read(balanceSelectionProvider.notifier).clear();
                    ref.read(balanceReportFiltersProvider.notifier).clearAll();
                    ref.read(balanceReportTableProvider.notifier).resetPage();
                    searchController.text = '';
                  },
                  child: const Text('Sıfırla'),
                ),
              ],
            ),
            if (activeChips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in activeChips)
                    Chip(
                      label: Text(c),
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ],
            if (expanded) ...[
              const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final w = constraints.maxWidth;
                          const spacing = 12.0;
                          final half = (w - spacing) / 2;

                          double fieldWidth(double desktopWidth) {
                            if (w < 600) return w;
                            if (w < 1024) return half;
                            return desktopWidth > w ? w : desktopWidth;
                          }

                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: [
                              _FilterDropdown<BalanceStatusFilter>(
                                width: fieldWidth(220),
                                label: 'Durum',
                                value: filters.status,
                                items: const [
                                  DropdownMenuItem(
                                    value: BalanceStatusFilter.all,
                                    child: Text('Tümü'),
                                  ),
                                  DropdownMenuItem(
                                    value: BalanceStatusFilter.debitOnly,
                                    child: Text('Sadece Borçlu'),
                                  ),
                                  DropdownMenuItem(
                                    value: BalanceStatusFilter.creditOnly,
                                    child: Text('Sadece Alacaklı'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  ref.read(balanceSelectionProvider.notifier).clear();
                                  ref
                                      .read(balanceReportFiltersProvider.notifier)
                                      .setStatus(v);
                                  ref
                                      .read(balanceReportTableProvider.notifier)
                                      .resetPage();
                                },
                              ),
                              _MinBalanceChips(
                                width: fieldWidth(420),
                                value: filters.minAbsNet,
                                onChanged: (v) {
                                  ref.read(balanceSelectionProvider.notifier).clear();
                                  ref
                                      .read(balanceReportFiltersProvider.notifier)
                                      .setMinAbsNet(v);
                                  ref
                                      .read(balanceReportTableProvider.notifier)
                                      .resetPage();
                                },
                              ),
                              SizedBox(
                                width: fieldWidth(360),
                                child: TextField(
                                  controller: searchController,
                                  decoration: const InputDecoration(
                                    labelText: 'Arama (ünvan / kod / telefon)',
                                    prefixIcon: Icon(Icons.search),
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (v) {
                                    ref
                                        .read(balanceSelectionProvider.notifier)
                                        .clear();
                                    ref
                                        .read(balanceReportFiltersProvider.notifier)
                                        .setSearch(v);
                                    ref
                                        .read(balanceReportTableProvider.notifier)
                                        .resetPage();
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.width,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final double width;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        initialValue: value,
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _MinBalanceChips extends StatelessWidget {
  const _MinBalanceChips({
    required this.width,
    required this.value,
    required this.onChanged,
  });

  final double width;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      0.0,
      1000.0,
      5000.0,
      10000.0,
    ];

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Minimum bakiye',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(o == 0 ? '0' : o.toInt().toString()),
                  selected: value == o,
                  onSelected: (_) => onChanged(o),
                ),
              ChoiceChip(
                label: const Text('Serbest'),
                selected: !options.contains(value),
                onSelected: (_) async {
                  final v = await _askNumber(context,
                      title: 'Minimum bakiye', hint: 'Örn: 25000');
                  if (v == null) return;
                  onChanged(v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PremiumTable extends StatelessWidget {
  const _PremiumTable({
    required this.rows,
    required this.sortField,
    required this.sortDesc,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onToggleSelectAll,
    required this.onSort,
  });

  final List<BalanceReportRowDto> rows;
  final BalanceSortField sortField;
  final bool sortDesc;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggleSelect;
  final VoidCallback onToggleSelectAll;
  final ValueChanged<BalanceSortField> onSort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    DataColumn col(String label, BalanceSortField field, {bool numeric = false}) {
      return DataColumn(
        numeric: numeric,
        onSort: (_, __) => onSort(field),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (sortField == field)
              Icon(
                sortDesc
                    ? Icons.arrow_drop_down_rounded
                    : Icons.arrow_drop_up_rounded,
                size: 18,
                color: cs.primary,
              ),
          ],
        ),
      );
    }

    return Theme(
      data: theme.copyWith(
        dividerColor: cs.outlineVariant.withValues(alpha: 0.6),
      ),
      child: DataTable(
        showCheckboxColumn: true,
        headingRowHeight: 44,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 60,
        columns: [
          DataColumn(
            label: Checkbox(
              value: selectedIds.length == rows.length,
              onChanged: (_) => onToggleSelectAll(),
            ),
          ),
          col('Cari Kodu', BalanceSortField.customerCode),
          col('Ünvan', BalanceSortField.title),
          col('Grup', BalanceSortField.groupName),
          col('Net Bakiye', BalanceSortField.netBalance, numeric: true),
          const DataColumn(
            label: Text('Borç', style: TextStyle(fontWeight: FontWeight.w700)),
            numeric: true,
          ),
          const DataColumn(
            label: Text('Alacak', style: TextStyle(fontWeight: FontWeight.w700)),
            numeric: true,
          ),
          const DataColumn(
            label: Text('Risk Limiti', style: TextStyle(fontWeight: FontWeight.w700)),
            numeric: true,
          ),
          col('Limit %', BalanceSortField.limitUsagePercent, numeric: true),
          col('Son Sevkiyat', BalanceSortField.lastShipmentAt),
          col('Son Tahsilat', BalanceSortField.lastPaymentDate),
          const DataColumn(label: Text('Durum', style: TextStyle(fontWeight: FontWeight.w700))),
          const DataColumn(label: SizedBox(width: 220)),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              selected: selectedIds.contains(r.customerId),
              onSelectChanged: (_) => onToggleSelect(r.customerId),
              cells: [
                DataCell(Checkbox(
                  value: selectedIds.contains(r.customerId),
                  onChanged: (_) => onToggleSelect(r.customerId),
                )),
                DataCell(Text(r.customerCode)),
                DataCell(Text(
                  r.displayName.trim().isEmpty ? 'Cari' : r.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )),
                DataCell(Text(r.groupName ?? '-')),
                DataCell(_MoneyCell(amount: r.netBalance, bold: true)),
                DataCell(_MoneyCell(amount: r.totalDebit)),
                DataCell(_MoneyCell(amount: r.totalCredit)),
                DataCell(_MoneyCell(amount: r.limitAmount)),
                DataCell(_LimitUsageCell(percent: r.limitUsagePercent)),
                DataCell(Text(r.lastShipmentAt == null ? '-' : formatDate(r.lastShipmentAt!))),
                DataCell(Text(r.lastPaymentDate == null ? '-' : formatDate(r.lastPaymentDate!))),
                DataCell(_StatusBadge(row: r)),
                DataCell(_RowActions(customerId: r.customerId)),
              ],
            ),
        ],
      ),
    );
  }
}

class _BalanceTileHeader extends StatelessWidget {
  const _BalanceTileHeader({
    required this.allSelected,
    required this.selectedCount,
    required this.rowCount,
    required this.onToggleAll,
  });

  final bool allSelected;
  final int selectedCount;
  final int rowCount;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: (_) => onToggleAll(),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              selectedCount > 0
                  ? '$selectedCount / $rowCount seçili'
                  : '$rowCount kayıt',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            'Detaylar',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BalanceRowTile extends StatelessWidget {
  const _BalanceRowTile({
    required this.row,
    required this.selected,
    required this.onToggleSelect,
  });

  final BalanceReportRowDto row;
  final bool selected;
  final VoidCallback onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final title = row.displayName.trim().isEmpty ? 'Cari' : row.displayName;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onToggleSelect,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelect(),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${row.customerCode} • $title',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s8),
                            _StatusBadge(row: row),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          'Grup: ${row.groupName ?? '-'}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              Row(
                children: [
                  Expanded(
                    child: _TileMetric(
                      label: 'Net',
                      value: formatMoney(row.netBalance),
                      emphasis: true,
                      valueColor: row.netBalance < 0 ? cs.error : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: _TileMetric(
                      label: 'Borç',
                      value: formatMoney(row.totalDebit),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: _TileMetric(
                      label: 'Alacak',
                      value: formatMoney(row.totalCredit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              Row(
                children: [
                  Expanded(
                    child: _TileMetric(
                      label: 'Risk Limiti',
                      value: formatMoney(row.limitAmount),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _LimitUsageCell(percent: row.limitUsagePercent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              Row(
                children: [
                  Expanded(
                    child: _TileMetric(
                      label: 'Son Sevkiyat',
                      value: row.lastShipmentAt == null
                          ? '-'
                          : formatDate(row.lastShipmentAt!),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: _TileMetric(
                      label: 'Son Tahsilat',
                      value: row.lastPaymentDate == null
                          ? '-'
                          : formatDate(row.lastPaymentDate!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              Align(
                alignment: Alignment.centerRight,
                child: _RowActions(customerId: row.customerId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TileMetric extends StatelessWidget {
  const _TileMetric({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          value,
          style: (emphasis
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyMedium)
              ?.copyWith(
            fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

enum _RowStatusKind {
  passive,
  limitExceeded,
  risky,
  normal,
}

_RowStatusKind _statusKindForRow(BalanceReportRowDto row) {
  if (!row.isActive) return _RowStatusKind.passive;
  if (row.isLimitExceeded) return _RowStatusKind.limitExceeded;
  if (row.limitUsagePercent >= 80) return _RowStatusKind.risky;
  return _RowStatusKind.normal;
}

String _statusLabelForRow(BalanceReportRowDto row) {
  switch (_statusKindForRow(row)) {
    case _RowStatusKind.passive:
      return 'Pasif';
    case _RowStatusKind.limitExceeded:
      return 'Limit Aşıldı';
    case _RowStatusKind.risky:
      return 'Riskli';
    case _RowStatusKind.normal:
      return 'Normal';
  }
}

class _MoneyCell extends StatelessWidget {
  const _MoneyCell({required this.amount, this.bold = false});

  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final isNegative = amount < 0;
    final color = isNegative ? const Color(0xFFDC2626) : null;

    return Text(
      formatMoney(amount),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        color: color,
      ),
    );
  }
}

class _LimitUsageCell extends StatelessWidget {
  const _LimitUsageCell({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color bar;
    if (percent >= 100) {
      bar = const Color(0xFFDC2626);
    } else if (percent >= 80) {
      bar = const Color(0xFFD97706);
    } else {
      bar = cs.primary;
    }

    final v = (percent / 100).clamp(0, 1).toDouble();

    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${percent.toStringAsFixed(0)}%',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(bar),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.row});

  final BalanceReportRowDto row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final kind = _statusKindForRow(row);

    final String text;
    final Color bg;
    final Color fg;

    switch (kind) {
      case _RowStatusKind.passive:
        text = 'Pasif';
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
        break;
      case _RowStatusKind.limitExceeded:
        text = 'Limit Aşıldı';
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        break;
      case _RowStatusKind.risky:
        text = 'Riskli';
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        break;
      case _RowStatusKind.normal:
        text = 'Normal';
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: (textTheme.labelMedium ?? const TextStyle())
            .copyWith(fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _RowActions extends StatefulWidget {
  const _RowActions({required this.customerId});

  final String customerId;

  @override
  State<_RowActions> createState() => _RowActionsState();
}

class _RowActionsState extends State<_RowActions> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedOpacity(
        opacity: _hover ? 1 : 0,
        duration: const Duration(milliseconds: 140),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _MiniAction(
              label: 'Ekstre Gör',
              icon: Icons.receipt_long_outlined,
              onTap: () => context.go('/customers/${widget.customerId}/statement'),
            ),
            _MiniAction(
              label: 'Tahsilat Gir',
              icon: Icons.payments_outlined,
              onTap: () =>
                  context.go('/customers/${widget.customerId}/payments/new'),
            ),
            _MiniAction(
              label: 'Limit',
              icon: Icons.credit_score_outlined,
              onTap: () => _snack(context, 'Limit güncelleme: sırada.'),
            ),
            _MiniAction(
              label: 'PDF',
              icon: Icons.picture_as_pdf_outlined,
              onTap: () => _snack(context, 'PDF export: sırada.'),
            ),
            _MiniAction(
              label: 'Pasif',
              icon: Icons.block,
              color: cs.error,
              onTap: () => _snack(context, 'Pasif yap: sırada.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color ?? cs.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color ?? cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.selectedCount,
    required this.onClear,
    required this.onBulkPdf,
    required this.onBulkLimitUpdate,
    required this.onBulkDeactivate,
    required this.onExportExcel,
  });

  final int selectedCount;
  final VoidCallback onClear;
  final VoidCallback onBulkPdf;
  final VoidCallback onBulkLimitUpdate;
  final VoidCallback onBulkDeactivate;
  final VoidCallback onExportExcel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;

          final actions = <Widget>[
            TextButton.icon(
              onPressed: onBulkPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Toplu PDF Ekstre'),
            ),
            TextButton.icon(
              onPressed: onBulkLimitUpdate,
              icon: const Icon(Icons.credit_score_outlined),
              label: const Text('Toplu Limit Güncelle'),
            ),
            TextButton.icon(
              onPressed: onBulkDeactivate,
              icon: const Icon(Icons.block),
              label: const Text('Toplu Pasif Yap'),
            ),
            TextButton.icon(
              onPressed: onExportExcel,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Excel Dışa Aktar'),
            ),
          ];

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$selectedCount seçildi',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Seçimi temizle',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            );
          }

          return Row(
            children: [
              Text(
                '$selectedCount seçildi',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              ...actions.expand((w) sync* {
                yield w;
                yield const SizedBox(width: 8);
              }),
              IconButton(
                tooltip: 'Seçimi temizle',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pageIndex,
    required this.pageSize,
    required this.totalCount,
    required this.onPageSizeChanged,
    required this.onPrev,
    required this.onNext,
  });

  final int pageIndex;
  final int pageSize;
  final int totalCount;
  final ValueChanged<int> onPageSizeChanged;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final start = totalCount == 0 ? 0 : (pageIndex * pageSize) + 1;
    final end = ((pageIndex + 1) * pageSize).clamp(0, totalCount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$start-$end / $totalCount',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<int>(
              initialValue: pageSize,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Sayfa',
              ),
              items: const [
                DropdownMenuItem(value: 25, child: Text('25')),
                DropdownMenuItem(value: 50, child: Text('50')),
                DropdownMenuItem(value: 100, child: Text('100')),
              ],
              onChanged: (v) {
                if (v == null) return;
                onPageSizeChanged(v);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Önceki',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            tooltip: 'Sonraki',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                Icons.bar_chart_rounded,
                size: 42,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Rapor boş',
              style:
                  theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Filtreleri belirleyip Rapor Getir’e basarak cari bakiyeleri görüntüleyebilirsiniz.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppErrorState(
      message: message,
      onRetry: onRetry,
    );
  }
}

class _SnapshotSkeleton extends StatelessWidget {
  const _SnapshotSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w < 600 ? 1 : (w < 1024 ? 2 : 4);
        const spacing = AppSpacing.s12;
        final itemWidth = columns == 1
            ? w
            : (w - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < 4; i++)
              SizedBox(
                width: itemWidth,
                child: const _SkeletonBox(),
              ),
          ],
        );
      },
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

Future<double?> _askNumber(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<double>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = controller.text.trim().replaceAll('.', '').replaceAll(',', '.');
              final v = double.tryParse(raw);
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Uygula'),
          ),
        ],
      );
    },
  );

  controller.dispose();
  return result;
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
