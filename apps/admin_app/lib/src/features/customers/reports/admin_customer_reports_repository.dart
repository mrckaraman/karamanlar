import 'package:core/core.dart' show supabaseClient;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'report_filters.dart';

class BalanceSnapshotDto {
  const BalanceSnapshotDto({
    required this.totalDebit,
    required this.totalCredit,
    required this.netRisk,
    required this.riskyCount,
    required this.limitExceededCount,
    required this.rowCount,
  });

  final double totalDebit;
  final double totalCredit;
  final double netRisk;
  final int riskyCount;
  final int limitExceededCount;
  final int rowCount;

  /// Alias for backends that return `net_total`.
  double get netTotal => netRisk;
}

class BalanceReportRowDto {
  const BalanceReportRowDto({
    required this.customerId,
    required this.customerCode,
    required this.displayName,
    required this.groupName,
    required this.netBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.limitAmount,
    required this.limitUsagePercent,
    required this.lastShipmentAt,
    required this.lastInvoiceDate,
    required this.lastPaymentDate,
    required this.statusBadge,
    required this.isLimitExceeded,
    required this.isActive,
  });

  final String customerId;
  final String customerCode;
  final String displayName;
  final String? groupName;
  final double netBalance;
  final double totalDebit;
  final double totalCredit;
  final double limitAmount;
  final double limitUsagePercent;
  final DateTime? lastShipmentAt;
  final DateTime? lastInvoiceDate;
  final DateTime? lastPaymentDate;
  final String statusBadge;
  final bool isLimitExceeded;
  final bool isActive;

  /// Backward-compatible alias.
  String get title => displayName;

  factory BalanceReportRowDto.fromMap(Map<String, dynamic> map) {
    dynamic pick(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v != null) return v;
      }
      return null;
    }

    String? pickNullableString(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return null;
    }

    String pickString(List<String> keys, {String fallback = ''}) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        if (v is String) {
          final s = v.trim();
          if (s.isNotEmpty) return s;
        } else {
          final s = v.toString().trim();
          if (s.isNotEmpty) return s;
        }
      }
      return fallback;
    }

    double pickDouble(List<String> keys, {double fallback = 0}) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? fallback;
      }
      return fallback;
    }

    bool pickBool(List<String> keys, {bool fallback = false}) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) {
          final s = v.trim().toLowerCase();
          if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
          if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
        }
      }
      return fallback;
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    final displayName = pickString(
      const [
        'display_name',
        'displayName',
        'title',
        'trade_title',
        'tradeTitle',
        'full_name',
        'fullName',
      ],
    );

    final limitUsagePercent = pickDouble(
      const ['limit_usage_percent', 'limitUsagePercent'],
    );

    final isLimitExceeded = pickBool(
      const ['is_limit_exceeded', 'isLimitExceeded'],
      fallback: limitUsagePercent >= 100,
    );

    final statusBadge = pickString(
      const ['status_badge', 'statusBadge'],
    );

    final isActive = pickBool(
      const ['is_active', 'isActive', 'active'],
      fallback: true,
    );

    final computedBadge = () {
      if (isLimitExceeded) return 'limit_exceeded';
      if (limitUsagePercent >= 80) return 'risky';
      return 'normal';
    }();

    return BalanceReportRowDto(
      customerId: (map['customer_id'] ?? map['customerId'])?.toString() ?? '',
      customerCode: pickString(const ['customer_code', 'customerCode']),
      displayName: displayName,
      groupName: pickNullableString(const ['group_name', 'groupName']),
      netBalance: pickDouble(const ['net_balance', 'netBalance']),
      totalDebit: pickDouble(const ['total_debit', 'totalDebt', 'totalDebit']),
      totalCredit: pickDouble(const ['total_credit', 'totalCredit']),
      limitAmount: pickDouble(const ['limit_amount', 'limitAmount']),
      limitUsagePercent: limitUsagePercent,
      lastShipmentAt: parseDate(pick(const ['last_shipment_at', 'lastShipmentAt'])),
      lastInvoiceDate: parseDate(pick(const ['last_invoice_date', 'lastInvoiceDate'])),
      lastPaymentDate: parseDate(pick(const ['last_payment_date', 'lastPaymentDate'])),
      statusBadge: statusBadge.isEmpty ? computedBadge : statusBadge,
      isLimitExceeded: isLimitExceeded,
      isActive: isActive,
    );
  }
}

class RiskSnapshotDto {
  const RiskSnapshotDto({
    required this.totalDebt,
    required this.totalCredit,
    required this.netTotal,
    required this.rowCount,
    required this.limitExceededCount,
    required this.riskyCount,
    required this.avgLimitUsage,
  });

  final double totalDebt;
  final double totalCredit;
  final double netTotal;
  final int rowCount;
  final int limitExceededCount;
  final int riskyCount;
  final double avgLimitUsage;
}

class RiskTopRowDto {
  const RiskTopRowDto({
    required this.customerId,
    required this.customerCode,
    required this.displayName,
    required this.groupName,
    required this.subGroup,
    required this.altGroup,
    required this.marketerName,
    required this.isActive,
    required this.netBalance,
    required this.debt,
    required this.credit,
    required this.limitAmount,
    required this.limitUsagePercent,
    required this.isLimitExceeded,
    required this.lastInvoiceDate,
    required this.lastPaymentDate,
  });

  final String customerId;
  final String customerCode;
  final String displayName;
  final String? groupName;
  final String? subGroup;
  final String? altGroup;
  final String? marketerName;
  final bool isActive;
  final double netBalance;
  final double debt;
  final double credit;
  final double limitAmount;
  final double limitUsagePercent;
  final bool isLimitExceeded;
  final DateTime? lastInvoiceDate;
  final DateTime? lastPaymentDate;

  factory RiskTopRowDto.fromMap(Map<String, dynamic> map) {
    dynamic pick(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v != null) return v;
      }
      return null;
    }

    String pickString(List<String> keys, {String fallback = ''}) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return fallback;
    }

    String? pickNullableString(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return null;
    }

    double pickDouble(List<String> keys, {double fallback = 0}) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? fallback;
      }
      return fallback;
    }

    bool pickBool(List<String> keys, {bool fallback = false}) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) {
          final s = v.trim().toLowerCase();
          if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
          if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
        }
      }
      return fallback;
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    final limitUsagePercent = pickDouble(
      const ['limit_usage_percent', 'limitUsagePercent'],
    );

    final isLimitExceeded = pickBool(
      const ['is_limit_exceeded', 'isLimitExceeded'],
      fallback: limitUsagePercent >= 100,
    );

    return RiskTopRowDto(
      customerId: (map['customer_id'] ?? map['customerId'])?.toString() ?? '',
      customerCode: pickString(const ['customer_code', 'customerCode']),
      displayName: pickString(const ['display_name', 'displayName', 'title']),
      groupName: pickNullableString(const ['group_name', 'groupName']),
      subGroup: pickNullableString(const ['sub_group', 'subGroup']),
      altGroup: pickNullableString(const ['alt_group', 'altGroup']),
      marketerName: pickNullableString(const ['marketer_name', 'marketerName']),
      isActive: pickBool(const ['is_active', 'isActive', 'active'], fallback: true),
      netBalance: pickDouble(const ['net_balance', 'netBalance']),
      debt: pickDouble(const ['debt']),
      credit: pickDouble(const ['credit']),
      limitAmount: pickDouble(const ['limit_amount', 'limitAmount']),
      limitUsagePercent: limitUsagePercent,
      isLimitExceeded: isLimitExceeded,
      lastInvoiceDate: parseDate(pick(const ['last_invoice_date', 'lastInvoiceDate'])),
      lastPaymentDate: parseDate(pick(const ['last_payment_date', 'lastPaymentDate'])),
    );
  }
}

class AgingSnapshotDto {
  const AgingSnapshotDto({
    required this.amount0to7,
    required this.amount8to14,
    required this.amount15to30,
    required this.amountOver30,
    required this.totalOverdueAmount,
    required this.overdueCustomerCount,
  });

  final double amount0to7;
  final double amount8to14;
  final double amount15to30;
  final double amountOver30;
  final double totalOverdueAmount;
  final int overdueCustomerCount;
}

class RiskScoreRowDto {
  const RiskScoreRowDto({
    required this.customerId,
    required this.customerCode,
    required this.displayName,
    required this.isActive,
    required this.netBalance,
    required this.limitAmount,
    required this.limitUsagePercent,
    required this.overdueAmount,
    required this.riskScore,
    required this.riskLevel,
  });

  final String customerId;
  final String customerCode;
  final String displayName;
  final bool isActive;
  final double netBalance;
  final double limitAmount;
  final double limitUsagePercent;
  final double overdueAmount;
  final double riskScore;
  final String riskLevel; // low/medium/high

  factory RiskScoreRowDto.fromMap(Map<String, dynamic> map) {
    String pickString(List<String> keys, {String fallback = ''}) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return fallback;
    }

    double pickDouble(List<String> keys, {double fallback = 0}) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? fallback;
      }
      return fallback;
    }

    bool pickBool(List<String> keys, {bool fallback = false}) {
      for (final k in keys) {
        final v = map[k];
        if (v == null) continue;
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) {
          final s = v.trim().toLowerCase();
          if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
          if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
        }
      }
      return fallback;
    }

    return RiskScoreRowDto(
      customerId: (map['customer_id'] ?? map['customerId'])?.toString() ?? '',
      customerCode: pickString(const ['customer_code', 'customerCode']),
      displayName: pickString(const ['display_name', 'displayName', 'title']),
      isActive: pickBool(const ['is_active', 'isActive', 'active'], fallback: true),
      netBalance: pickDouble(const ['net_balance', 'netBalance']),
      limitAmount: pickDouble(const ['limit_amount', 'limitAmount']),
      limitUsagePercent: pickDouble(const ['limit_usage_percent', 'limitUsagePercent']),
      overdueAmount: pickDouble(const ['overdue_amount', 'overdueAmount']),
      riskScore: pickDouble(const ['risk_score', 'riskScore']),
      riskLevel: pickString(const ['risk_level', 'riskLevel']),
    );
  }
}

class AdminCustomerReportsRepository {
  AdminCustomerReportsRepository({SupabaseClient? client})
      : _client = client ?? supabaseClient;

  final SupabaseClient _client;

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) {
      return data.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map) {
        return first.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }

    return const <String, dynamic>{};
  }

  num _asNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  RiskSnapshotDto _parseRiskSnapshot(dynamic raw) {
    final map = _asMap(raw);

    final snapRaw = map['snap'];
    final snap = snapRaw is Map ? _asMap(snapRaw) : map;

    final totalDebt = _asNum(snap['total_debt'] ?? snap['total_debit']);
    final totalCredit = _asNum(snap['total_credit']);
    final netTotal = _asNum(snap['net_total'] ?? snap['net_risk']);

    return RiskSnapshotDto(
      totalDebt: totalDebt.toDouble(),
      totalCredit: totalCredit.toDouble(),
      netTotal: netTotal.toDouble(),
      rowCount: _asNum(snap['row_count']).toInt(),
      limitExceededCount: _asNum(snap['limit_exceeded_count']).toInt(),
      riskyCount: _asNum(snap['risky_count']).toInt(),
      avgLimitUsage: _asNum(snap['avg_limit_usage']).toDouble(),
    );
  }

  AgingSnapshotDto _parseAgingSnapshot(dynamic raw) {
    final map = _asMap(raw);

    final snapRaw = map['snap'];
    final snap = snapRaw is Map ? _asMap(snapRaw) : map;

    return AgingSnapshotDto(
      amount0to7: _asNum(snap['0_7_days_amount']).toDouble(),
      amount8to14: _asNum(snap['8_14_days_amount']).toDouble(),
      amount15to30: _asNum(snap['15_30_days_amount']).toDouble(),
      amountOver30: _asNum(snap['over_30_days_amount']).toDouble(),
      totalOverdueAmount: _asNum(snap['total_overdue_amount']).toDouble(),
      overdueCustomerCount: _asNum(snap['overdue_customer_count']).toInt(),
    );
  }

  BalanceSnapshotDto _parseSnapshot(dynamic raw) {
    final map = _asMap(raw);

    final snapRaw = map['snap'];
    final snap = snapRaw is Map ? _asMap(snapRaw) : map;

    final totalDebit = _asNum(snap['total_debit'] ?? snap['total_debt']);
    final totalCredit = _asNum(snap['total_credit']);
    final netRisk = _asNum(snap['net_risk'] ?? snap['net_total']);

    return BalanceSnapshotDto(
      totalDebit: totalDebit.toDouble(),
      totalCredit: totalCredit.toDouble(),
      netRisk: netRisk.toDouble(),
      riskyCount: _asNum(snap['risky_count']).toInt(),
      limitExceededCount: _asNum(snap['limit_exceeded_count']).toInt(),
      rowCount: _asNum(snap['row_count']).toInt(),
    );
  }

  Future<BalanceSnapshotDto> fetchBalanceSnapshot({
    required double? minAbsNet,
    required String? status,
    String? groupName,
    String? subGroup,
    String? altGroup,
    String? marketerName,
    String? search,
  }) async {
    final raw = await _client.rpc(
      'rpc_admin_customer_balance_snapshot',
      params: <String, dynamic>{
        'p_min_abs_net': minAbsNet,
        'p_status': status,
        'p_group_name': groupName,
        'p_sub_group': subGroup,
        'p_alt_group': altGroup,
        'p_marketer_name': marketerName,
        'p_search': search,
      },
    );

    return _parseSnapshot(raw);
  }

  Future<List<BalanceReportRowDto>> fetchBalancePage({
    required double? minAbsNet,
    required String? status,
    required int limit,
    required int offset,
    required String sortField,
    required bool sortDesc,
    String? groupName,
    String? subGroup,
    String? altGroup,
    String? marketerName,
    String? search,
  }) async {
    final result = await _client.rpc(
      'rpc_admin_customer_balance_page',
      params: <String, dynamic>{
        'p_min_abs_net': minAbsNet,
        'p_status': status,
        'p_group_name': groupName,
        'p_sub_group': subGroup,
        'p_alt_group': altGroup,
        'p_marketer_name': marketerName,
        'p_search': search,
        'p_sort_field': sortField,
        'p_sort_desc': sortDesc,
        'p_limit': limit,
        'p_offset': offset,
      },
    );

    if (result is! List) {
      return const <BalanceReportRowDto>[];
    }

    return result
        .map((e) => BalanceReportRowDto.fromMap(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList(growable: false);
  }

  Future<RiskSnapshotDto> fetchRiskSnapshot(BalanceReportNormalizedFilters f) async {
    final raw = await _client.rpc(
      'rpc_admin_customer_risk_snapshot',
      params: <String, dynamic>{
        'p_min_abs_net': f.minAbsNet,
        'p_status': f.status,
        'p_group_name': f.groupName,
        'p_sub_group': f.subGroup,
        'p_alt_group': f.altGroup,
        'p_marketer_name': f.marketerName,
        'p_search': f.search,
      },
    );

    return _parseRiskSnapshot(raw);
  }

  Future<AgingSnapshotDto> fetchRiskAgingSnapshot(
    BalanceReportNormalizedFilters f,
  ) async {
    final raw = await _client.rpc(
      'rpc_admin_customer_aging_snapshot',
      params: <String, dynamic>{
        'p_group_name': f.groupName,
        'p_sub_group': f.subGroup,
        'p_alt_group': f.altGroup,
        'p_marketer_name': f.marketerName,
        'p_search': f.search,
      },
    );

    return _parseAgingSnapshot(raw);
  }

  Future<List<RiskScoreRowDto>> fetchRiskScoredTop({
    required int limit,
    required int offset,
  }) async {
    final result = await _client.rpc(
      'rpc_admin_customer_risk_scored_top',
      params: <String, dynamic>{
        'p_limit': limit,
        'p_offset': offset,
      },
    );

    if (result is! List) {
      return const <RiskScoreRowDto>[];
    }

    return result
        .map((e) => RiskScoreRowDto.fromMap(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList(growable: false);
  }

  Future<List<RiskTopRowDto>> fetchRiskTop(
    BalanceReportNormalizedFilters f, {
    int limit = 25,
    int offset = 0,
    String sortField = 'limit_usage_percent',
    bool sortDesc = true,
  }) async {
    final result = await _client.rpc(
      'rpc_admin_customer_risk_top',
      params: <String, dynamic>{
        'p_min_abs_net': f.minAbsNet,
        'p_status': f.status,
        'p_group_name': f.groupName,
        'p_sub_group': f.subGroup,
        'p_alt_group': f.altGroup,
        'p_marketer_name': f.marketerName,
        'p_search': f.search,
        'p_limit': limit,
        'p_offset': offset,
        'p_sort_field': sortField,
        'p_sort_desc': sortDesc,
      },
    );

    if (result is! List) {
      return const <RiskTopRowDto>[];
    }

    return result
        .map((e) => RiskTopRowDto.fromMap(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList(growable: false);
  }

  Future<void> bulkDeactivateCustomers({
    required List<String> customerIds,
  }) async {
    if (customerIds.isEmpty) return;

    await _client
        .from('customers')
        .update(<String, dynamic>{'is_active': false})
        .inFilter('id', customerIds);
  }

  Future<void> bulkUpdateLimitAmount({
    required List<String> customerIds,
    required double limitAmount,
  }) async {
    if (customerIds.isEmpty) return;

    final payload = customerIds
        .map((id) => <String, dynamic>{
              'customer_id': id,
              'limit_amount': limitAmount,
            })
        .toList(growable: false);

    await _client.from('customer_details').upsert(
          payload,
          onConflict: 'customer_id',
        );
  }
}

final adminCustomerReportsRepository = AdminCustomerReportsRepository();
