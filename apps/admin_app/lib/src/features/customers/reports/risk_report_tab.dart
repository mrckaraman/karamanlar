import 'package:core/core.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/formatters_tr.dart';
import 'admin_customer_reports_repository.dart';
import 'balance_report_providers.dart';
import 'report_filters.dart';
import 'risk_report_providers.dart';

import '../../stocks/stock_import_export_download_stub.dart'
  if (dart.library.html) '../../stocks/stock_import_export_download_web.dart'
  as download_helper;

class RiskReportTab extends ConsumerStatefulWidget {
  const RiskReportTab({super.key});

  @override
  ConsumerState<RiskReportTab> createState() => _RiskReportTabState();
}

class _RiskReportTabState extends ConsumerState<RiskReportTab> {
  bool _filtersExpanded = false;
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

    final agingAsync = ref.watch(riskAgingSnapshotProvider);
    final scoredAsync = ref.watch(riskScoredTopProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DashboardCards(
          agingAsync: agingAsync,
          scoredAsync: scoredAsync,
          onRetry: () {
            ref.invalidate(riskAgingSnapshotProvider);
            ref.invalidate(riskScoredTopProvider);
          },
        ),
        const SizedBox(height: AppSpacing.s12),
        _FilterPanel(
          expanded: _filtersExpanded,
          onToggle: () => setState(() => _filtersExpanded = !_filtersExpanded),
          filters: filters,
          searchController: _searchController,
          onRefresh: () {
            ref.invalidate(riskAgingSnapshotProvider);
            ref.invalidate(riskScoredTopProvider);
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: agingAsync.when(
                  loading: () => const _AgingPanelSkeleton(),
                  error: (e, _) => _InlineError(
                    message:
                        'Aging dağılımı yüklenemedi: ${AppException.messageOf(e)}',
                    onRetry: () => ref.invalidate(riskAgingSnapshotProvider),
                  ),
                  data: (snap) => _AgingPanel(snap: snap),
                ),
              ),
              const Divider(height: 1),
              scoredAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: _InlineError(
                    message:
                        'Risk skoru listesi yüklenemedi: ${AppException.messageOf(e)}',
                    onRetry: () => ref.invalidate(riskScoredTopProvider),
                  ),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: _EmptyState(
                        title: 'Risk skoru için kayıt yok',
                        subtitle: 'Henüz skorlanacak cari bulunamadı.',
                      ),
                    );
                  }

                  return Column(
                    children: [
                      _ScoredTableHeader(
                        rowCount: rows.length,
                        onExport: () async {
                          final bytes = _buildScoredXlsxBytes(rows);
                          if (bytes == null) return;
                          await download_helper.saveBytesFile(
                            'cari_risk_skoru.xlsx',
                            bytes,
                            mimeType:
                                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                          );
                        },
                        onRefresh: () => ref.invalidate(riskScoredTopProvider),
                      ),
                      const Divider(height: 1),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWideTable = constraints.maxWidth >= 1200;
                          if (isWideTable) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: _RiskScoreTable(rows: rows),
                            );
                          }

                          return Padding(
                            padding: const EdgeInsets.all(AppSpacing.s12),
                            child: Column(
                              children: [
                                for (final r in rows) ...[
                                  _RiskScoreTile(row: r),
                                  const SizedBox(height: AppSpacing.s12),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RiskScoreTile extends StatelessWidget {
  const _RiskScoreTile({required this.row});

  final RiskScoreRowDto row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final title = row.displayName.trim().isEmpty ? 'Cari' : row.displayName;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
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
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                _RiskLevelBadge(row: row),
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
                    label: 'Gecikmiş',
                    value: formatMoney(row.overdueAmount),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _LimitUsageCell(percent: row.limitUsagePercent),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                _TileMetric(
                  label: 'Risk Skoru',
                  value: row.riskScore.toStringAsFixed(1),
                  emphasis: true,
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

List<int>? _buildScoredXlsxBytes(List<RiskScoreRowDto> rows) {
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
    'Net',
    'Limit',
    'Limit%',
    'Gecikmiş',
    'Risk Skoru',
    'Risk Seviyesi',
    'Durum',
  ];

  sheet.appendRow(textRow(headers));

  for (final r in rows) {
    sheet.appendRow(
      textRow([
        r.customerCode,
        r.displayName.trim().isEmpty ? 'Cari' : r.displayName,
        r.netBalance.toStringAsFixed(2),
        r.limitAmount.toStringAsFixed(2),
        r.limitUsagePercent.toStringAsFixed(2),
        r.overdueAmount.toStringAsFixed(2),
        r.riskScore.toStringAsFixed(2),
        _riskLevelLabel(r.riskLevel),
        r.isActive ? 'Aktif' : 'Pasif',
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

String _riskLevelLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'high':
      return 'High';
    case 'medium':
      return 'Medium';
    case 'low':
    default:
      return 'Low';
  }
}

class _DashboardCards extends StatelessWidget {
  const _DashboardCards({
    required this.agingAsync,
    required this.scoredAsync,
    required this.onRetry,
  });

  final AsyncValue<AgingSnapshotDto> agingAsync;
  final AsyncValue<List<RiskScoreRowDto>> scoredAsync;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget card({
      required String title,
      required String value,
      required IconData icon,
      Color? badgeBg,
      Color? badgeFg,
    }) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: badgeBg ?? cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: badgeFg ?? cs.primary, size: 20),
            ),
          ],
        ),
      );
    }

    final agingState = agingAsync.valueOrNull;
    final scored = scoredAsync.valueOrNull ?? const <RiskScoreRowDto>[];

    final limitExceededCount = scored.where((r) {
      if (!r.isActive) return false;
      if (r.limitAmount <= 0) return false;
      return r.netBalance > r.limitAmount || r.limitUsagePercent >= 100;
    }).length;

    final riskyCount = scored.where((r) {
      if (!r.isActive) return false;
      return r.limitUsagePercent >= 80;
    }).length;

    final avgRiskScore = scored.isEmpty
        ? 0.0
        : (scored.map((e) => e.riskScore).reduce((a, b) => a + b) / scored.length);

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
        child: (agingAsync.isLoading && scoredAsync.isLoading)
            ? const _SnapshotSkeleton()
            : (agingAsync.hasError || scoredAsync.hasError)
                ? _InlineError(
                    message: 'Dashboard verileri yüklenemedi.',
                    onRetry: onRetry,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final columns = w < 600 ? 1 : (w < 1024 ? 2 : 4);
                      const spacing = 12.0;
                      final itemWidth = columns == 1
                          ? w
                          : (w - (spacing * (columns - 1))) / columns;

                      final cards = <Widget>[
                        card(
                          title: 'Limit Aşan',
                          value: limitExceededCount.toString(),
                          icon: Icons.error_outline_rounded,
                          badgeBg: cs.errorContainer,
                          badgeFg: cs.onErrorContainer,
                        ),
                        card(
                          title: 'Riskli (≥%80)',
                          value: riskyCount.toString(),
                          icon: Icons.warning_amber_rounded,
                          badgeBg: cs.tertiaryContainer,
                          badgeFg: cs.onTertiaryContainer,
                        ),
                        card(
                          title: 'Toplam Gecikmiş',
                          value: formatMoney(
                            agingState?.totalOverdueAmount ?? 0,
                          ),
                          icon: Icons.schedule_outlined,
                        ),
                        card(
                          title: 'Ortalama Risk Skoru',
                          value: avgRiskScore.toStringAsFixed(1),
                          icon: Icons.auto_graph_rounded,
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
                  ),
      ),
    );
  }
}

class _SnapshotSkeleton extends StatelessWidget {
  const _SnapshotSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget box() {
      return Container(
        height: 96,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final columns = w < 600 ? 1 : (w < 1024 ? 2 : 4);
            const spacing = 12.0;
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
                    child: box(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AgingPanelSkeleton extends StatelessWidget {
  const _AgingPanelSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
    );
  }
}

class _AgingPanel extends StatelessWidget {
  const _AgingPanel({required this.snap});

  final AgingSnapshotDto snap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final total = snap.totalOverdueAmount;
    final v0 = snap.amount0to7;
    final v1 = snap.amount8to14;
    final v2 = snap.amount15to30;
    final v3 = snap.amountOver30;

    double pct(double v) => total <= 0 ? 0 : (v / total).clamp(0, 1).toDouble();

    Widget legend(Color color, String label, double value) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$label  ${formatMoney(value)}',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      );
    }

    final c0 = cs.primaryContainer;
    final c1 = cs.secondaryContainer;
    final c2 = cs.tertiaryContainer;
    final c3 = cs.errorContainer;

    return Container(
      padding: const EdgeInsets.all(16),
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
                  'Aging Dağılımı',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                'Gecikmiş müşteri: ${snap.overdueCustomerCount}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: (pct(v0) * 1000).round().clamp(0, 1000),
                    child: Container(color: c0),
                  ),
                  Expanded(
                    flex: (pct(v1) * 1000).round().clamp(0, 1000),
                    child: Container(color: c1),
                  ),
                  Expanded(
                    flex: (pct(v2) * 1000).round().clamp(0, 1000),
                    child: Container(color: c2),
                  ),
                  Expanded(
                    flex: (pct(v3) * 1000).round().clamp(0, 1000),
                    child: Container(color: c3),
                  ),
                  if (total <= 0) Expanded(flex: 1000, child: Container(color: cs.surfaceContainerHighest)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              legend(c0, '0–7', v0),
              legend(c1, '8–14', v1),
              legend(c2, '15–30', v2),
              legend(c3, '30+', v3),
            ],
          ),
        ],
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
    required this.onRefresh,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final BalanceReportFilters filters;
  final TextEditingController searchController;
  final VoidCallback onRefresh;

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
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Yenile'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    ref.read(balanceReportFiltersProvider.notifier).clearAll();
                    ref.read(riskTopTableProvider.notifier).reset();
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
                          ref
                              .read(balanceReportFiltersProvider.notifier)
                              .setStatus(v);
                          ref.read(riskTopTableProvider.notifier).reset();
                        },
                      ),
                      _MinBalanceChips(
                        width: fieldWidth(420),
                        value: filters.minAbsNet,
                        onChanged: (v) {
                          ref
                              .read(balanceReportFiltersProvider.notifier)
                              .setMinAbsNet(v);
                          ref.read(riskTopTableProvider.notifier).reset();
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
                                .read(balanceReportFiltersProvider.notifier)
                                .setSearch(v);
                            ref.read(riskTopTableProvider.notifier).reset();
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

Future<double?> _askNumber(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final c = TextEditingController();
  final cs = Theme.of(context).colorScheme;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Uygula'),
          ),
        ],
      );
    },
  );

  if (ok != true) return null;

  final raw = c.text.trim().replaceAll(',', '.');
  return double.tryParse(raw);
}

class _ScoredTableHeader extends StatelessWidget {
  const _ScoredTableHeader({
    required this.rowCount,
    required this.onExport,
    required this.onRefresh,
  });

  final int rowCount;
  final VoidCallback onExport;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Risk Skoru — Top Müşteriler',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '$rowCount kayıt',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Yenile'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.table_view_rounded, size: 18),
            label: const Text('Excel (CSV)'),
          ),
        ],
      ),
    );
  }
}

class _RiskScoreTable extends StatelessWidget {
  const _RiskScoreTable({required this.rows});

  final List<RiskScoreRowDto> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    DataColumn col(String label, {bool numeric = false}) {
      return DataColumn(
        numeric: numeric,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
    }

    return Theme(
      data: theme.copyWith(
        dividerColor: cs.outlineVariant.withValues(alpha: 0.6),
      ),
      child: DataTable(
        headingRowHeight: 44,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 60,
        columns: [
          col('Ünvan'),
          col('Net Bakiye', numeric: true),
          col('Limit %', numeric: true),
          col('Gecikmiş Tutar', numeric: true),
          col('Risk Skoru', numeric: true),
          col('Risk Seviyesi'),
          const DataColumn(label: SizedBox(width: 220)),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(Text(
                  r.displayName.trim().isEmpty ? 'Cari' : r.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )),
                DataCell(_MoneyCell(amount: r.netBalance, bold: true)),
                DataCell(_LimitUsageCell(percent: r.limitUsagePercent)),
                DataCell(_MoneyCell(amount: r.overdueAmount)),
                DataCell(Text(r.riskScore.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(_RiskLevelBadge(row: r)),
                DataCell(_RowActions(customerId: r.customerId)),
              ],
            ),
        ],
      ),
    );
  }
}

class _MoneyCell extends StatelessWidget {
  const _MoneyCell({required this.amount, this.bold = false});

  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final isNegative = amount < 0;
    final cs = Theme.of(context).colorScheme;
    final color = isNegative ? cs.error : null;

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
      bar = cs.error;
    } else if (percent >= 80) {
      bar = cs.tertiary;
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

class _RiskLevelBadge extends StatelessWidget {
  const _RiskLevelBadge({required this.row});

  final RiskScoreRowDto row;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final String text;
    final Color bg;
    final Color fg;

    if (!row.isActive) {
      text = 'Pasif';
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurfaceVariant;
    } else {
      switch (row.riskLevel.trim().toLowerCase()) {
        case 'high':
          text = 'High';
          bg = cs.errorContainer;
          fg = cs.onErrorContainer;
          break;
        case 'medium':
          text = 'Medium';
          bg = cs.tertiaryContainer;
          fg = cs.onTertiaryContainer;
          break;
        case 'low':
        default:
          text = 'Low';
          bg = cs.primaryContainer;
          fg = cs.onPrimaryContainer;
          break;
      }
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
              label: 'Cari Kartı',
              icon: Icons.person_outline_rounded,
              onTap: () => context.go('/customers/${widget.customerId}/edit'),
            ),
            _MiniAction(
              label: 'Ekstre',
              icon: Icons.receipt_long_outlined,
              onTap: () => context.go('/customers/${widget.customerId}/statement'),
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
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

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
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.insights_rounded, color: cs.primary),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: cs.error),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}
