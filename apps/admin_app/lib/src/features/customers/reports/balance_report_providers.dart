import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_customer_reports_repository.dart';
import 'report_filters.dart';

enum BalanceSortField {
  netBalance('net_balance'),
  customerCode('customer_code'),
  title('title'),
  groupName('group_name'),
  limitUsagePercent('limit_usage_percent'),
  lastShipmentAt('last_shipment_at'),
  lastPaymentDate('last_payment_date');

  const BalanceSortField(this.db);
  final String db;
}

final balanceNormalizedFiltersProvider =
    Provider.autoDispose<BalanceReportNormalizedFilters>(
  (ref) {
    final filters = ref.watch(balanceReportFiltersProvider);
    return BalanceReportNormalizedFilters.fromUi(filters);
  },
);

class BalanceReportFiltersNotifier extends StateNotifier<BalanceReportFilters> {
  BalanceReportFiltersNotifier() : super(const BalanceReportFilters());

  void setStatus(BalanceStatusFilter value) {
    state = state.copyWith(status: value);
  }

  void setMinAbsNet(double value) {
    state = state.copyWith(minAbsNet: value);
  }

  void setSearch(String value) {
    state = state.copyWith(search: value);
  }

  void setGroup(String? value) {
    state = state.copyWith(
      groupName: value,
      clearSubGroup: true,
      clearAltGroup: true,
    );
  }

  void setSubGroup(String? value) {
    state = state.copyWith(
      subGroup: value,
      clearAltGroup: true,
    );
  }

  void setAltGroup(String? value) {
    state = state.copyWith(altGroup: value);
  }

  void setMarketer(String? value) {
    state = state.copyWith(marketerName: value);
  }

  void clearAll() {
    state = const BalanceReportFilters();
  }
}

final balanceReportFiltersProvider =
    StateNotifierProvider<BalanceReportFiltersNotifier, BalanceReportFilters>(
  (ref) => BalanceReportFiltersNotifier(),
);

class BalanceReportTableState {
  const BalanceReportTableState({
    this.pageSize = 25,
    this.pageIndex = 0,
    this.sortField = BalanceSortField.netBalance,
    this.sortDesc = true,
  });

  final int pageSize;
  final int pageIndex;
  final BalanceSortField sortField;
  final bool sortDesc;

  int get offset => pageIndex * pageSize;

  BalanceReportTableState copyWith({
    int? pageSize,
    int? pageIndex,
    BalanceSortField? sortField,
    bool? sortDesc,
  }) {
    return BalanceReportTableState(
      pageSize: pageSize ?? this.pageSize,
      pageIndex: pageIndex ?? this.pageIndex,
      sortField: sortField ?? this.sortField,
      sortDesc: sortDesc ?? this.sortDesc,
    );
  }
}

class BalanceReportTableNotifier extends StateNotifier<BalanceReportTableState> {
  BalanceReportTableNotifier() : super(const BalanceReportTableState());

  void setPageIndex(int index) {
    state = state.copyWith(pageIndex: index);
  }

  void setPageSize(int size) {
    state = state.copyWith(pageSize: size, pageIndex: 0);
  }

  void setSort(BalanceSortField field) {
    final nextDesc = state.sortField == field ? !state.sortDesc : true;
    state = state.copyWith(sortField: field, sortDesc: nextDesc, pageIndex: 0);
  }

  void resetPage() {
    state = state.copyWith(pageIndex: 0);
  }
}

final balanceReportTableProvider =
    StateNotifierProvider<BalanceReportTableNotifier, BalanceReportTableState>(
  (ref) => BalanceReportTableNotifier(),
);

final balanceSelectionProvider =
    StateNotifierProvider<_BalanceSelectionNotifier, Set<String>>(
  (ref) => _BalanceSelectionNotifier(),
);

class _BalanceSelectionNotifier extends StateNotifier<Set<String>> {
  _BalanceSelectionNotifier() : super(<String>{});

  void toggle(String customerId) {
    final next = Set<String>.from(state);
    if (!next.add(customerId)) {
      next.remove(customerId);
    }
    state = next;
  }

  void clear() {
    state = <String>{};
  }

  void setAll(Iterable<String> ids) {
    state = ids.toSet();
  }
}

final balanceSnapshotProvider = FutureProvider.autoDispose<BalanceSnapshotDto>(
  (ref) async {
    final repo = adminCustomerReportsRepository;
    final filters = ref.watch(balanceNormalizedFiltersProvider);

    return repo.fetchBalanceSnapshot(
      minAbsNet: filters.minAbsNet,
      status: filters.status,
      groupName: filters.groupName,
      subGroup: filters.subGroup,
      altGroup: filters.altGroup,
      marketerName: filters.marketerName,
      search: filters.search,
    );
  },
);

final balancePageProvider =
    FutureProvider.autoDispose<List<BalanceReportRowDto>>(
  (ref) async {
    final repo = adminCustomerReportsRepository;
    final filters = ref.watch(balanceNormalizedFiltersProvider);
    final table = ref.watch(balanceReportTableProvider);

    return repo.fetchBalancePage(
      minAbsNet: filters.minAbsNet,
      status: filters.status,
      limit: table.pageSize,
      offset: table.offset,
      sortField: table.sortField.db,
      sortDesc: table.sortDesc,
      groupName: filters.groupName,
      subGroup: filters.subGroup,
      altGroup: filters.altGroup,
      marketerName: filters.marketerName,
      search: filters.search,
    );
  },
);
