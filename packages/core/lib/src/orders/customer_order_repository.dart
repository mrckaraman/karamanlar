import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';

class CustomerOrderItemDraft {
  const CustomerOrderItemDraft({
    required this.stockId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
  });

  final String stockId;
  final String name;
  final String unit;
  final double quantity;
  final double unitPrice;

  double get lineTotal => quantity * unitPrice;
}

class CustomerOrderDetail {
  const CustomerOrderDetail({
    required this.id,
    required this.status,
    required this.totalAmount,
    required this.createdAt,
    required this.orderNo,
    required this.note,
  });

  final String id;
  final String status;
  final double totalAmount;
  final DateTime createdAt;
  final String? orderNo;
  final String? note;

  factory CustomerOrderDetail.fromMap(Map<String, dynamic> map) {
    final totalRaw = map['total_amount'];
    double total = 0;
    if (totalRaw is num) {
      total = totalRaw.toDouble();
    } else if (totalRaw is String) {
      total = num.tryParse(totalRaw)?.toDouble() ?? 0;
    }

    String _safeString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      return value.toString();
    }

    String? _safeNullableString(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      return value.toString();
    }

    final createdRaw = map['created_at'];
    final DateTime createdAt;
    if (createdRaw is String) {
      createdAt = DateTime.parse(createdRaw);
    } else if (createdRaw is DateTime) {
      createdAt = createdRaw;
    } else {
      createdAt = DateTime.now();
    }

    return CustomerOrderDetail(
      id: _safeString(map['id']),
      status: _safeString(map['status']),
      totalAmount: total,
      createdAt: createdAt,
      orderNo: _safeNullableString(map['order_no']),
      note: _safeNullableString(map['note']),
    );
  }
}

class CustomerOrderItem {
  const CustomerOrderItem({
    required this.name,
    required this.quantity,
    required this.unitName,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String name;
  final double quantity;
  final String unitName;
  final double unitPrice;
  final double lineTotal;

  factory CustomerOrderItem.fromMap(Map<String, dynamic> map) {
    final qtyRaw = map['qty'];
    double qty = 0;
    if (qtyRaw is num) {
      qty = qtyRaw.toDouble();
    } else if (qtyRaw is String) {
      qty = num.tryParse(qtyRaw)?.toDouble() ?? 0;
    }

    final unitName = (map['unit_name'] as String?)?.trim() ?? '';

    double unitPrice = 0;
    final unitPriceRaw = map['unit_price'];
    if (unitPriceRaw is num) {
      unitPrice = unitPriceRaw.toDouble();
    } else if (unitPriceRaw is String) {
      unitPrice = num.tryParse(unitPriceRaw)?.toDouble() ?? 0;
    }

    double lineTotal = 0;
    final lineTotalRaw = map['line_total'];
    if (lineTotalRaw is num) {
      lineTotal = lineTotalRaw.toDouble();
    } else if (lineTotalRaw is String) {
      lineTotal = num.tryParse(lineTotalRaw)?.toDouble() ?? 0;
    }

    return CustomerOrderItem(
      name: (map['name'] as String?) ?? '',
      quantity: qty,
      unitName: unitName,
      unitPrice: unitPrice,
      lineTotal: lineTotal,
    );
  }
}

class CustomerOrderRepository {
  const CustomerOrderRepository(this._client);

  final SupabaseClient _client;

  /// Sepet içeriğinden sipariş oluşturur.
  ///
  /// Akış:
  ///  * orders tablosuna status = 'new' ile insert (customer_id ve total_amount
  ///    DB tarafındaki trigger / policy tarafından atanır)
  ///  * order_items tablosuna kalemleri bulk insert
  ///  * herhangi bir adımda hata olursa oluşturulan order kaydını silmeye çalışır
  Future<String> createOrderFromCart({
    required List<CustomerOrderItemDraft> items,
    String? note,
  }) async {
    if (items.isEmpty) {
      throw Exception('Sepet boş. Lütfen önce ürün ekleyin.');
    }

    String? orderId;

    try {
      final dynamic orderInsert = await guardPostgrest(
        'orders.createOrderFromCart.insert note=${note ?? ''}',
        () => _client
            .from('orders')
            .insert(<String, dynamic>{
              'status': 'new',
              'note': note,
              // Toplam tutar DB tarafinda trigger ile hesaplanir.
              'total_amount': 0,
            })
            .select('id, customer_id, total_amount')
            .maybeSingle(),
      );

      if (orderInsert == null) {
        throw Exception('Sepet oluşturulamadı. Sipariş kaydı oluşturulamadı.');
      }

      if (orderInsert is! Map<String, dynamic>) {
        throw Exception('Sipariş oluşturulamadı: beklenmeyen yanıt.');
      }

      orderId = orderInsert['id'] as String?;
      if (orderId == null || orderId.isEmpty) {
        throw Exception('Sipariş oluşturulamadı: sipariş ID alınamadı.');
      }

      final itemsPayload = items
          .map((item) => <String, dynamic>{
                'order_id': orderId,
                'stock_id': item.stockId,
                'name': item.name,
                'qty': item.quantity,
                'unit_name': item.unit,
                'unit_price': item.unitPrice,
                'line_total': item.lineTotal,
              })
          .toList();

      await guardPostgrest(
        'order_items.insert count=${itemsPayload.length}',
        () => _client.from('order_items').insert(itemsPayload),
      );

      return orderId;
    } on PostgrestException catch (e) {
      // Hata durumunda oluşturulan siparişi geri almaya çalış.
      if (orderId != null && orderId.isNotEmpty) {
        try {
          await _client.from('orders').delete().eq('id', orderId);
        } catch (_) {
          // Rollback denemesi başarısız olsa bile asıl hatayı fırlat.
        }
      }
      // PostgrestException mesajini dogrudan UI'a iletmek icin
      // sadecce message alanini tasiyan bir Exception firlat.
      throw Exception(e.message);
    } catch (e) {
      if (orderId != null && orderId.isNotEmpty) {
        try {
          await _client.from('orders').delete().eq('id', orderId);
        } catch (_) {
          // Rollback denemesi başarısız olsa bile asıl hatayı fırlat.
        }
      }
      rethrow;
    }
  }

  Future<CustomerOrderDetail> fetchCustomerOrderDetail(
    String orderId,
  ) async {
    final dynamic data = await guardPostgrest(
      'orders.fetchCustomerOrderDetail id=$orderId',
      () => _client
          .from('orders')
          .select('id, status, total_amount, created_at, order_no, note')
          .eq('id', orderId)
          .single(),
    );

    if (data is! Map<String, dynamic>) {
      throw Exception('Sipariş detayı alınamadı: beklenmeyen yanıt.');
    }

    return CustomerOrderDetail.fromMap(data);
  }

  Future<List<CustomerOrderItem>> fetchCustomerOrderItems(
    String orderId,
  ) async {
    final dynamic data = await guardPostgrest(
      'order_items.fetchCustomerOrderItems id=$orderId',
      () => _client
          .from('order_items')
          .select(
            'name, qty, unit_name, unit_price, line_total, created_at',
          )
          .eq('order_id', orderId)
          .order('created_at', ascending: true),
    );

    if (data is! List) {
      throw Exception('Sipariş kalemleri alınamadı: beklenmeyen yanıt.');
    }

    return data
        .map((row) => CustomerOrderItem.fromMap(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList(growable: false);
  }
}

final customerOrderRepository = CustomerOrderRepository(supabaseClient);
