class DashboardSummary {
  const DashboardSummary({
    required this.balance,
    required this.openOrdersCount,
    this.lastOrderDate,
    this.lastOrderTotal,
    required this.riskLimit,
    required this.dueDays,
    this.lastOrderAt,
  });

  final double balance;
  final int openOrdersCount;
  final DateTime? lastOrderDate;
  final double? lastOrderTotal;
  final double riskLimit;
  final int dueDays;
  final DateTime? lastOrderAt;

  factory DashboardSummary.fromMap(Map<String, dynamic> map) {
    final balanceRaw = map['balance'];
    final openOrdersRaw = map['open_orders_count'];
    final lastDateRaw = map['last_order_date'];
    final lastTotalRaw = map['last_order_total'];
    final riskLimitRaw = map['risk_limit'];
    final dueDaysRaw = map['due_days'];

    DateTime? parseDate(dynamic raw) {
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw);
      }
      if (raw is DateTime) {
        return raw;
      }
      return null;
    }

    final parsedLastDate =
      parseDate(lastDateRaw) ?? parseDate(map['last_order_at']);

    return DashboardSummary(
      balance: (balanceRaw as num?)?.toDouble() ?? 0,
      openOrdersCount: (openOrdersRaw as num?)?.toInt() ?? 0,
      lastOrderDate: parsedLastDate,
      lastOrderTotal: (lastTotalRaw as num?)?.toDouble(),
      riskLimit: (riskLimitRaw as num?)?.toDouble() ?? 0,
      dueDays: (dueDaysRaw as num?)?.toInt() ?? 0,
      lastOrderAt: parsedLastDate,
    );
  }

  static const empty = DashboardSummary(
    balance: 0,
    openOrdersCount: 0,
    lastOrderDate: null,
    lastOrderTotal: null,
    riskLimit: 0,
    dueDays: 0,
    lastOrderAt: null,
  );
}
