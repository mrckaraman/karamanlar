import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';

class AdminMetricsRepository {
  AdminMetricsRepository(this._client);

  final SupabaseClient _client;

  Future<int> getActiveStockCount() async {
    final data = await _client
      .from('stocks')
    .select('id')
    .eq('is_active', true);
    return (data as List<dynamic>).length;
  }

  Future<int> getCustomerCount() async {
    final data = await _client.from('v_customers').select('id');
    return (data as List<dynamic>).length;
  }

  Future<int> getTodaySalesCount() async {
    final now = DateTime.now();
    final startLocal = DateTime(now.year, now.month, now.day);
    final endLocal = startLocal.add(const Duration(days: 1));

    final startUtcIso = startLocal.toUtc().toIso8601String();
    final endUtcIso = endLocal.toUtc().toIso8601String();

    // Not: Projede satış, siparişin 'completed' olmasıyla oluşan fatura (invoices)
    // üzerinden takip ediliyor. Bu yüzden satış adedini, bugün kesilen faturalar
    // üzerinden sayıyoruz.
    try {
      final data = await _client
          .from('invoices')
          .select('id')
          .eq('status', 'issued')
          .gte('issued_at', startUtcIso)
          .lt('issued_at', endUtcIso);
      return (data as List<dynamic>).length;
    } catch (_) {
      // Fatura okuma yetkisi yoksa / tablo farklıysa: en azından completed
      // siparişleri saymaya çalış.
      try {
        final data = await _client
            .from('orders')
            .select('id')
            .eq('status', 'completed')
            .gte('created_at', startUtcIso)
            .lt('created_at', endUtcIso);
        return (data as List<dynamic>).length;
      } catch (_) {
        return 0;
      }
    }
  }

  Future<int> getOpenOrderCount({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final now = DateTime.now();
      final DateTime start;
      final DateTime end;

      if (startDate != null && endDate != null) {
        start = startDate;
        end = endDate;
      } else {
        // Dashboard'ta tarih filtresi yoksa: bugünkü açık siparişler.
        start = DateTime(now.year, now.month, now.day);
        end = start.add(const Duration(days: 1));
      }

      final openStatuses = <String>[
        'new',
        'approved',
        'preparing',
        'shipped',
      ];

      final data = await _client
          .from('orders')
          .select('id')
          .inFilter('status', openStatuses)
          .gte('created_at', start.toUtc().toIso8601String())
          .lt('created_at', end.toUtc().toIso8601String());

      return (data as List<dynamic>).length;
    } catch (_) {
      // Tablo veya kolon hatası durumunda metrik grafikleri kırmamak için 0 dön.
      return 0;
    }
  }
}

final adminMetricsRepository = AdminMetricsRepository(supabaseClient);
