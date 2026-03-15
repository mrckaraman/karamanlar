import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';

class AdminOrderListEntry {
  const AdminOrderListEntry({
    required this.id,
    required this.createdAt,
    required this.status,
    required this.totalAmount,
    required this.customerName,
    required this.customerId,
    this.orderNo,
    this.note,
    this.customerPhone,
    this.customerCode,
  });

  final String id;
  final DateTime createdAt;
  final String status;
  final double totalAmount;
  final String customerName;
  final String? customerId;
  final int? orderNo;
  final String? note;

  /// customers.phone (best-effort).
  final String? customerPhone;

  /// customers.customer_code (best-effort).
  final String? customerCode;
}

class AdminOrderItemEntry {
  const AdminOrderItemEntry({
    required this.id,
    required this.stockId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String id;
  final String stockId;
  final String name;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
}

class AdminCustomerProductSaleHistoryEntry {
  const AdminCustomerProductSaleHistoryEntry({
    required this.orderId,
    required this.orderCreatedAt,
    required this.orderStatus,
    required this.qty,
    required this.unitName,
    required this.unitPrice,
    required this.lineTotal,
    this.orderNo,
  });

  final String orderId;
  final DateTime orderCreatedAt;
  final String orderStatus;
  final int? orderNo;

  final double qty;
  final String unitName;
  final double unitPrice;
  final double lineTotal;
}

class AdminOrderItemDraft {
  const AdminOrderItemDraft({
    required this.stockId,
    required this.name,
    required this.unitName,
    required this.quantity,
    required this.unitPrice,
    this.multiplier = 1,
  });

  final String stockId;
  final String name;
  final String unitName;

  /// Kullanıcının seçtiği birimde girdiği miktar (örn. 2 paket).
  final double quantity;

  /// Baz birim fiyatı (adet fiyatı).
  final double unitPrice;

  /// Seçilen birimin baz birime çarpanı (adet=1, paket=12, koli=24 gibi).
  final double multiplier;

  double get realQuantity => quantity * (multiplier <= 0 ? 1 : multiplier);

  double get shownUnitPrice => unitPrice * (multiplier <= 0 ? 1 : multiplier);

  double get lineTotal => realQuantity * unitPrice;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'stock_id': stockId,
      // RPC tarafında gerçek stok düşümü baz birim üzerinden yapılır.
      'qty': realQuantity,
      'unit_name': unitName,
      // unit_price her zaman baz birim fiyatıdır.
      'unit_price': unitPrice,
    };
  }
}

class AdminUnitOption {
  const AdminUnitOption({
    required this.code,
    required this.name,
    required this.multiplier,
    required this.isDefault,
  });

  /// 'piece' | 'pack' | 'box' | 'carton'
  final String code;
  final String name;
  final double multiplier;
  final bool isDefault;
}

class AdminOrderDetail {
  const AdminOrderDetail({
    required this.id,
    required this.customerName,
    required this.status,
    required this.note,
    required this.totalAmount,
    required this.createdAt,
    required this.items,
    this.orderNo,
    this.customerId,
  });

  final String id;
  final String customerName;
  final String status;
  final String? note;
  final double totalAmount;
  final DateTime createdAt;
  final List<AdminOrderItemEntry> items;
  final int? orderNo;

  /// İlişkili cari (orders.customer_id). Bazı eski kayıtlarda null olabilir.
  final String? customerId;
}

class AdminOrderRepository {
  AdminOrderRepository(this._client);

  final SupabaseClient _client;

  /// Bir cari için, belirli bir ürünün (stock_id) geçmiş satış/sipariş
  /// kalemlerini döndürür.
  ///
  /// Not: Projede satışın kesinleşmiş hali genellikle siparişin
  /// `completed` / `invoiced` statüsüne gelmesiyle oluşur.
  Future<List<AdminCustomerProductSaleHistoryEntry>>
      fetchCustomerProductSaleHistory({
    required String customerId,
    required String stockId,
    int limit = 20,
  }) async {
    final trimmedCustomerId = customerId.trim();
    final trimmedStockId = stockId.trim();
    if (trimmedCustomerId.isEmpty) {
      throw ArgumentError('customerId boş olamaz');
    }
    if (trimmedStockId.isEmpty) {
      throw ArgumentError('stockId boş olamaz');
    }

    final effectiveLimit = (limit <= 0) ? 20 : limit;

    const select =
        'id, order_id, qty, unit_name, unit_price, line_total, orders!inner(id, customer_id, status, created_at, order_no)';

    try {
      final statuses = <String>['completed', 'invoiced'];
      final dynamic data = await _client
          .from('order_items')
          .select(select)
          .eq('stock_id', trimmedStockId)
          .eq('orders.customer_id', trimmedCustomerId)
        .inFilter('orders.status', statuses)
        .order('created_at', referencedTable: 'orders', ascending: false)
        .limit(effectiveLimit);

      final rows = (data as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final entries = <AdminCustomerProductSaleHistoryEntry>[];

      DateTime _parseDateTime(dynamic value) {
        if (value == null) return DateTime.now();
        if (value is DateTime) return value;
        if (value is String && value.trim().isNotEmpty) {
          return DateTime.tryParse(value.trim()) ?? DateTime.now();
        }
        return DateTime.now();
      }

      for (final row in rows) {
        final order = row['orders'];
        if (order is! Map) continue;
        final orderMap = Map<String, dynamic>.from(order);

        final orderId = (row['order_id'] as String?) ??
            (orderMap['id'] as String?) ??
            '';
        if (orderId.trim().isEmpty) continue;

        final status = (orderMap['status'] as String?) ?? '';
        final createdAt = _parseDateTime(orderMap['created_at']);

        int? orderNo;
        final orderNoRaw = orderMap['order_no'];
        if (orderNoRaw is int) {
          orderNo = orderNoRaw;
        } else if (orderNoRaw is num) {
          orderNo = orderNoRaw.toInt();
        } else if (orderNoRaw is String && orderNoRaw.trim().isNotEmpty) {
          orderNo = int.tryParse(orderNoRaw.trim());
        }

        final qty = (row['qty'] as num?)?.toDouble() ?? 0;
        final unitName = (row['unit_name'] as String?) ?? '';
        final unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0;
        final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;

        entries.add(
          AdminCustomerProductSaleHistoryEntry(
            orderId: orderId,
            orderCreatedAt: createdAt,
            orderStatus: status,
            orderNo: orderNo,
            qty: qty,
            unitName: unitName,
            unitPrice: unitPrice,
            lineTotal: lineTotal,
          ),
        );
      }

      entries.sort((a, b) => b.orderCreatedAt.compareTo(a.orderCreatedAt));

      if (entries.length <= effectiveLimit) return entries;
      return entries.take(effectiveLimit).toList(growable: false);
    } on PostgrestException catch (e, st) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][OrderSaleHistory] customerId=$trimmedCustomerId stockId=$trimmedStockId code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  Future<({String orderId, int orderNo})> createOrderWithItemsRpc({
    required String customerId,
    required String? note,
    required List<AdminOrderItemDraft> items,
  }) async {
    final trimmedCustomerId = customerId.trim();
    if (trimmedCustomerId.isEmpty) {
      throw ArgumentError('customerId boş olamaz');
    }
    if (items.isEmpty) {
      throw ArgumentError('items boş olamaz');
    }

    final params = <String, dynamic>{
      'p_customer_id': trimmedCustomerId,
      'p_note': note,
      'p_items': items.map((e) => e.toJson()).toList(growable: false),
    };

    if (kDebugMode) {
      debugPrint(
        '[ADMIN][OrderCreateRPC] call rpc=rpc_admin_create_order_with_items '
        'customerId=$trimmedCustomerId noteLen=${note?.length ?? 0} items=${items.length}',
      );
      debugPrint(
        '[ADMIN][OrderCreateRPC] firstItem=${items.first.toJson()}',
      );
    }

    try {
      final dynamic res = await _client.rpc(
        'rpc_admin_create_order_with_items',
        params: params,
      );

      if (kDebugMode) {
        debugPrint(
          '[ADMIN][OrderCreateRPC] responseType=${res.runtimeType}',
        );
        if (res is List) {
          debugPrint('[ADMIN][OrderCreateRPC] responseLen=${res.length}');
          if (res.isNotEmpty) {
            debugPrint('[ADMIN][OrderCreateRPC] responseFirst=${res.first}');
          }
        }
      }

      if (res is! List || res.isEmpty) {
        throw Exception('RPC boş sonuç döndü.');
      }

      final first = res.first;
      if (first is! Map) {
        throw Exception('Beklenmeyen RPC dönüş tipi: ${first.runtimeType}');
      }

      final map = Map<String, dynamic>.from(first);
      final orderId = map['order_id'] as String?;
      final orderNoRaw = map['order_no'];

      if (orderId == null || orderId.trim().isEmpty) {
        throw Exception('RPC sonucu içinde order_id bulunamadı.');
      }

      int? orderNo;
      if (orderNoRaw is int) {
        orderNo = orderNoRaw;
      } else if (orderNoRaw is num) {
        orderNo = orderNoRaw.toInt();
      } else if (orderNoRaw is String && orderNoRaw.trim().isNotEmpty) {
        orderNo = int.tryParse(orderNoRaw.trim());
      }

      if (orderNo == null || orderNo <= 0) {
        throw Exception('RPC sonucu içinde order_no bulunamadı.');
      }

      return (orderId: orderId, orderNo: orderNo);
    } on PostgrestException catch (e, st) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][OrderCreateRPC] code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  /// Admin panelinden yeni sipariş oluşturur.
  ///
  /// Akış:
  ///  * orders tablosuna status='new' + customer_id ile insert
  ///  * order_items tablosuna kalemleri bulk insert
  ///  * herhangi bir adımda hata olursa oluşturulan order kaydını silmeye çalışır
  Future<String> createOrderWithItems({
    required String customerId,
    required List<AdminOrderItemDraft> items,
    String? note,
  }) async {
    if (customerId.trim().isEmpty) {
      throw Exception('Cari seçilmedi. Lütfen önce cari seçin.');
    }

    if (items.isEmpty) {
      throw Exception('Sepet boş. Lütfen önce ürün ekleyin.');
    }

    String? orderId;

    try {
      final dynamic orderInsert = await guardPostgrest(
        'admin.orders.createOrderWithItems.insert customerId=$customerId note=${note ?? ''}',
        () => _client
            .from('orders')
            .insert(<String, dynamic>{
              'customer_id': customerId,
              'status': 'new',
              'note': note,
              // Toplam tutar DB tarafinda trigger/RPC ile hesaplanir.
              'total_amount': 0,
            })
            .select('id')
            .maybeSingle(),
      );

      if (orderInsert == null) {
        throw Exception('Sipariş oluşturulamadı. Sipariş kaydı oluşturulamadı.');
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
                'unit_name': item.unitName,
                'unit_price': item.unitPrice,
                'line_total': item.lineTotal,
              })
          .toList(growable: false);

      await guardPostgrest(
        'admin.order_items.insert count=${itemsPayload.length}',
        () => _client.from('order_items').insert(itemsPayload),
      );

      // Opsiyonel: total hesaplamasını force et (RPC varsa).
      try {
        await _client.rpc(
          'recalc_order_total',
          params: <String, dynamic>{'p_order_id': orderId},
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ADMIN][OrderCreate] recalc_order_total skipped: $e');
        }
      }

      return orderId;
    } on PostgrestException catch (e) {
      if (orderId != null && orderId.isNotEmpty) {
        try {
          await _client.from('orders').delete().eq('id', orderId);
        } catch (_) {
          // Rollback denemesi başarısız olsa bile asıl hatayı fırlat.
        }
      }
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

  Future<List<AdminOrderListEntry>> fetchOrders({
    String status = 'new',
    List<String>? statuses,
    int? limit,
    int? offset,
  }) async {
    dynamic query = _client.from('orders').select(
          'id, customer_id, status, total_amount, created_at, order_no, note',
        );

    // Çoklu durum filtresi önceliklidir.
    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    } else if (status.isNotEmpty && status != 'all') {
      // Eski tekli status davranışı korunur.
      query = query.eq('status', status);
    }

    if (limit != null) {
      final start = offset ?? 0;
      final end = start + limit - 1;
      query = query.range(start, end);
    }

    final dynamic data = await query.order('created_at', ascending: false);

    final rawOrders = (data as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (rawOrders.isEmpty) {
      return const <AdminOrderListEntry>[];
    }

    final customerIds = rawOrders
        .map((e) => e['customer_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    Map<String, String> customerNamesById = <String, String>{};
    Map<String, String?> customerPhonesById = <String, String?>{};
    Map<String, String?> customerCodesById = <String, String?>{};
    if (customerIds.isNotEmpty) {
      final dynamic customerData = await _client
          .from('customers')
        .select('id, trade_title, full_name, phone, customer_code')
          .inFilter('id', customerIds);

      final customers = (customerData as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      for (final row in customers) {
        final id = row['id'] as String?;
        if (id == null) continue;
        final tradeTitle = row['trade_title'] as String?;
        final fullName = row['full_name'] as String?;
        final phone = row['phone'] as String?;
        final customerCode = row['customer_code'] as String?;
        final name = (tradeTitle != null && tradeTitle.isNotEmpty)
            ? tradeTitle
            : (fullName ?? 'Bilinmeyen Cari');
        customerNamesById[id] = name;
        customerPhonesById[id] = phone;
        customerCodesById[id] = customerCode;
      }
    }

    return rawOrders.map((row) {
      final id = row['id'] as String;
      final customerId = row['customer_id'] as String?;
      final status = (row['status'] as String?) ?? '';
      final totalAmount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      final int? orderNo = (row['order_no'] as num?)?.toInt();
      final String? note = row['note'] as String?;
      final createdAtRaw = row['created_at'];
      final createdAt = createdAtRaw is String
          ? DateTime.parse(createdAtRaw)
          : createdAtRaw is DateTime
              ? createdAtRaw
              : DateTime.now();

      final customerName = customerId != null
          ? (customerNamesById[customerId] ?? 'Bilinmeyen Cari')
          : 'Bilinmeyen Cari';

        final customerPhone = customerId != null ? customerPhonesById[customerId] : null;
        final customerCode = customerId != null ? customerCodesById[customerId] : null;

      return AdminOrderListEntry(
        id: id,
        createdAt: createdAt,
        status: status,
        totalAmount: totalAmount,
        customerName: customerName,
        customerId: customerId,
        orderNo: orderNo,
        note: note,
        customerPhone: customerPhone,
        customerCode: customerCode,
      );
    }).toList();
  }

  Future<int> fetchOrderCount({
    String? status,
    List<String>? statuses,
  }) async {
    var query = _client.from('orders').select('id');

    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    } else if (status != null && status.isNotEmpty && status != 'all') {
      query = query.eq('status', status);
    }

    final dynamic data = await query;
    final list = (data as List<dynamic>);
    return list.length;
  }

  Future<AdminOrderDetail> fetchOrderDetail(String orderId) async {
    final ordersQuery = _client
        .from('orders')
        .select(
          'id, customer_id, status, note, total_amount, created_at, order_no',
        )
        .eq('id', orderId);

    debugPrint('[ADMIN][OrderDetail] fetching detail orderId=$orderId');

    final dynamic orderRow;
    try {
      orderRow = await ordersQuery.single();
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][OrderDetail] code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }

    if (orderRow is! Map<String, dynamic>) {
      throw Exception('Sipariş bulunamadı.');
    }

    final order = Map<String, dynamic>.from(orderRow);
    final customerId = order['customer_id'] as String?;

    String customerName = 'Bilinmeyen Cari';
    if (customerId != null) {
      final dynamic customerRow = await _client
          .from('customers')
          .select('trade_title, full_name')
          .eq('id', customerId)
          .maybeSingle();

      if (customerRow is Map<String, dynamic>) {
        final tradeTitle = customerRow['trade_title'] as String?;
        final fullName = customerRow['full_name'] as String?;
        customerName = (tradeTitle != null && tradeTitle.isNotEmpty)
            ? tradeTitle
            : (fullName ?? customerName);
      }
    }

    final items = await fetchOrderItems(orderId);

    final status = (order['status'] as String?) ?? '';
    final note = order['note'] as String?;
    final int? orderNo = (order['order_no'] as num?)?.toInt();
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final createdAtRaw = order['created_at'];
    final createdAt = createdAtRaw is String
        ? DateTime.parse(createdAtRaw)
        : createdAtRaw is DateTime
            ? createdAtRaw
            : DateTime.now();

    return AdminOrderDetail(
      id: orderId,
      customerName: customerName,
      status: status,
      note: note,
      totalAmount: totalAmount,
      createdAt: createdAt,
      items: items,
      orderNo: orderNo,
      customerId: customerId,
    );
  }

  Future<List<AdminOrderItemEntry>> fetchOrderItems(String orderId) async {
    final itemsQuery = _client
        .from('order_items')
        .select(
          'id, stock_id, name, qty, unit_name, unit_price, line_total',
        )
        .eq('order_id', orderId);

    debugPrint(
      '[ADMIN][OrderDetail] fetching items orderId=$orderId select=id,stock_id,name,qty,unit_name,unit_price,line_total',
    );

    final dynamic itemsData;
    try {
      itemsData = await itemsQuery;
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][OrderDetail] code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }

    final rawItems = (itemsData as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (rawItems.isEmpty) {
      return const <AdminOrderItemEntry>[];
    }

    final stockIds = rawItems
        .map((e) => e['stock_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    Map<String, String> stockNamesById = <String, String>{};
    if (stockIds.isNotEmpty) {
      final dynamic stocksData = await _client
          .from('stocks')
          .select('id, name')
          .inFilter('id', stockIds);

      final stocks = (stocksData as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      for (final row in stocks) {
        final id = row['id'] as String?;
        if (id == null) continue;
        final name = row['name'] as String?;
        if (name != null && name.isNotEmpty) {
          stockNamesById[id] = name;
        }
      }
    }

    return rawItems.map((row) {
      final id = (row['id'] as String?) ?? '';
      final stockId = (row['stock_id'] as String?) ?? '';

      num? quantity;
      final dynamic qtyValue = row['qty'];
      if (qtyValue is num) {
        quantity = qtyValue;
      } else if (qtyValue is String && qtyValue.trim().isNotEmpty) {
        quantity = num.tryParse(qtyValue.trim());
      }
      quantity ??= 0;

      String? unit;
      final dynamic unitNameValue = row['unit_name'];
      if (unitNameValue is String && unitNameValue.trim().isNotEmpty) {
        unit = unitNameValue.trim();
      }
      unit ??= '';

      final unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0;
      final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;

      String? itemName = row['name'] as String?;
      if (itemName == null || itemName.trim().isEmpty) {
        itemName = stockNamesById[stockId];
      }
      itemName ??= 'Bilinmeyen Stok';

      return AdminOrderItemEntry(
        id: id,
        stockId: stockId,
        name: itemName,
        unit: unit,
        quantity: quantity.toDouble(),
        unitPrice: unitPrice,
        lineTotal: lineTotal,
      );
    }).toList();
  }

  Future<List<AdminUnitOption>> fetchStockUnitOptions(String stockId) async {
    final query = _client
        .from('stock_units')
        .select('pack_qty,box_qty,carton_qty')
        .eq('stock_id', stockId);

    debugPrint(
      '[ADMIN][OrderDetail] fetching unit options stockId=$stockId select=pack_qty,box_qty,carton_qty',
    );

    final dynamic data;
    try {
      data = await query.maybeSingle();
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][OrderUnitOptions] code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }

    if (data == null) {
      return const <AdminUnitOption>[];
    }

    final row = Map<String, dynamic>.from(data as Map);

    double _toDouble(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toDouble();
      if (value is String && value.trim().isNotEmpty) {
        return double.tryParse(value.trim()) ?? 0;
      }
      return 0;
    }

    final List<AdminUnitOption> options = <AdminUnitOption>[];

    // Her zaman adet (piece) eklenir.
    options.add(
      const AdminUnitOption(
        code: 'piece',
        name: 'adet',
        multiplier: 1,
        isDefault: true,
      ),
    );

    final double packQty = _toDouble(row['pack_qty']);
    if (packQty > 0) {
      options.add(
        AdminUnitOption(
          code: 'pack',
          name: 'paket',
          multiplier: packQty,
          isDefault: false,
        ),
      );
    }

    final double boxQty = _toDouble(row['box_qty']);
    if (boxQty > 0) {
      options.add(
        AdminUnitOption(
          code: 'box',
          name: 'koli',
          multiplier: boxQty,
          isDefault: false,
        ),
      );
    }

    final double cartonQty = _toDouble(row['carton_qty']);
    if (cartonQty > 0) {
      options.add(
        AdminUnitOption(
          code: 'carton',
          name: 'kol',
          multiplier: cartonQty,
          isDefault: false,
        ),
      );
    }

    options.sort((a, b) => a.multiplier.compareTo(b.multiplier));

    return options;
  }

  Future<void> updateOrderItem({
    required String itemId,
    required num qty,
    required String unitName,
    required num unitPrice,
    required num lineTotal,
  }) async {
    try {
      await _client.from('order_items').update(<String, dynamic>{
        'qty': qty,
        'unit_name': unitName,
        'unit_price': unitPrice,
        'line_total': lineTotal,
      }).eq('id', itemId);
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][OrderItemUpdate] code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }
  }

  Future<void> deleteOrderItem(String itemId) async {
    try {
      await _client.from('order_items').delete().eq('id', itemId);
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][OrderItemDelete] code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }
  }

  Future<void> recalculateOrderTotal(String orderId) async {
    try {
      await _client.rpc(
        'recalc_order_total',
        params: <String, dynamic>{'p_order_id': orderId},
      );
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][OrderRecalcTotal] code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }
  }

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    await _client.from('orders').update(<String, dynamic>{
      'status': status,
    }).eq('id', orderId);
  }

  Future<void> updateOrderStatusAndNote({
    required String orderId,
    required String status,
    required String? note,
  }) async {
    await _client.from('orders').update(<String, dynamic>{
      'status': status,
      'note': note,
    }).eq('id', orderId);
  }

  Future<void> updateOrdersStatusBulk({
    required List<String> orderIds,
    required String status,
  }) async {
    if (orderIds.isEmpty) {
      return;
    }

    await _client.from('orders').update(<String, dynamic>{
      'status': status,
    }).inFilter('id', orderIds);
  }

  Future<void> cancelOrdersBulk({
    required List<String> orderIds,
    required String reason,
  }) async {
    if (orderIds.isEmpty) {
      return;
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      return;
    }

    final dynamic data = await _client
        .from('orders')
        .select('id, note')
        .inFilter('id', orderIds);

    final rows = (data as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    for (final row in rows) {
      final id = row['id'] as String?;
      if (id == null) continue;

      final existingNote = (row['note'] as String?)?.trim();
      String? newNote =
          existingNote == null || existingNote.isEmpty ? null : existingNote;

      final cancelLine = 'İptal: $trimmedReason';
      if (newNote == null || newNote.isEmpty) {
        newNote = cancelLine;
      } else {
        newNote = '$newNote\n$cancelLine';
      }

      await updateOrderStatusAndNote(
        orderId: id,
        status: 'cancelled',
        note: newNote,
      );
    }
  }
}

final adminOrderRepository = AdminOrderRepository(supabaseClient);
