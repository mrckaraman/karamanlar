import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuditLogFilters {
  const AuditLogFilters({
    this.entity,
    this.action,
    this.from,
    this.to,
    this.createdBy,
  });

  final String? entity;
  final String? action;
  final DateTime? from;
  final DateTime? to;
  final String? createdBy;

  AuditLogFilters copyWith({
    String? entity,
    String? action,
    DateTime? from,
    DateTime? to,
    String? createdBy,
  }) {
    return AuditLogFilters(
      entity: entity ?? this.entity,
      action: action ?? this.action,
      from: from ?? this.from,
      to: to ?? this.to,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  static AuditLogFilters empty() => const AuditLogFilters();
}

class AuditLogsViewState {
  const AuditLogsViewState({
    required this.items,
    required this.filters,
    required this.hasMore,
    required this.isLoadingMore,
  });

  final List<AuditLogEntry> items;
  final AuditLogFilters filters;
  final bool hasMore;
  final bool isLoadingMore;

  int get offset => items.length;

  AuditLogsViewState copyWith({
    List<AuditLogEntry>? items,
    AuditLogFilters? filters,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return AuditLogsViewState(
      items: items ?? this.items,
      filters: filters ?? this.filters,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

class AuditLogsController extends AutoDisposeAsyncNotifier<AuditLogsViewState> {
  static const int pageSize = 50;

  @override
  Future<AuditLogsViewState> build() async {
    final initialFilters = AuditLogFilters.empty();

    final result = await AsyncValue.guard(() async {
      final items = await auditRepository.fetchAuditLogs(
        entity: initialFilters.entity,
        action: initialFilters.action,
        from: initialFilters.from,
        to: initialFilters.to,
        createdBy: initialFilters.createdBy,
        limit: pageSize,
        offset: 0,
      );

      return AuditLogsViewState(
        items: items,
        filters: initialFilters,
        hasMore: items.length == pageSize,
        isLoadingMore: false,
      );
    });

    if (result.hasError) {
      throw result.error!;
    }

    return result.requireValue;
  }

  AuditLogFilters get currentFilters =>
      state.valueOrNull?.filters ?? AuditLogFilters.empty();

  Future<void> reloadWithFilters(AuditLogFilters filters) async {
    state = const AsyncLoading<AuditLogsViewState>();

    final result = await AsyncValue.guard(() async {
      final items = await auditRepository.fetchAuditLogs(
        entity: filters.entity,
        action: filters.action,
        from: filters.from,
        to: filters.to,
        createdBy: filters.createdBy,
        limit: pageSize,
        offset: 0,
      );

      return AuditLogsViewState(
        items: items,
        filters: filters,
        hasMore: items.length == pageSize,
        isLoadingMore: false,
      );
    });

    state = result;
  }

  Future<void> clearFilters() => reloadWithFilters(AuditLogFilters.empty());

  Future<Object?> loadMore() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.isLoadingMore) return null;
    if (!current.hasMore) return null;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    final result = await AsyncValue.guard(() async {
      final fetched = await auditRepository.fetchAuditLogs(
        entity: current.filters.entity,
        action: current.filters.action,
        from: current.filters.from,
        to: current.filters.to,
        createdBy: current.filters.createdBy,
        limit: pageSize,
        offset: current.offset,
      );

      final merged = _mergeDedupById(current.items, fetched);

      return current.copyWith(
        items: merged,
        hasMore: fetched.length == pageSize,
        isLoadingMore: false,
      );
    });

    if (result.hasError) {
      // Load-more hatasında mevcut listeyi koru.
      state = AsyncData(current.copyWith(isLoadingMore: false));
      return result.error;
    }

    state = AsyncData(result.requireValue);
    return null;
  }

  List<AuditLogEntry> _mergeDedupById(
    List<AuditLogEntry> current,
    List<AuditLogEntry> fetched,
  ) {
    if (fetched.isEmpty) return current;

    final seen = <String>{for (final e in current) e.id};
    final out = <AuditLogEntry>[...current];

    for (final e in fetched) {
      if (e.id.isEmpty) continue;
      if (seen.add(e.id)) {
        out.add(e);
      }
    }

    return out;
  }
}

final auditLogsProvider =
    AutoDisposeAsyncNotifierProvider<AuditLogsController, AuditLogsViewState>(
  AuditLogsController.new,
);
