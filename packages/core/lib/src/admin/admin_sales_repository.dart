import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';

class AdminSaleListEntry {
  const AdminSaleListEntry({
    required this.id,
    required this.createdAt,
    required this.totalAmount,
    required this.customerName,
    this.batchId,
    this.note,
  });

  final String id;
  final DateTime createdAt;
  final double totalAmount;
  final String customerName;
  final String? batchId;
  final String? note;
}

class AdminSalesRepository {
  AdminSalesRepository(this._client);

  final SupabaseClient _client;

  Future<List<AdminSaleListEntry>> fetchSales({String? batchId}) async {
    var query = _client
        .from('sales')
        .select('id, customer_id, total_amount, created_at, batch_id, note');

    if (batchId != null && batchId.isNotEmpty) {
      // Hem batch_id kolonunu hem de BATCH:<id> formatındaki not alanını
      // destekle (backend tarafındaki uygulamaya göre esnek bırakılır).
      query = query.or('batch_id.eq.$batchId,note.eq.BATCH:$batchId');
    }

    final dynamic data = await query.order('created_at', ascending: false);

    final rawSales = (data as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (rawSales.isEmpty) {
      return const <AdminSaleListEntry>[];
    }

    final customerIds = rawSales
      .map((e) => e['customer_id'] as String?)
      .whereType<String>()
      .toSet()
      .toList();

    Map<String, String> customerNamesById = <String, String>{};
    if (customerIds.isNotEmpty) {
      final dynamic customerData = await _client
        .from('customers')
        .select('id, trade_title, full_name')
        .inFilter('id', customerIds);

      final customers = (customerData as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

      for (final row in customers) {
      final id = row['id'] as String?;
        if (id == null) continue;
        final tradeTitle = row['trade_title'] as String?;
        final fullName = row['full_name'] as String?;
        final name = (tradeTitle != null && tradeTitle.isNotEmpty)
            ? tradeTitle
            : (fullName ?? 'Bilinmeyen Cari');
        customerNamesById[id] = name;
      }
    }

    return rawSales.map((row) {
      final id = row['id'] as String;
      final customerId = row['customer_id'] as String?;
      final totalAmount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      final createdAtRaw = row['created_at'];
      final createdAt = createdAtRaw is String
          ? DateTime.parse(createdAtRaw)
          : createdAtRaw is DateTime
              ? createdAtRaw
              : DateTime.now();
        final batchIdValue = row['batch_id']?.toString();
      final note = row['note'] as String?;

      final customerName = customerId != null
          ? (customerNamesById[customerId] ?? 'Bilinmeyen Cari')
          : 'Bilinmeyen Cari';

      return AdminSaleListEntry(
        id: id,
        createdAt: createdAt,
        totalAmount: totalAmount,
        customerName: customerName,
        batchId: batchIdValue,
        note: note,
      );
    }).toList();
  }
}

final adminSalesRepository = AdminSalesRepository(supabaseClient);
