import 'package:core/core.dart';

import 'dashboard_summary.dart';

class CustomerDashboardRepository {
  const CustomerDashboardRepository();

  Future<DashboardSummary> fetchSummary({required String customerId}) async {
    if (customerId.trim().isEmpty) return DashboardSummary.empty;

    DashboardSummary base = DashboardSummary.empty;

    // Özet alanları için mevcut kaynakları kullan.
    // Not: Bakiye kesin olarak v_customer_balance.net üzerinden override edilecek.
    try {
      final dynamic data = await supabaseClient.rpc('customer_dashboard_summary');

      if (data is Map<String, dynamic>) {
        base = DashboardSummary.fromMap(data);
      } else if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map<String, dynamic>) {
          base = DashboardSummary.fromMap(first);
        }
      }
    } catch (_) {
      // RPC tanımlı değilse view üzerinden tek satır dene.
      try {
        final dynamic rows = await supabaseClient
            .from('v_customer_dashboard_summary')
            .select()
            .limit(1);

        if (rows is List && rows.isNotEmpty) {
          final first = rows.first;
          if (first is Map<String, dynamic>) {
            base = DashboardSummary.fromMap(first);
          }
        }
      } catch (_) {
        // Backend henüz hazır değilse; UI error state bunu yakalayacak.
        rethrow;
      }
    }

    final balanceNet = await customerBalanceRepository.getCustomerBalance(
      customerId,
    );

    return DashboardSummary(
      balance: balanceNet,
      openOrdersCount: base.openOrdersCount,
      lastOrderDate: base.lastOrderDate,
      lastOrderTotal: base.lastOrderTotal,
      riskLimit: base.riskLimit,
      dueDays: base.dueDays,
      lastOrderAt: base.lastOrderAt,
    );
  }
}

const customerDashboardRepository = CustomerDashboardRepository();
