import 'package:core/core.dart' show supabaseClient;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const int _shipmentPageSize = 20;

typedef ShipmentListQuery = ({
  String? search,
  DateTime? dateFrom,
  DateTime? dateTo,
  int page,
});

typedef ShipmentCountQuery = ({
  String? search,
  DateTime? dateFrom,
  DateTime? dateTo,
});

class AdminShipmentListRow {
  const AdminShipmentListRow({
    required this.id,
    required this.orderNo,
    required this.createdAt,
    required this.status,
    required this.totalAmount,
    required this.customerId,
    required this.customerName,
    required this.city,
    required this.invoiced,
  });

  final String id;
  final int? orderNo;
  final DateTime createdAt;
  final String status;
  final double totalAmount;
  final String? customerId;
  final String customerName;
  final String? city;
  final bool invoiced;

  static DateTime _parseDate(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.parse(v);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static double _parseDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
    }
    return false;
  }

  factory AdminShipmentListRow.fromMap(Map<String, dynamic> map) {
    final id = (map['id'] as String?) ?? '';
    final rawOrderNo = map['order_no'];
    final int? orderNo = rawOrderNo is num
        ? rawOrderNo.toInt()
        : rawOrderNo is String
            ? int.tryParse(rawOrderNo)
            : null;

    final createdAt = _parseDate(map['created_at']);
    final status = (map['status'] as String?) ?? '';
    final totalAmount = _parseDouble(map['total_amount']);
    final customerId = map['customer_id'] as String?;
    final customerName = (map['customer_name'] as String?)?.trim().isNotEmpty ==
            true
        ? (map['customer_name'] as String).trim()
        : 'Cari';
    final city = (map['city'] as String?)?.trim();
    final invoiced = _parseBool(map['invoiced']);

    return AdminShipmentListRow(
      id: id,
      orderNo: orderNo,
      createdAt: createdAt,
      status: status,
      totalAmount: totalAmount,
      customerId: customerId,
      customerName: customerName,
      city: city,
      invoiced: invoiced,
    );
  }
}

String? _normalizeSearch(String? value) {
  final v = value?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

final shipmentListProvider = FutureProvider.autoDispose
    .family<List<AdminShipmentListRow>, ShipmentListQuery>((ref, q) async {
  final search = _normalizeSearch(q.search);
  final dateFrom = q.dateFrom;
  final dateTo = q.dateTo;
  final page = q.page;

  final params = <String, dynamic>{
    'p_search': search,
    'p_date_from': dateFrom?.toIso8601String(),
    'p_date_to': dateTo?.toIso8601String(),
    'p_limit': _shipmentPageSize,
    'p_offset': page * _shipmentPageSize,
  };

  if (kDebugMode) {
    debugPrint('[ADMIN][ShipmentList] rpc_admin_shipment_list params=$params');
  }

  final result = await supabaseClient.rpc(
    'rpc_admin_shipment_list',
    params: params,
  );

  if (result is! List) {
    return const <AdminShipmentListRow>[];
  }

  return result
      .map((e) => AdminShipmentListRow.fromMap(
            Map<String, dynamic>.from(e as Map),
          ))
      .toList(growable: false);
});

final shipmentListCountProvider = FutureProvider.autoDispose
    .family<int, ShipmentCountQuery>((ref, q) async {
  final search = _normalizeSearch(q.search);
  final dateFrom = q.dateFrom;
  final dateTo = q.dateTo;

  final params = <String, dynamic>{
    'p_search': search,
    'p_date_from': dateFrom?.toIso8601String(),
    'p_date_to': dateTo?.toIso8601String(),
  };

  final result = await supabaseClient.rpc(
    'rpc_admin_shipment_list_count',
    params: params,
  );

  if (result is int) return result;
  if (result is num) return result.toInt();
  if (result is String) return int.tryParse(result) ?? 0;
  return 0;
});

/// Spec-friendly alias used by UI.
final shipmentCountProvider = shipmentListCountProvider;
