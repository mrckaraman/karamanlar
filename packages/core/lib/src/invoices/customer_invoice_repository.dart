import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';

class CustomerInvoiceListEntry {
  const CustomerInvoiceListEntry({
    required this.id,
    required this.invoiceNo,
    required this.issuedAt,
    required this.totalAmount,
    required this.paidAmount,
    required this.status,
    required this.orderId,
  });

  final String id;
  final String invoiceNo;
  final DateTime issuedAt;
  final double totalAmount;
  final double paidAmount;
  final String status;
  final String? orderId;

  double get remaining =>
      (totalAmount - paidAmount).clamp(0, double.infinity).toDouble();

  factory CustomerInvoiceListEntry.fromMap(Map<String, dynamic> map) {
    String _string(dynamic value) =>
        value == null ? '' : (value is String ? value : value.toString());

    double _double(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      if (value is String) {
        return num.tryParse(value)?.toDouble() ?? 0;
      }
      return 0;
    }

    DateTime _date(dynamic value) {
      if (value is DateTime) return value;
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    final id = _string(map['id']);
    final invoiceNo = _string(map['invoice_no']);

    final issuedAt = _date(
      map['invoice_date'] ?? map['issued_at'] ?? map['created_at'],
    );

    final totalAmount = _double(map['total_amount']);
    final paidAmount = _double(map['paid_amount']);
    final status = _string(map['status']);
    final String? orderId = map['order_id'] == null
        ? null
        : _string(map['order_id']);

    return CustomerInvoiceListEntry(
      id: id,
      invoiceNo: invoiceNo,
      issuedAt: issuedAt,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      status: status,
      orderId: orderId,
    );
  }
}

class CustomerInvoiceRepository {
  const CustomerInvoiceRepository(this._client);

  final SupabaseClient _client;

  Future<List<CustomerInvoiceListEntry>> fetchCustomerInvoices({
    required String customerId,
    String? search,
    List<String>? statuses,
    int limit = 50,
  }) async {
    if (customerId.isEmpty) return <CustomerInvoiceListEntry>[];

    const selectColumns =
        'id, invoice_no, invoice_date, issued_at, created_at, total_amount, paid_amount, status, order_id, customer_id';

    dynamic query = _client
        .from('invoices')
        .select(selectColumns)
      .eq('customer_id', customerId)
      .neq('status', 'cancelled');

    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    }

    if (search != null && search.trim().isNotEmpty) {
      final value = search.trim();
      query = query.ilike('invoice_no', '%$value%');
    }

    query = query
    .order('invoice_date', ascending: false)
    .order('issued_at', ascending: false)
    .order('created_at', ascending: false)
    .limit(limit);

    try {
      final dynamic data = await guardPostgrest(
        '[CUSTOMER][Invoices] fetchCustomerInvoices customerId=$customerId',
        () => query,
      );

      if (data is! List) {
        debugPrint('[CUSTOMER][Invoices] unexpected response: $data');
        return <CustomerInvoiceListEntry>[];
      }

      return data
          .map((e) => CustomerInvoiceListEntry.fromMap(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][CUSTOMER][Invoices] code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }
  }
}

final customerInvoiceRepository = CustomerInvoiceRepository(supabaseClient);
