import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import '../../utils/csv_export/csv_exporter.dart';

enum BalanceReportRange { days30, days90, all }

enum BalanceReportStatus { all, debitOnly, creditOnly }

class BalanceReportFilters {
  const BalanceReportFilters({
    this.range = BalanceReportRange.days30,
    this.status = BalanceReportStatus.all,
    this.minAbsNet = 0,
    this.search = '',
    this.sortField = 'net',
    this.sortDesc = true,
    this.groupName,
    this.subGroupName,
    this.subSubGroupName,
    this.marketerName,
  });

  final BalanceReportRange range;
  final BalanceReportStatus status;
  final double minAbsNet;
  final String search;
  final String sortField;
  final bool sortDesc;
  final String? groupName;
  final String? subGroupName;
  final String? subSubGroupName;
  final String? marketerName;

  @override
  int get hashCode => Object.hash(
        range,
        status,
        minAbsNet,
        search,
        sortField,
        sortDesc,
        groupName,
        subGroupName,
        subSubGroupName,
        marketerName,
      );

  @override
  bool operator ==(Object other) {
    return other is BalanceReportFilters &&
        other.range == range &&
        other.status == status &&
        other.minAbsNet == minAbsNet &&
        other.search == search &&
        other.sortField == sortField &&
        other.sortDesc == sortDesc &&
        other.groupName == groupName &&
        other.subGroupName == subGroupName &&
        other.subSubGroupName == subSubGroupName &&
        other.marketerName == marketerName;
  }

  BalanceReportFilters copyWith({
    BalanceReportRange? range,
    BalanceReportStatus? status,
    double? minAbsNet,
    String? search,
    String? sortField,
    bool? sortDesc,
    String? groupName,
    String? subGroupName,
    String? subSubGroupName,
    String? marketerName,
  }) {
    return BalanceReportFilters(
      range: range ?? this.range,
      status: status ?? this.status,
      minAbsNet: minAbsNet ?? this.minAbsNet,
      search: search ?? this.search,
      sortField: sortField ?? this.sortField,
      sortDesc: sortDesc ?? this.sortDesc,
      groupName: groupName ?? this.groupName,
      subGroupName: subGroupName ?? this.subGroupName,
      subSubGroupName: subSubGroupName ?? this.subSubGroupName,
      marketerName: marketerName ?? this.marketerName,
    );
  }
}

class BalanceReportFiltersNotifier
    extends StateNotifier<BalanceReportFilters> {
  BalanceReportFiltersNotifier() : super(const BalanceReportFilters());

  void setRange(BalanceReportRange range) {
    state = state.copyWith(range: range);
  }

  void setStatus(BalanceReportStatus status) {
    state = state.copyWith(status: status);
  }

  void setMinAbsNet(double value) {
    state = state.copyWith(minAbsNet: value);
  }

  void setSearch(String value) {
    state = state.copyWith(search: value);
  }

  void setSort(String field, bool desc) {
    state = state.copyWith(sortField: field, sortDesc: desc);
  }

  void setGroup(String? value) {
    // Grup değişince ara grup ve alt grup sıfırlanır
    state = state.copyWith(
      groupName: value,
      subGroupName: null,
      subSubGroupName: null,
    );
  }

  void setSubGroup(String? value) {
    // Ara grup değişince alt grup sıfırlanır
    state = state.copyWith(
      subGroupName: value,
      subSubGroupName: null,
    );
  }

  void setSubSubGroup(String? value) {
    state = state.copyWith(subSubGroupName: value);
  }

  void setMarketer(String? value) {
    state = state.copyWith(marketerName: value);
  }
}

final balanceReportFiltersProvider =
    StateNotifierProvider<BalanceReportFiltersNotifier, BalanceReportFilters>(
  (ref) => BalanceReportFiltersNotifier(),
);

final _balanceReportRequestTokenProvider =
    StateProvider<int>((ref) => 0);

final _balanceReportRequestedFiltersProvider =
    StateProvider<BalanceReportFilters?>((ref) => null);

class BalanceReportRow {
  const BalanceReportRow({
    required this.customerId,
    required this.name,
    required this.code,
    required this.phone,
    required this.totalDebit,
    required this.totalCredit,
    required this.lastTxDate,
    this.groupName,
    this.subGroupName,
    this.subSubGroupName,
    this.marketerName,
  });

  final String customerId;
  final String name;
  final String code;
  final String phone;
  final double totalDebit;
  final double totalCredit;
  final DateTime? lastTxDate;
  final String? groupName;
  final String? subGroupName;
  final String? subSubGroupName;
  final String? marketerName;

  double get net => totalDebit - totalCredit;
}

class BalanceReportSnapshot {
  const BalanceReportSnapshot({
    required this.token,
    required this.generatedAt,
    required this.filters,
    required this.rows,
    required this.totalDebit,
    required this.totalCredit,
  });

  final int token;
  final DateTime generatedAt;
  final BalanceReportFilters filters;
  final List<BalanceReportRow> rows;
  final double totalDebit;
  final double totalCredit;

  double get netTotal => totalDebit - totalCredit;

  BalanceReportSnapshot copyWith({
    int? token,
    DateTime? generatedAt,
    BalanceReportFilters? filters,
    List<BalanceReportRow>? rows,
    double? totalDebit,
    double? totalCredit,
  }) {
    return BalanceReportSnapshot(
      token: token ?? this.token,
      generatedAt: generatedAt ?? this.generatedAt,
      filters: filters ?? this.filters,
      rows: rows ?? this.rows,
      totalDebit: totalDebit ?? this.totalDebit,
      totalCredit: totalCredit ?? this.totalCredit,
    );
  }
}

final balanceReportSnapshotProvider =
    StateProvider<BalanceReportSnapshot?>((ref) => null);

// Distinct filtre listeleri için provider'lar
final balanceReportGroupsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  const repo = AdminReportsRepository(useMockData: true);
  return repo.fetchDistinctGroups();
});

final balanceReportSubGroupsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  const repo = AdminReportsRepository(useMockData: true);
  final filters = ref.watch(balanceReportFiltersProvider);
  return repo.fetchDistinctSubGroups(group: filters.groupName);
});

final balanceReportSubSubGroupsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  const repo = AdminReportsRepository(useMockData: true);
  final filters = ref.watch(balanceReportFiltersProvider);
  return repo.fetchDistinctSubSubGroups(
    group: filters.groupName,
    subGroup: filters.subGroupName,
  );
});

final balanceReportMarketersProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  const repo = AdminReportsRepository(useMockData: true);
  return repo.fetchDistinctMarketers();
});

class AdminReportsRepository {
  const AdminReportsRepository({this.useMockData = true});

  final bool useMockData;

  Future<List<BalanceReportRow>> fetchBalanceReport({
    required BalanceReportRange range,
    required BalanceReportStatus status,
    required double minAbsNet,
    required String search,
    required String sortField,
    required bool sortDesc,
    String? groupName,
    String? subGroupName,
    String? subSubGroupName,
    String? marketerName,
  }) async {
    if (!useMockData) {
      // Burada Supabase SQL/view entegrasyonu yapılabilir.
      return <BalanceReportRow>[];
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));

    final now = DateTime.now();

    final mock = _buildMockRows(now);

    Iterable<BalanceReportRow> rows = mock;

    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      rows = rows.where((r) {
        return r.name.toLowerCase().contains(q) ||
            r.code.toLowerCase().contains(q) ||
            r.phone.toLowerCase().contains(q);
      });
    }

    // Grup / Ara Grup / Alt Grup / Pazarlamacı filtreleri
    if (groupName != null && groupName.isNotEmpty) {
      rows = rows.where((r) => r.groupName == groupName);
    }

    if (subGroupName != null && subGroupName.isNotEmpty) {
      rows = rows.where((r) => r.subGroupName == subGroupName);
    }

    if (subSubGroupName != null && subSubGroupName.isNotEmpty) {
      rows = rows.where((r) => r.subSubGroupName == subSubGroupName);
    }

    if (marketerName != null && marketerName.isNotEmpty) {
      rows = rows.where((r) => r.marketerName == marketerName);
    }

    rows = rows.where((r) => r.net.abs() >= minAbsNet);

    rows = rows.where((r) {
      switch (status) {
        case BalanceReportStatus.debitOnly:
          return r.net > 0;
        case BalanceReportStatus.creditOnly:
          return r.net < 0;
        case BalanceReportStatus.all:
          return true;
      }
    });

    final list = rows.toList();

    list.sort((a, b) {
      int result;
      switch (sortField) {
        case 'name':
          result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case 'code':
          result = a.code.toLowerCase().compareTo(b.code.toLowerCase());
          break;
        case 'lastTxDate':
          final ad = a.lastTxDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.lastTxDate ?? DateTime.fromMillisecondsSinceEpoch(0);
          result = ad.compareTo(bd);
          break;
        case 'net':
        default:
          result = a.net.compareTo(b.net);
          break;
      }

      return sortDesc ? -result : result;
    });

    return list;
  }

  Future<List<String>> fetchDistinctGroups() async {
    if (!useMockData) {
      return <String>[];
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final rows = _buildMockRows(DateTime.now());

    final set = <String>{};
    for (final r in rows) {
      final g = r.groupName;
      if (g != null && g.trim().isNotEmpty) {
        set.add(g.trim());
      }
    }

    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<List<String>> fetchDistinctSubGroups({String? group}) async {
    if (!useMockData) {
      return <String>[];
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final rows = _buildMockRows(DateTime.now());

    final set = <String>{};
    for (final r in rows) {
      if (group != null && group.isNotEmpty && r.groupName != group) {
        continue;
      }
      final g = r.subGroupName;
      if (g != null && g.trim().isNotEmpty) {
        set.add(g.trim());
      }
    }

    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<List<String>> fetchDistinctSubSubGroups({
    String? group,
    String? subGroup,
  }) async {
    if (!useMockData) {
      return <String>[];
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final rows = _buildMockRows(DateTime.now());

    final set = <String>{};
    for (final r in rows) {
      if (group != null && group.isNotEmpty && r.groupName != group) {
        continue;
      }
      if (subGroup != null && subGroup.isNotEmpty &&
          r.subGroupName != subGroup) {
        continue;
      }
      final g = r.subSubGroupName;
      if (g != null && g.trim().isNotEmpty) {
        set.add(g.trim());
      }
    }

    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<List<String>> fetchDistinctMarketers() async {
    if (!useMockData) {
      return <String>[];
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
    final rows = _buildMockRows(DateTime.now());

    final set = <String>{};
    for (final r in rows) {
      final g = r.marketerName;
      if (g != null && g.trim().isNotEmpty) {
        set.add(g.trim());
      }
    }

    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }
}

List<BalanceReportRow> _buildMockRows(DateTime now) {
  return <BalanceReportRow>[
    BalanceReportRow(
      customerId: '1',
      name: 'Karamanlar Gıda Ltd. Şti.',
      code: 'CR0001',
      phone: '+90 532 000 00 01',
      totalDebit: 25000,
      totalCredit: 5000,
      lastTxDate: now.subtract(const Duration(days: 2)),
      groupName: 'Perakende',
      subGroupName: 'Market',
      subSubGroupName: 'A Tipi',
      marketerName: 'Ahmet Yılmaz',
    ),
    BalanceReportRow(
      customerId: '2',
      name: 'Örnek Market A.Ş.',
      code: 'CR0002',
      phone: '+90 532 000 00 02',
      totalDebit: 12000,
      totalCredit: 8000,
      lastTxDate: now.subtract(const Duration(days: 5)),
      groupName: 'Perakende',
      subGroupName: 'Market',
      subSubGroupName: 'B Tipi',
      marketerName: 'Ahmet Yılmaz',
    ),
    BalanceReportRow(
      customerId: '3',
      name: 'Deneme İnşaat',
      code: 'CR0003',
      phone: '+90 532 000 00 03',
      totalDebit: 0,
      totalCredit: 7000,
      lastTxDate: now.subtract(const Duration(days: 10)),
      groupName: 'Toptan',
      subGroupName: 'İnşaat',
      subSubGroupName: 'Proje',
      marketerName: 'Mehmet Demir',
    ),
    BalanceReportRow(
      customerId: '4',
      name: 'Test Büfe',
      code: 'CR0004',
      phone: '+90 532 000 00 04',
      totalDebit: 3000,
      totalCredit: 3000,
      lastTxDate: now.subtract(const Duration(days: 1)),
      groupName: 'Perakende',
      subGroupName: 'Büfe',
      subSubGroupName: 'C Tipi',
      marketerName: 'Zeynep Kaya',
    ),
  ];
}

final customerBalanceReportProvider =
    FutureProvider.autoDispose<List<BalanceReportRow>>((ref) async {
  final token = ref.watch(_balanceReportRequestTokenProvider);
  if (token == 0) {
    return <BalanceReportRow>[];
  }

  final requestedFilters =
      ref.watch(_balanceReportRequestedFiltersProvider);
  if (requestedFilters == null) {
    return <BalanceReportRow>[];
  }
  const repo = AdminReportsRepository(useMockData: true);

  return repo.fetchBalanceReport(
    range: requestedFilters.range,
    status: requestedFilters.status,
    minAbsNet: requestedFilters.minAbsNet,
    search: requestedFilters.search,
    sortField: requestedFilters.sortField,
    sortDesc: requestedFilters.sortDesc,
    groupName: requestedFilters.groupName,
    subGroupName: requestedFilters.subGroupName,
    subSubGroupName: requestedFilters.subSubGroupName,
    marketerName: requestedFilters.marketerName,
  );
});

class CustomerBalanceReportPage extends ConsumerWidget {
  const CustomerBalanceReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filters = ref.watch(balanceReportFiltersProvider);
    final token = ref.watch(_balanceReportRequestTokenProvider);
    final snapshot = ref.watch(balanceReportSnapshotProvider);

    final AsyncValue<List<BalanceReportRow>> reportAsync;
    if (token == 0) {
      reportAsync = const AsyncValue.data(<BalanceReportRow>[]);
    } else {
      reportAsync = ref.watch(customerBalanceReportProvider);
    }

    final hasData = snapshot?.rows.isNotEmpty == true;

    final filtersChanged =
        snapshot != null && snapshot.filters != filters;

    return AppScaffold(
      title: 'Cari Raporları / Bakiye Listesi',
      resizeToAvoidBottomInset: false,
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 40),
          ),
          onPressed: hasData
              ? () async {
                  final current = snapshot;
                  if (current != null) {
                    await _exportBalanceSnapshotToCsv(current);
                  }
                }
              : null,
          icon: const Icon(Icons.grid_on),
          label: const Text('Excel'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 40),
          ),
          onPressed: hasData
              ? () {
                  // Web'de tarayıcı PDF çıktısı için print görünümünü aç.
                  GoRouter.of(context)
                      .go('/customers/reports/balances/print');
                }
              : null,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('PDF Al'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 40),
          ),
          onPressed: hasData
              ? () {
                  GoRouter.of(context)
                      .go('/customers/reports/balances/print');
                }
              : null,
          icon: const Icon(Icons.print),
          label: const Text('Yazdır'),
        ),
        const SizedBox(width: 8),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    'Bu liste, oluşturulduğu andaki güncel bakiyelere göre hazırlanmıştır.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.textTheme.bodySmall?.color?.withValues(
                        alpha: 0.9,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (snapshot != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
              ),
              child: Card(
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cari Bakiye Listesi',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        'Oluşturulma: ${formatDateTimeTr(snapshot.generatedAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        'Filtreler: ${buildFiltersSummary(snapshot.filters)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (filtersChanged)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s4,
              ),
              child: Card(
                color: Colors.amber.withValues(alpha: 0.1),
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: Text(
                          'Filtreler değişti. Güncel liste için "Raporu Getir".',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s8),
            child: _BalanceReportFiltersCard(filters: filters),
          ),
          const SizedBox(height: AppSpacing.s8),
          Expanded(
            child: reportAsync.when(
              loading: () => const AppLoadingState(),
              error: (e, _) => AppErrorState(
                message: 'Rapor yüklenemedi: ${AppException.messageOf(e)}',
                onRetry: () {
                  ref.invalidate(customerBalanceReportProvider);
                },
              ),
              data: (rows) {
                if (token == 0) {
                  return const AppEmptyState(
                    title: 'Henüz rapor oluşturulmadı',
                    subtitle:
                        'Filtreleri ayarlayıp "Raporu Getir" butonuna bastığınızda cari bakiye listesi burada görünecek.',
                  );
                }

                if (rows.isEmpty) {
                  return const AppEmptyState(
                    title: 'Sonuç bulunamadı',
                    subtitle:
                        'Seçilen filtrelere göre cari bakiye kaydı bulunamadı.',
                  );
                }

                final totalDebit = rows.fold<double>(
                  0,
                  (sum, r) => sum + r.totalDebit,
                );
                final totalCredit = rows.fold<double>(
                  0,
                  (sum, r) => sum + r.totalCredit,
                );
                final netTotal = totalDebit - totalCredit;

                final snapshotController =
                    ref.read(balanceReportSnapshotProvider.notifier);
                final requestedFilters = ref
                    .read(_balanceReportRequestedFiltersProvider);
                final existing = snapshotController.state;

                if (requestedFilters != null &&
                    (existing == null || existing.token != token)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final latest = snapshotController.state;
                    if (latest == null || latest.token != token) {
                      snapshotController.state = BalanceReportSnapshot(
                        token: token,
                        generatedAt: DateTime.now(),
                        filters: requestedFilters,
                        rows: List<BalanceReportRow>.from(rows),
                        totalDebit: totalDebit,
                        totalCredit: totalCredit,
                      );
                    }
                  });
                }

                final activeSnapshot =
                    snapshotController.state ??
                        BalanceReportSnapshot(
                          token: token,
                          generatedAt: DateTime.now(),
                          filters: requestedFilters ??
                              const BalanceReportFilters(),
                          rows: List<BalanceReportRow>.from(rows),
                          totalDebit: totalDebit,
                          totalCredit: totalCredit,
                        );

                const spec = _BalanceReportColumnSpec(
                  codeWidth: 120,
                  phoneWidth: 120,
                  groupWidth: 120,
                  subGroupWidth: 120,
                  subSubGroupWidth: 120,
                  marketerWidth: 160,
                  debitWidth: 120,
                  creditWidth: 120,
                  netWidth: 130,
                  lastTxWidth: 110,
                );

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(customerBalanceReportProvider);
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s16,
                          vertical: AppSpacing.s4,
                        ),
                        sliver: SliverPersistentHeader(
                          pinned: true,
                          delegate: _BalanceReportHeaderDelegate(
                            spec: spec,
                            sortField: activeSnapshot.filters.sortField,
                            sortDesc: activeSnapshot.filters.sortDesc,
                            onSortChanged: (field) {
                              _handleSortTap(
                                ref,
                                field,
                              );
                            },
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s16,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final row = activeSnapshot.rows[index];
                              final isZebra = index.isEven;
                              return _BalanceReportGridRow(
                                row: row,
                                spec: spec,
                                isZebra: isZebra,
                              );
                            },
                            childCount: activeSnapshot.rows.length,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s16,
                            vertical: AppSpacing.s12,
                          ),
                          child: _BalanceReportTotalsFooter(
                            totalDebit: totalDebit,
                            totalCredit: totalCredit,
                            netTotal: netTotal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceReportFiltersCard extends ConsumerWidget {
  const _BalanceReportFiltersCard({
    required this.filters,
  });

  final BalanceReportFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final minController = TextEditingController(
      text: filters.minAbsNet == 0
          ? ''
          : filters.minAbsNet.toStringAsFixed(0),
    );

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Tarih aralığı',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Son 30 gün'),
                  selected:
                      filters.range == BalanceReportRange.days30,
                  onSelected: (_) {
                    ref
                        .read(balanceReportFiltersProvider.notifier)
                        .setRange(BalanceReportRange.days30);
                  },
                ),
                ChoiceChip(
                  label: const Text('Son 90 gün'),
                  selected:
                      filters.range == BalanceReportRange.days90,
                  onSelected: (_) {
                    ref
                        .read(balanceReportFiltersProvider.notifier)
                        .setRange(BalanceReportRange.days90);
                  },
                ),
                ChoiceChip(
                  label: const Text('Tümü'),
                  selected: filters.range == BalanceReportRange.all,
                  onSelected: (_) {
                    ref
                        .read(balanceReportFiltersProvider.notifier)
                        .setRange(BalanceReportRange.all);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Durum',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ChoiceChip(
                  label: const Text('Tümü'),
                  selected: filters.status == BalanceReportStatus.all,
                  onSelected: (_) {
                    ref
                        .read(balanceReportFiltersProvider.notifier)
                        .setStatus(BalanceReportStatus.all);
                  },
                ),
                ChoiceChip(
                  label: const Text('Sadece borçlu'),
                  selected:
                      filters.status == BalanceReportStatus.debitOnly,
                  onSelected: (_) {
                    ref
                        .read(balanceReportFiltersProvider.notifier)
                        .setStatus(BalanceReportStatus.debitOnly);
                  },
                ),
                ChoiceChip(
                  label: const Text('Sadece alacaklı'),
                  selected:
                      filters.status == BalanceReportStatus.creditOnly,
                  onSelected: (_) {
                    ref
                        .read(balanceReportFiltersProvider.notifier)
                        .setStatus(BalanceReportStatus.creditOnly);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Minimum bakiye',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _MinBalanceChip(value: 0, label: '0 ₺',
                    filters: filters),
                _MinBalanceChip(
                    value: 1000, label: '1.000 ₺', filters: filters),
                _MinBalanceChip(
                    value: 5000, label: '5.000 ₺', filters: filters),
                _MinBalanceChip(
                    value: 10000, label: '10.000 ₺', filters: filters),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: minController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Serbest (₺)',
                    ),
                    onSubmitted: (value) {
                      final parsed = double.tryParse(
                              value.replaceAll('.', '').replaceAll(',', '.')) ??
                          0;
                      ref
                          .read(balanceReportFiltersProvider.notifier)
                          .setMinAbsNet(parsed);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            // Grup / Ara Grup / Alt Grup filtreleri
            Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final groupsAsync =
                          ref.watch(balanceReportGroupsProvider);
                      return groupsAsync.when(
                        data: (items) {
                          final allItems = <String?>[null, ...items];
                          return DropdownButtonFormField<String?>(
                            initialValue: filters.groupName,
                            decoration: const InputDecoration(
                              labelText: 'Grup',
                            ),
                            isExpanded: true,
                            items: allItems
                                .map(
                                  (g) => DropdownMenuItem<String?>(
                                    value: g,
                                    child: Text(g ?? 'Tümü'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              ref
                                  .read(
                                    balanceReportFiltersProvider
                                        .notifier,
                                  )
                                  .setGroup(value);
                            },
                          );
                        },
                        loading: () => const SizedBox(
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                        error: (e, _) => DropdownButtonFormField<String?>(
                          initialValue: filters.groupName,
                          decoration: const InputDecoration(
                            labelText: 'Grup',
                          ),
                          items: const [],
                          onChanged: (_) {},
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final subGroupsAsync =
                          ref.watch(balanceReportSubGroupsProvider);
                      return subGroupsAsync.when(
                        data: (items) {
                          final allItems = <String?>[null, ...items];
                          return DropdownButtonFormField<String?>(
                            initialValue: filters.subGroupName,
                            decoration: const InputDecoration(
                              labelText: 'Ara Grup',
                            ),
                            isExpanded: true,
                            items: allItems
                                .map(
                                  (g) => DropdownMenuItem<String?>(
                                    value: g,
                                    child: Text(g ?? 'Tümü'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              ref
                                  .read(
                                    balanceReportFiltersProvider
                                        .notifier,
                                  )
                                  .setSubGroup(value);
                            },
                          );
                        },
                        loading: () => const SizedBox(
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                        error: (e, _) => DropdownButtonFormField<String?>(
                          initialValue: filters.subGroupName,
                          decoration: const InputDecoration(
                            labelText: 'Ara Grup',
                          ),
                          items: const [],
                          onChanged: (_) {},
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final subSubGroupsAsync = ref.watch(
                        balanceReportSubSubGroupsProvider,
                      );
                      return subSubGroupsAsync.when(
                        data: (items) {
                          final allItems = <String?>[null, ...items];
                          return DropdownButtonFormField<String?>(
                            initialValue: filters.subSubGroupName,
                            decoration: const InputDecoration(
                              labelText: 'Alt Grup',
                            ),
                            isExpanded: true,
                            items: allItems
                                .map(
                                  (g) => DropdownMenuItem<String?>(
                                    value: g,
                                    child: Text(g ?? 'Tümü'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              ref
                                  .read(
                                    balanceReportFiltersProvider
                                        .notifier,
                                  )
                                  .setSubSubGroup(value);
                            },
                          );
                        },
                        loading: () => const SizedBox(
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                        error: (e, _) => DropdownButtonFormField<String?>(
                          initialValue: filters.subSubGroupName,
                          decoration: const InputDecoration(
                            labelText: 'Alt Grup',
                          ),
                          items: const [],
                          onChanged: (_) {},
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            // Pazarlamacı filtresi
            Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final marketersAsync =
                          ref.watch(balanceReportMarketersProvider);
                      return marketersAsync.when(
                        data: (items) {
                          final allItems = <String?>[null, ...items];
                          return DropdownButtonFormField<String?>(
                            initialValue: filters.marketerName,
                            decoration: const InputDecoration(
                              labelText: 'Pazarlamacı',
                            ),
                            isExpanded: true,
                            items: allItems
                                .map(
                                  (g) => DropdownMenuItem<String?>(
                                    value: g,
                                    child: Text(g ?? 'Tümü'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              ref
                                  .read(
                                    balanceReportFiltersProvider
                                        .notifier,
                                  )
                                  .setMarketer(value);
                            },
                          );
                        },
                        loading: () => const SizedBox(
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        ),
                        error: (e, _) => DropdownButtonFormField<String?>(
                          initialValue: filters.marketerName,
                          decoration: const InputDecoration(
                            labelText: 'Pazarlamacı',
                          ),
                          items: const [],
                          onChanged: (_) {},
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Ünvan / kod / telefon',
                    ),
                    onChanged: (value) {
                      ref
                          .read(balanceReportFiltersProvider.notifier)
                          .setSearch(value);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                PrimaryButton(
                  label: 'Raporu Getir',
                  onPressed: () {
                  final currentFilters =
                    ref.read(balanceReportFiltersProvider);
                  ref
                    .read(_balanceReportRequestedFiltersProvider
                      .notifier)
                    .state = currentFilters;
                  ref
                    .read(_balanceReportRequestTokenProvider.notifier)
                    .state++;
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MinBalanceChip extends ConsumerWidget {
  const _MinBalanceChip({
    required this.value,
    required this.label,
    required this.filters,
  });

  final double value;
  final String label;
  final BalanceReportFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = filters.minAbsNet == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        ref
            .read(balanceReportFiltersProvider.notifier)
            .setMinAbsNet(value);
      },
    );
  }
}

class _BalanceReportColumnSpec {
  const _BalanceReportColumnSpec({
    required this.codeWidth,
    required this.phoneWidth,
    required this.groupWidth,
    required this.subGroupWidth,
    required this.subSubGroupWidth,
    required this.marketerWidth,
    required this.debitWidth,
    required this.creditWidth,
    required this.netWidth,
    required this.lastTxWidth,
  });

  final double codeWidth;
  final double phoneWidth;
  final double groupWidth;
  final double subGroupWidth;
  final double subSubGroupWidth;
  final double marketerWidth;
  final double debitWidth;
  final double creditWidth;
  final double netWidth;
  final double lastTxWidth;
}

class _BalanceReportHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _BalanceReportHeaderDelegate({
    required this.spec,
    required this.sortField,
    required this.sortDesc,
    required this.onSortChanged,
  });

  final _BalanceReportColumnSpec spec;
  final String sortField;
  final bool sortDesc;
  final void Function(String field) onSortChanged;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: overlapsContent ? 2 : 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: _SortableHeaderLabel(
                label: 'Cari Ünvan',
                isActive: sortField == 'name',
                descending: sortDesc,
                onTap: () => onSortChanged('name'),
              ),
            ),
            SizedBox(
              width: spec.codeWidth,
              child: Text(
                'Cari Kodu',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            SizedBox(
              width: spec.phoneWidth,
              child: Text(
                'Telefon',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            SizedBox(
              width: spec.groupWidth,
              child: Text(
                'Grup',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            SizedBox(
              width: spec.subGroupWidth,
              child: Text(
                'Ara Grup',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            SizedBox(
              width: spec.subSubGroupWidth,
              child: Text(
                'Alt Grup',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            SizedBox(
              width: spec.marketerWidth,
              child: Text(
                'Pazarlamacı',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.left,
              ),
            ),
            SizedBox(
              width: spec.debitWidth,
              child: Text(
                'Toplam Borç',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: spec.creditWidth,
              child: Text(
                'Toplam Alacak',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: spec.netWidth,
              child: _SortableHeaderLabel(
                label: 'Net Bakiye',
                isActive: sortField == 'net',
                descending: sortDesc,
                onTap: () => onSortChanged('net'),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: spec.lastTxWidth,
              child: _SortableHeaderLabel(
                label: 'Son İşlem',
                isActive: sortField == 'lastTxDate',
                descending: sortDesc,
                onTap: () => onSortChanged('lastTxDate'),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _BalanceReportHeaderDelegate oldDelegate) {
    return oldDelegate.spec != spec ||
        oldDelegate.sortField != sortField ||
        oldDelegate.sortDesc != sortDesc;
  }
}

class _SortableHeaderLabel extends StatelessWidget {
  const _SortableHeaderLabel({
    required this.label,
    required this.isActive,
    required this.descending,
    required this.onTap,
    this.textAlign,
  });

  final String label;
  final bool isActive;
  final bool descending;
  final VoidCallback onTap;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: isActive ? theme.colorScheme.primary : null,
    );

    Widget child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: textAlign == TextAlign.right
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            label,
            style: style,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign ?? TextAlign.left,
          ),
        ),
        if (isActive) ...[
          const SizedBox(width: 4),
          Icon(
            descending
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 14,
            color: theme.colorScheme.primary,
          ),
        ],
      ],
    );

    return InkWell(
      onTap: onTap,
      child: Align(
        alignment: textAlign == TextAlign.right
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: child,
      ),
    );
  }
}

class _BalanceReportGridRow extends StatelessWidget {
  const _BalanceReportGridRow({
    required this.row,
    required this.spec,
    required this.isZebra,
  });

  final BalanceReportRow row;
  final _BalanceReportColumnSpec spec;
  final bool isZebra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = isZebra
        ? theme.colorScheme.surfaceContainerLowest
        : theme.colorScheme.surface;

    final numberStyle = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final debitText = formatMoney(row.totalDebit);
    final creditText = formatMoney(row.totalCredit);
    final net = row.net;
    final netText = formatMoney(net.abs());
    final netColor = _netColor(theme, net);

    final lastTxText = row.lastTxDate == null
        ? '-'
        : formatDate(row.lastTxDate!);

    return Container(
      height: 44,
      color: backgroundColor,
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                row.name,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: spec.codeWidth,
              child: Text(
                row.code,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: spec.phoneWidth,
              child: Text(
                row.phone,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: spec.groupWidth,
              child: Text(
                row.groupName ?? '',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: spec.subGroupWidth,
              child: Text(
                row.subGroupName ?? '',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: spec.subSubGroupWidth,
              child: Text(
                row.subSubGroupName ?? '',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: spec.marketerWidth,
              child: Text(
                row.marketerName ?? '',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: spec.debitWidth,
              child: Text(
                debitText,
                style: numberStyle,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: spec.creditWidth,
              child: Text(
                creditText,
                style: numberStyle,
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: spec.netWidth,
              child: Text(
                netText,
                style: numberStyle?.copyWith(color: netColor),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: spec.lastTxWidth,
              child: Text(
                lastTxText,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
          ],
        ),
      ),
    );
  }
}

class _BalanceReportTotalsFooter extends StatelessWidget {
  const _BalanceReportTotalsFooter({
    required this.totalDebit,
    required this.totalCredit,
    required this.netTotal,
  });

  final double totalDebit;
  final double totalCredit;
  final double netTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final netColor = _netColor(theme, netTotal);

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            Expanded(
              child: _TotalItem(
                label: 'Toplam Borç',
                value: formatMoney(totalDebit),
                valueColor: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _TotalItem(
                label: 'Toplam Alacak',
                value: formatMoney(totalCredit),
                valueColor: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _TotalItem(
                label: 'Net Toplam',
                value: formatMoney(netTotal),
                valueColor: netColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalItem extends StatelessWidget {
  const _TotalItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

Color _netColor(ThemeData theme, double value) {
  if (value > 0) {
    return Colors.red.shade600;
  }
  if (value < 0) {
    return Colors.green.shade700;
  }
  return theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;
}

void _handleSortTap(WidgetRef ref, String field) {
  final snapshotController = ref.read(balanceReportSnapshotProvider.notifier);
  final current = snapshotController.state;
  if (current == null) {
    return;
  }

  final currentFilters = current.filters;
  final isSameField = currentFilters.sortField == field;
  final nextDesc = isSameField ? !currentFilters.sortDesc : true;

  final rows = List<BalanceReportRow>.from(current.rows);

  int compare(BalanceReportRow a, BalanceReportRow b) {
    switch (field) {
      case 'name':
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case 'lastTxDate':
        final ad = a.lastTxDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.lastTxDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      case 'net':
      default:
        return a.net.compareTo(b.net);
    }
  }

  int compareWithOrder(BalanceReportRow a, BalanceReportRow b) {
    return nextDesc ? compare(b, a) : compare(a, b);
  }

  rows.sort(compareWithOrder);

  final updatedFilters = currentFilters.copyWith(
    sortField: field,
    sortDesc: nextDesc,
  );

  snapshotController.state = current.copyWith(
    filters: updatedFilters,
    rows: rows,
  );

  // Bir sonraki rapor isteğinde de aynı sıralamanın kullanılması için
  ref.read(balanceReportFiltersProvider.notifier).setSort(
        field,
        nextDesc,
      );
}

String formatDateTimeTr(DateTime value) {
  final date = formatDate(value);
  final time = '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  return '$date $time';
}

String _twoDigits(int v) => v.toString().padLeft(2, '0');

String buildFiltersSummary(BalanceReportFilters filters) {
  final parts = <String>[];

  switch (filters.range) {
    case BalanceReportRange.days30:
      parts.add('Tarih: Son 30 gün');
      break;
    case BalanceReportRange.days90:
      parts.add('Tarih: Son 90 gün');
      break;
    case BalanceReportRange.all:
      parts.add('Tarih: Tümü');
      break;
  }

  switch (filters.status) {
    case BalanceReportStatus.all:
      parts.add('Durum: Tümü');
      break;
    case BalanceReportStatus.debitOnly:
      parts.add('Durum: Sadece borçlu');
      break;
    case BalanceReportStatus.creditOnly:
      parts.add('Durum: Sadece alacaklı');
      break;
  }

  parts.add('Min bakiye: ${formatMoney(filters.minAbsNet)}');

  if (filters.search.trim().isNotEmpty) {
    parts.add('Arama: "${filters.search.trim()}"');
  }
  if (filters.groupName != null && filters.groupName!.trim().isNotEmpty) {
    parts.add('Grup: ${filters.groupName!.trim()}');
  }

  if (filters.subGroupName != null &&
      filters.subGroupName!.trim().isNotEmpty) {
    parts.add('Ara Grup: ${filters.subGroupName!.trim()}');
  }

  if (filters.subSubGroupName != null &&
      filters.subSubGroupName!.trim().isNotEmpty) {
    parts.add('Alt Grup: ${filters.subSubGroupName!.trim()}');
  }

  if (filters.marketerName != null &&
      filters.marketerName!.trim().isNotEmpty) {
    parts.add('Pazarlamacı: ${filters.marketerName!.trim()}');
  }

  return parts.join(' • ');
}

Future<void> _exportBalanceSnapshotToCsv(
  BalanceReportSnapshot snapshot, {
  bool includeColumnLetters = true,
}) async {
  final buffer = StringBuffer();

  // UTF-8 BOM, Excel'de Türkçe karakterlerin doğru görünmesi için
  buffer.write('\uFEFF');

  // Opsiyonel A–Z header satırı (default açık)
  if (includeColumnLetters) {
    buffer.writeln('A;B;C;D;E;F;G;H;I;J;K');
  }

  // Noktalı virgül ayraç + tamamen Türkçe başlıklar,
  // grid ve print ile aynı kolon sırası
  buffer.writeln(
    'Cari Ünvan;Cari Kodu;Telefon;Grup;Ara Grup;Alt Grup;Pazarlamacı;Toplam Borç;Toplam Alacak;Net Bakiye;Son İşlem',
  );

  for (final row in snapshot.rows) {
    final lastTxText =
        row.lastTxDate == null ? '-' : formatDate(row.lastTxDate!);

    final cells = [
      row.name,
      row.code,
      row.phone,
      row.groupName ?? '',
      row.subGroupName ?? '',
      row.subSubGroupName ?? '',
      row.marketerName ?? '',
      _formatNumberForExcel(row.totalDebit),
      _formatNumberForExcel(row.totalCredit),
      _formatNumberForExcel(row.net),
      lastTxText,
    ];

    buffer.writeln(cells.map(_escapeCsvCell).join(';'));
  }

  final csvBytes = utf8.encode(buffer.toString());

  await exportCsvBytes(
    bytes: csvBytes,
    fileName: 'bakiye_raporu.csv',
  );
}

String _escapeCsvCell(String value) {
  var v = value;
  if (v.contains('"')) {
    v = v.replaceAll('"', '""');
  }
  // Noktalı virgül ayraç olduğu için sadece ; ve satır sonunu kaçır
  if (v.contains(';') || v.contains('\n')) {
    v = '"$v"';
  }
  return v;
}

String _formatNumberForExcel(double value) {
  // Türkçe Excel için: ondalık ayracı virgül, binlik yok
  final text = value.toStringAsFixed(2).replaceAll('.', ',');
  return text;
}

class CustomerBalanceReportPrintPage extends ConsumerStatefulWidget {
  const CustomerBalanceReportPrintPage({super.key});

  @override
  ConsumerState<CustomerBalanceReportPrintPage> createState() =>
      _CustomerBalanceReportPrintPageState();
}

class _CustomerBalanceReportPrintPageState
    extends ConsumerState<CustomerBalanceReportPrintPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await printPageIfSupported();
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(balanceReportSnapshotProvider);

    if (snapshot == null) {
      return const AppScaffold(
        title: 'Cari Bakiye Listesi – Yazdır',
        body: Center(
          child: Text('Henüz oluşturulmuş bir bakiye raporu yok.'),
        ),
      );
    }

    final theme = Theme.of(context);
    final filtersSummary = buildFiltersSummary(snapshot.filters);
    final createdText = formatDateTimeTr(snapshot.generatedAt);

    return Scaffold(
      backgroundColor: Colors.grey.shade300,
      body: SafeArea(
        child: Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cari Bakiye Listesi',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Oluşturulma: $createdText',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Filtreler: $filtersSummary',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Table(
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          columnWidths: const {
                            0: FlexColumnWidth(3), // Ünvan
                            1: FlexColumnWidth(2), // Kod
                            2: FlexColumnWidth(2), // Telefon
                            3: FlexColumnWidth(2), // Grup
                            4: FlexColumnWidth(2), // Ara Grup
                            5: FlexColumnWidth(2), // Alt Grup
                            6: FlexColumnWidth(2), // Pazarlamacı
                            7: FlexColumnWidth(2), // Toplam Borç
                            8: FlexColumnWidth(2), // Toplam Alacak
                            9: FlexColumnWidth(2), // Net Bakiye
                            10: FlexColumnWidth(2), // Son İşlem
                            11: FlexColumnWidth(2), // İmza
                            12: FlexColumnWidth(2), // Alınan
                          },
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                              ),
                              children: [
                                _printHeaderCell('Cari Ünvan'),
                                _printHeaderCell('Cari Kodu'),
                                _printHeaderCell('Telefon'),
                                _printHeaderCell('Grup'),
                                _printHeaderCell('Ara Grup'),
                                _printHeaderCell('Alt Grup'),
                                _printHeaderCell('Pazarlamacı'),
                                _printHeaderCell('Toplam Borç',
                                    alignRight: true),
                                _printHeaderCell('Toplam Alacak',
                                    alignRight: true),
                                _printHeaderCell('Net Bakiye',
                                    alignRight: true),
                                _printHeaderCell('Son İşlem'),
                                _printHeaderCell('İmza'),
                                _printHeaderCell('Alınan'),
                              ],
                            ),
                            ...snapshot.rows.map(
                              (r) {
                                final debitText = formatMoney(r.totalDebit);
                                final creditText =
                                    formatMoney(r.totalCredit);
                                final netText =
                                    formatMoney(r.net.abs());
                                final lastTxText = r.lastTxDate == null
                                    ? '-'
                                    : formatDate(r.lastTxDate!);

                                return TableRow(
                                  decoration: BoxDecoration(
                                    color:
                                        snapshot.rows.indexOf(r).isEven
                                            ? Colors.white
                                            : Colors.grey.shade50,
                                  ),
                                  children: [
                                    _printBodyCell(r.name),
                                    _printBodyCell(r.code),
                                    _printBodyCell(r.phone),
                                    _printBodyCell(r.groupName ?? ''),
                                    _printBodyCell(r.subGroupName ?? ''),
                                    _printBodyCell(r.subSubGroupName ?? ''),
                                    _printBodyCell(r.marketerName ?? ''),
                                    _printBodyCell(debitText,
                                        alignRight: true),
                                    _printBodyCell(creditText,
                                        alignRight: true),
                                    _printBodyCell(netText,
                                        alignRight: true),
                                    _printBodyCell(lastTxText),
                                    _printBodyCell(''),
                                    _printBodyCell(''),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _TotalItem(
                        label: 'Toplam Borç',
                        value: formatMoney(snapshot.totalDebit),
                        valueColor:
                            theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: _TotalItem(
                        label: 'Toplam Alacak',
                        value: formatMoney(snapshot.totalCredit),
                        valueColor:
                            theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: _TotalItem(
                        label: 'Net Toplam',
                        value: formatMoney(snapshot.netTotal),
                        valueColor:
                            _netColor(theme, snapshot.netTotal),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Bu liste, raporun oluşturulduğu andaki güncel bakiyelere göre düzenlenmiştir.',
                  style: theme.textTheme.bodySmall,
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Not: "Yazdır" işlevi şu anda sadece web sürümünde tam desteklenmektedir.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _printHeaderCell(String text, {bool alignRight = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 11,
      ),
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
    ),
  );
}

Widget _printBodyCell(String text, {bool alignRight = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
      ),
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
