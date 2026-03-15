import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_customer_reports_repository.dart';
import 'balance_report_providers.dart' show balanceNormalizedFiltersProvider;

class RiskTopTableState {
  const RiskTopTableState({
    this.limit = 25,
    this.offset = 0,
    this.sortField = 'limit_usage_percent',
    this.sortDesc = true,
  });

  final int limit;
  final int offset;
  final String sortField;
  final bool sortDesc;

  RiskTopTableState copyWith({
    int? limit,
    int? offset,
    String? sortField,
    bool? sortDesc,
  }) {
    return RiskTopTableState(
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      sortField: sortField ?? this.sortField,
      sortDesc: sortDesc ?? this.sortDesc,
    );
  }
}

class RiskTopTableNotifier extends StateNotifier<RiskTopTableState> {
  RiskTopTableNotifier() : super(const RiskTopTableState());

  void setLimit(int v) {
    state = state.copyWith(limit: v, offset: 0);
  }

  void setSort({required String field}) {
    final nextDesc = (state.sortField == field) ? !state.sortDesc : true;
    state = state.copyWith(sortField: field, sortDesc: nextDesc, offset: 0);
  }

  void reset() {
    state = const RiskTopTableState();
  }
}

final riskTopTableProvider =
    StateNotifierProvider<RiskTopTableNotifier, RiskTopTableState>(
  (ref) => RiskTopTableNotifier(),
);

final riskSnapshotProvider = FutureProvider.autoDispose<RiskSnapshotDto>(
  (ref) async {
    final repo = adminCustomerReportsRepository;
    final filters = ref.watch(balanceNormalizedFiltersProvider);
    return repo.fetchRiskSnapshot(filters);
  },
);

final riskTopProvider = FutureProvider.autoDispose<List<RiskTopRowDto>>(
  (ref) async {
    final repo = adminCustomerReportsRepository;
    final filters = ref.watch(balanceNormalizedFiltersProvider);
    final table = ref.watch(riskTopTableProvider);

    return repo.fetchRiskTop(
      filters,
      limit: table.limit,
      offset: table.offset,
      sortField: table.sortField,
      sortDesc: table.sortDesc,
    );
  },
);

class RiskScoreTableState {
  const RiskScoreTableState({
    this.limit = 25,
    this.offset = 0,
  });

  final int limit;
  final int offset;

  RiskScoreTableState copyWith({
    int? limit,
    int? offset,
  }) {
    return RiskScoreTableState(
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }
}

class RiskScoreTableNotifier extends StateNotifier<RiskScoreTableState> {
  RiskScoreTableNotifier() : super(const RiskScoreTableState());

  void setLimit(int v) {
    state = state.copyWith(limit: v, offset: 0);
  }

  void setOffset(int v) {
    state = state.copyWith(offset: v);
  }

  void reset() {
    state = const RiskScoreTableState();
  }
}

final riskScoreTableProvider =
    StateNotifierProvider<RiskScoreTableNotifier, RiskScoreTableState>(
  (ref) => RiskScoreTableNotifier(),
);

final riskAgingSnapshotProvider = FutureProvider.autoDispose<AgingSnapshotDto>(
  (ref) async {
    final repo = adminCustomerReportsRepository;
    final filters = ref.watch(balanceNormalizedFiltersProvider);
    return repo.fetchRiskAgingSnapshot(filters);
  },
);

final riskScoredTopProvider = FutureProvider.autoDispose<List<RiskScoreRowDto>>(
  (ref) async {
    final repo = adminCustomerReportsRepository;
    final table = ref.watch(riskScoreTableProvider);
    return repo.fetchRiskScoredTop(limit: table.limit, offset: table.offset);
  },
);
