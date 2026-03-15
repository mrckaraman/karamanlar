import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../audit/audit_service.dart';
import '../config/supabase_client.dart';

class AdminInvoiceListEntry {
  const AdminInvoiceListEntry({
    required this.id,
    required this.invoiceNo,
    required this.customerId,
    required this.customerName,
    required this.issuedAt,
    required this.totalAmount,
    required this.paidAmount,
    required this.status,
  });

  final String id;
  final String invoiceNo;
  final String customerId;
  final String customerName;
  final DateTime issuedAt;
  final double totalAmount;
  final double paidAmount;
  final String status;
}

class AdminInvoiceDetail {
  const AdminInvoiceDetail({
    required this.id,
    required this.invoiceNo,
    required this.status,
    required this.totalAmount,
    required this.paidAmount,
    required this.invoiceDate,
    required this.issuedAt,
    required this.createdAt,
    this.orderId,
    this.customerId,
  });

  final String id;
  final String invoiceNo;
  final String status;
  final double totalAmount;
  final double paidAmount;
  final DateTime? invoiceDate;
  final DateTime? issuedAt;
  final DateTime? createdAt;
  final String? orderId;
  final String? customerId;

  double get remainingAmount => totalAmount - paidAmount;

  DateTime get effectiveDate =>
      invoiceDate ?? issuedAt ?? createdAt ?? DateTime.now();
}

class AdminInvoiceItemEntry {
  const AdminInvoiceItemEntry({
    required this.stockId,
    required this.stockName,
    required this.qty,
    required this.unitName,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String stockId;
  final String stockName;
  final double qty;
  final String unitName;
  final double unitPrice;
  final double lineTotal;
}

class AdminInvoiceRepository {
  AdminInvoiceRepository(this._client) : _audit = AuditService(_client);

  final SupabaseClient _client;
  final AuditService _audit;

  Future<List<AdminInvoiceListEntry>> fetchInvoices({
    String? status,
    List<String>? statuses,
    String? search,
    bool overdueOnly = false,
    String? customerId,
  }) async {
    const selectColumns =
        'id, order_id, customer_id, invoice_no, invoice_date, total_amount, paid_amount, status, created_at, issued_at';

    // Debug amaçlı: runtime'da gerçekten hangi select ifadesini
    // kullandığımızı loglayalım.
    // Böylece Supabase hatasında due_date görünüyorsa, bunun bu
    // repository'den mi yoksa başka bir kaynaktan mı geldiğini ayırt
    // edebiliriz.
    debugPrint(
      '[ADMIN][Invoices] fetchInvoices select="$selectColumns" status=$status statuses=$statuses overdueOnly=$overdueOnly search=${search ?? ''}',
    );

    var query = _client.from('invoices').select(selectColumns);

    // Status filtresi (tekli / çoklu)
    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    } else if (status != null && status.isNotEmpty && status != 'all') {
      query = query.eq('status', status);
    }

    // Belirli bir cari için fatura listesi
    if (customerId != null && customerId.isNotEmpty) {
      query = query.eq('customer_id', customerId);
    }

    // Arama: fatura no / cari adı client-side uygulanacak.

    // Geciken faturalar için filtre, şimdilik üst katmanda tarih bazlı
    // (invoice_date/issued_at/created_at) kontrolle client-side uygulanıyor.
    if (overdueOnly) {
      // İleride burada invoice_date < today ve status != paid/cancelled/refunded
      // şeklinde server-side filtre eklenebilir.
    }

    final dynamic data = await query.order('invoice_date', ascending: false);

    final rawInvoices = (data as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (rawInvoices.isEmpty) {
      return const <AdminInvoiceListEntry>[];
    }

    final customerIds = rawInvoices
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

    final entries = rawInvoices.map((row) {
        final id = row['id'] as String;
      final customerId = row['customer_id'] as String?;
      final statusValue = (row['status'] as String?) ?? '';
      final totalAmount = (row['total_amount'] as num?)?.toDouble() ?? 0;
        final paidAmount = (row['paid_amount'] as num?)?.toDouble() ?? 0;

        final invoiceDateRaw = row['invoice_date'];
        final DateTime? invoiceDate = invoiceDateRaw is String
          ? DateTime.parse(invoiceDateRaw)
          : invoiceDateRaw is DateTime
            ? invoiceDateRaw
            : null;

        final issuedRaw = row['issued_at'];
        final DateTime? issuedAtFromDb = issuedRaw is String
          ? DateTime.parse(issuedRaw)
          : issuedRaw is DateTime
            ? issuedRaw
            : null;

        final createdRaw = row['created_at'];
        final DateTime? createdAt = createdRaw is String
          ? DateTime.parse(createdRaw)
          : createdRaw is DateTime
            ? createdRaw
            : null;

        // Fatura tarihi: öncelik invoice_date -> issued_at -> created_at.
        final DateTime effectiveDate =
          invoiceDate ?? issuedAtFromDb ?? createdAt ?? DateTime.now();

      final customerName = customerId != null
          ? (customerNamesById[customerId] ?? 'Bilinmeyen Cari')
          : 'Bilinmeyen Cari';

      final invoiceNo = (row['invoice_no'] as String?) ?? '';

      return AdminInvoiceListEntry(
        id: id,
        invoiceNo: invoiceNo,
        customerId: customerId ?? '',
        customerName: customerName,
        issuedAt: effectiveDate,
        totalAmount: totalAmount,
        paidAmount: paidAmount,
        status: statusValue,
      );
    }).toList();

    // Arama filtresini client-side uygula.
    final filtered = _applySearchFilter(entries, search);

    // Vadesi geçen filtrelemesi ileride server-side yapılabilir;
    // şu an overdueOnly bayrağı yalnızca üst katman mantığı için tutuluyor.
    return filtered;
  }

  Future<AdminInvoiceDetail> fetchInvoiceById(String invoiceId) async {
    const selectColumns =
        'id, order_id, customer_id, invoice_no, invoice_date, total_amount, paid_amount, status, created_at, issued_at';

    final debugUrl =
        '/rest/v1/invoices?select=$selectColumns&id=eq.$invoiceId';
    debugPrint(
      '[ADMIN][InvoiceDetail] fetchInvoiceById id=$invoiceId url=$debugUrl',
    );

    dynamic data;
    try {
      data = await _client
          .from('invoices')
          .select(selectColumns)
          .eq('id', invoiceId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][InvoiceDetail] fetchInvoiceById id=$invoiceId url=$debugUrl code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }

    if (data == null) {
      throw Exception('Fatura bulunamadı.');
    }

    final row = Map<String, dynamic>.from(data as Map);

    final id = row['id'] as String? ?? invoiceId;
    final orderId = row['order_id'] as String?;
    final customerId = row['customer_id'] as String?;
    final invoiceNo = (row['invoice_no'] as String?) ?? '';
    final statusValue = (row['status'] as String?) ?? '';
    final totalAmount = (row['total_amount'] as num?)?.toDouble() ?? 0;
    final paidAmount = (row['paid_amount'] as num?)?.toDouble() ?? 0;

    DateTime? _parseDateTime(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value);
      }
      return null;
    }

    final invoiceDate = _parseDateTime(row['invoice_date']);
    final issuedAt = _parseDateTime(row['issued_at']);
    final createdAt = _parseDateTime(row['created_at']);

    return AdminInvoiceDetail(
      id: id,
      invoiceNo: invoiceNo,
      status: statusValue,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      invoiceDate: invoiceDate,
      issuedAt: issuedAt,
      createdAt: createdAt,
      orderId: orderId,
      customerId: customerId,
    );
  }

  Future<void> linkPaymentToInvoice({
    required String paymentId,
    required String invoiceId,
  }) async {
    try {
      await _client.rpc(
        'rpc_link_payment_to_invoice',
        params: <String, dynamic>{
          'p_payment_id': paymentId,
          'p_invoice_id': invoiceId,
        },
      );
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][Invoices] linkPaymentToInvoice paymentId=$paymentId invoiceId=$invoiceId code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }
  }

  /// Belirli bir siparişe ait ilk faturayı (varsa) döner.
  Future<String?> findInvoiceIdByOrderId(String orderId) async {
    const selectColumns = 'id, status';

    debugPrint(
      '[ADMIN][Invoices] findInvoiceIdByOrderId orderId=$orderId',
    );

    try {
      final dynamic data = await _client
          .from('invoices')
          .select(selectColumns)
          .eq('order_id', orderId)
          .limit(1)
          .maybeSingle();

      if (data == null) {
        return null;
      }

      final row = Map<String, dynamic>.from(data as Map);
      final id = row['id'] as String?;
      final status = (row['status'] as String?)?.trim().toLowerCase();

      // "Fatura hazır" bilgisini sadece açık benzeri statüler için döndür.
      // Böylece sipariş detayı ekranında banner yalnızca
      // invoice.status in ('issued','open') iken gösterilir.
      if (status != null && status.isNotEmpty) {
        final isOpenLike = status == 'issued' || status == 'open';
        if (!isOpenLike) {
          return null;
        }
      }

      return (id != null && id.isNotEmpty) ? id : null;
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][Invoices] findInvoiceIdByOrderId orderId=$orderId code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }
  }

  Future<List<AdminInvoiceItemEntry>> fetchInvoiceItems(
    String invoiceId,
  ) async {
    // 1) Önce invoice_items tablosu varsa onu dene.
    const invoiceItemsSelect =
        'stock_id, stock_name, qty, unit_name, unit_price, line_total';
    final invoiceItemsUrl =
        '/rest/v1/invoice_items?select=$invoiceItemsSelect&invoice_id=eq.$invoiceId';

    debugPrint(
      '[ADMIN][InvoiceDetail] fetchInvoiceItems (invoice_items) invoiceId=$invoiceId url=$invoiceItemsUrl',
    );

    try {
      final dynamic data = await _client
          .from('invoice_items')
          .select(invoiceItemsSelect)
          .eq('invoice_id', invoiceId);

      final rows = (data as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (rows.isNotEmpty) {
        return rows.map((row) {
          final stockId = (row['stock_id'] as String?) ?? '';
          final stockName = (row['stock_name'] as String?) ?? 'Bilinmeyen Stok';
          final qty = (row['qty'] as num?)?.toDouble() ?? 0;
          final unitName = (row['unit_name'] as String?) ?? '';
          final unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0;
          final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;

          return AdminInvoiceItemEntry(
            stockId: stockId,
            stockName: stockName,
            qty: qty,
            unitName: unitName,
            unitPrice: unitPrice,
            lineTotal: lineTotal,
          );
        }).toList();
      }
    } on PostgrestException catch (e) {
      // Tablo yoksa veya yetki hatası varsa debug için URL'i logla.
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][InvoiceDetail] fetchInvoiceItems (invoice_items) invoiceId=$invoiceId url=$invoiceItemsUrl code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      // Eğer gerçekten tablo yoksa (undefined_table) order_items fallback'ine geçeceğiz.
      // Diğer hataları da fallback ile birlikte üst katmana fırlatmak için swallow etmiyoruz.
    }

    // 2) invoice_items tablosu yoksa veya boş döndüyse: orders + order_items üzerinden kalemleri çek.
    const invoiceSelect = 'order_id';
    final invoiceUrl =
        '/rest/v1/invoices?select=$invoiceSelect&id=eq.$invoiceId';
    debugPrint(
      '[ADMIN][InvoiceDetail] fetchInvoiceItems (order_items fallback - invoice) invoiceId=$invoiceId url=$invoiceUrl',
    );

    String? orderId;
    try {
      final dynamic invoiceData = await _client
          .from('invoices')
          .select(invoiceSelect)
          .eq('id', invoiceId)
          .maybeSingle();

      if (invoiceData != null) {
        final row = Map<String, dynamic>.from(invoiceData as Map);
        orderId = row['order_id'] as String?;
      }
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][InvoiceDetail] fetchInvoiceItems (invoice lookup) invoiceId=$invoiceId url=$invoiceUrl code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }

    if (orderId == null || orderId.isEmpty) {
      return const <AdminInvoiceItemEntry>[];
    }

    const orderItemsSelect =
        'stock_id, name, qty, unit_name, unit_price, line_total';
    final orderItemsUrl =
        '/rest/v1/order_items?select=$orderItemsSelect&order_id=eq.$orderId';
    debugPrint(
      '[ADMIN][InvoiceDetail] fetchInvoiceItems (order_items fallback) invoiceId=$invoiceId orderId=$orderId url=$orderItemsUrl',
    );

    try {
      final dynamic itemsData = await _client
          .from('order_items')
          .select(orderItemsSelect)
          .eq('order_id', orderId);

      final rows = (itemsData as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (rows.isEmpty) {
        return const <AdminInvoiceItemEntry>[];
      }

      return rows.map((row) {
        final stockId = (row['stock_id'] as String?) ?? '';
        String stockName = (row['name'] as String?) ?? '';
        if (stockName.trim().isEmpty) {
          stockName = 'Bilinmeyen Stok';
        }
        final qty = (row['qty'] as num?)?.toDouble() ?? 0;
        final unitName = (row['unit_name'] as String?) ?? '';
        final unitPrice = (row['unit_price'] as num?)?.toDouble() ?? 0;
        final lineTotal = (row['line_total'] as num?)?.toDouble() ?? 0;

        return AdminInvoiceItemEntry(
          stockId: stockId,
          stockName: stockName,
          qty: qty,
          unitName: unitName,
          unitPrice: unitPrice,
          lineTotal: lineTotal,
        );
      }).toList();
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][InvoiceDetail] fetchInvoiceItems (order_items fallback) invoiceId=$invoiceId orderId=$orderId url=$orderItemsUrl code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }
  }

  List<AdminInvoiceListEntry> _applySearchFilter(
    List<AdminInvoiceListEntry> source,
    String? search,
  ) {
    final raw = search?.trim();
    if (raw == null || raw.isEmpty) {
      return source;
    }

    final term = raw.toLowerCase();
    return source.where((invoice) {
      final inInvoiceNo = invoice.invoiceNo.toLowerCase().contains(term);
      final inCustomerName = invoice.customerName.toLowerCase().contains(term);
      return inInvoiceNo || inCustomerName;
    }).toList();
  }

  Future<void> updateInvoiceStatus({
    required String invoiceId,
    required String status,
  }) async {
    await _client
        .from('invoices')
        .update(<String, dynamic>{
          'status': status,
        })
        .eq('id', invoiceId);
  }

  /// Manuel fatura oluşturma (cari bazlı).
  ///
  /// Dönüş: oluşturulan faturanın ID'si.
  Future<String> createInvoiceForCustomer({
    required String customerId,
    String? invoiceNo,
    required DateTime invoiceDate,
    double totalAmount = 0,
  }) async {
    final now = DateTime.now();

    final payload = <String, dynamic>{
      'customer_id': customerId,
      'status': 'issued',
      'invoice_date': invoiceDate.toIso8601String(),
      'issued_at': now.toIso8601String(),
      'total_amount': totalAmount,
    };

    if (invoiceNo != null && invoiceNo.isNotEmpty) {
      payload['invoice_no'] = invoiceNo;
    }

    const selectColumns = 'id';
    dynamic data;
    try {
      data = await _client
          .from('invoices')
          .insert(payload)
          .select(selectColumns)
          .maybeSingle();
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][Invoices] createInvoiceForCustomer customerId=$customerId code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }

    if (data == null) {
      throw Exception('Fatura oluşturulamadı.');
    }

    final row = Map<String, dynamic>.from(data as Map);
    final id = row['id'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('Fatura ID bilgisi alınamadı.');
    }

    return id;
  }

  /// Var olan bir faturayı ve ilişkili kalemlerini günceller.
  ///
  /// Not: Gerçek anlamda atomik bir işlem için bu mantığın Supabase
  /// tarafında tek bir RPC içinde transaction ile uygulanması önerilir.
  /// Şimdilik basitçe:
  ///   1) invoices tablosunda temel alanları günceller
  ///   2) ilgili invoice_items satırlarını silip yeniden ekler.
  Future<void> updateInvoiceWithItems({
    required String invoiceId,
    required DateTime invoiceDate,
    String? invoiceNo,
    required List<Map<String, dynamic>> items,
  }) async {
    await _logAuthContext('updateInvoiceWithItems');

    // Toplam tutarı kalemlerden hesapla.
    final totalAmount = items.fold<double>(
      0,
      (sum, item) {
        final qty = (item['qty'] as num?)?.toDouble() ?? 0;
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
        return sum + qty * unitPrice;
      },
    );

    final payload = <String, dynamic>{
      'invoice_date': invoiceDate.toIso8601String(),
      'total_amount': totalAmount,
    };

    final trimmedNo = invoiceNo?.trim();
    if (trimmedNo != null && trimmedNo.isNotEmpty) {
      payload['invoice_no'] = trimmedNo;
    }

    try {
      // 1) Faturayı güncelle.
      await _client
          .from('invoices')
          .update(payload)
          .eq('id', invoiceId);

      // 2) Mevcut kalemleri temizle.
      await _client
          .from('invoice_items')
          .delete()
          .eq('invoice_id', invoiceId);

      // 3) Yeni kalemleri ekle.
      if (items.isNotEmpty) {
        final rows = items.map((item) {
          final qty = (item['qty'] as num?)?.toDouble() ?? 0;
          final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0;
          final lineTotal = qty * unitPrice;

          return <String, dynamic>{
            'invoice_id': invoiceId,
            'stock_id': item['stock_id'],
            'stock_name': item['stock_name'],
            'unit_name': item['unit_name'],
            'qty': qty,
            'unit_price': unitPrice,
            'line_total': lineTotal,
          };
        }).toList();

        await _client.from('invoice_items').insert(rows);
      }
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][Invoices] updateInvoiceWithItems invoiceId=$invoiceId code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }
  }

  Future<void> _logAuthContext(String label) async {
    if (!kDebugMode) {
      return;
    }

    final user = _client.auth.currentUser;
    final session = _client.auth.currentSession;
    final token = session?.accessToken;
    final tokenLen = token?.length ?? 0;
    final tokenPrefix = tokenLen > 0
        ? token!.substring(0, tokenLen > 10 ? 10 : tokenLen)
        : null;

    debugPrint(
      '[AUTH][$label] '
      'uid=${user?.id} '
      'email=${user?.email}',
    );

    debugPrint(
      '[AUTH][$label] '
      'hasSession=${session != null} '
      'tokenLen=$tokenLen '
      'tokenPrefix=${tokenPrefix != null ? '$tokenPrefix...' : 'null'}',
    );

    try {
      final dynamic isAdminResult = await _client.rpc('is_admin');
      debugPrint('[AUTH][$label] rpc is_admin=$isAdminResult');
    } catch (e, st) {
      debugPrint('[AUTH][$label] rpc is_admin error=$e');
      debugPrintStack(stackTrace: st);
    }
  }

  /// Siparişi tek adımda faturaya dönüştürür.
  ///
  /// ASSUMPTIONS:
  /// - Backend tarafında `rpc_convert_order_to_invoice(p_order_id uuid)`
  ///   isimli bir RPC fonksiyonu vardır.
  /// - RPC doğrudan fatura id'sini (String) döndürebilir veya
  ///   `{ "new_invoice_id": "..." }` / `{ "invoice_id": "..." }`
  ///   şeklinde bir nesne döndürebilir.
  Future<String> convertOrderToInvoice({
    required String orderId,
  }) async {
    if (kDebugMode) {
      final session = Supabase.instance.client.auth.currentSession;
      debugPrint(
        '[ADMIN][Invoices] convertOrderToInvoice: '
        'session_exists=${session != null} uid=${session?.user.id}',
      );
      debugPrint(
        '[ADMIN][Invoices] convertOrderToInvoice params={p_order_id: $orderId}',
      );
    }

    Map<String, dynamic>? oldOrder;
    try {
      final row = await _client
          .from('orders')
          .select(
            'id, customer_id, status, total_amount, created_at, order_no, note',
          )
          .eq('id', orderId)
          .maybeSingle();
      if (row != null) {
        oldOrder = Map<String, dynamic>.from(row as Map);
      }
    } catch (_) {
      // Best-effort: audit için old_value alınamazsa ana akışı bozma.
    }

    try {
      final dynamic data = await _client.rpc(
        'rpc_convert_order_to_invoice',
        params: <String, dynamic>{'p_order_id': orderId},
      );

      if (kDebugMode) {
        debugPrint(
          '[ADMIN][Invoices] convertOrderToInvoice raw_result=$data',
        );
      }

      final invoiceId = _normalizeConvertOrderToInvoiceResult(data);

      unawaited(
        _audit.logChange(
          entity: 'orders',
          entityId: orderId,
          action: 'convert',
          oldValue: oldOrder,
          newValue: <String, dynamic>{
            'invoice_id': invoiceId,
          },
        ),
      );

      return invoiceId;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SUPABASE-ERROR][ADMIN][Invoices] convertOrderToInvoice '
          'orderId=$orderId code=${e.code} message=${e.message} '
          'details=${e.details} hint=${e.hint}',
        );
      }

      // Yetki ve oturum hatalarını kullanıcı dostu mesajlara çevir.
      final code = e.code;
      if (code == '28000') {
        throw Exception(
          'Oturum bulunamadı veya süresi doldu. Lütfen tekrar giriş yapın.',
        );
      }
      if (code == 'P0001') {
        throw Exception(
          'Bu işlemi yapma yetkiniz yok. Yetkili bir kullanıcı ile tekrar deneyin.',
        );
      }

      rethrow;
    }
  }
}

String _normalizeConvertOrderToInvoiceResult(dynamic data) {
  if (data == null) {
    throw Exception('Fatura ID dönmedi.');
  }

  if (data is String) {
    if (data.isEmpty) {
      throw Exception('Boş fatura ID döndü.');
    }
    return data;
  }

  if (data is Map) {
    final map = Map<String, dynamic>.from(data);
    final invoiceId = (map['new_invoice_id'] ?? map['invoice_id']) as String?;
    if (invoiceId == null || invoiceId.isEmpty) {
      throw Exception('RPC sonucu içinde invoice id bulunamadı.');
    }
    return invoiceId;
  }

  throw Exception('Beklenmeyen RPC dönüş tipi: ${data.runtimeType}');
}

final adminInvoiceRepository = AdminInvoiceRepository(supabaseClient);

/// Admin fatura oluşturma akışında kullanılan "Cari + Son Fatura" listesi
class AdminInvoiceCustomerPickEntry {
  const AdminInvoiceCustomerPickEntry({
    required this.customerId,
    required this.displayName,
    required this.tradeTitle,
    required this.fullName,
    required this.phone,
    required this.customerCode,
    required this.lastInvoiceNo,
    required this.lastIssuedAt,
  });

  final String customerId;
  final String displayName;
  final String? tradeTitle;
  final String? fullName;
  final String? phone;
  final String? customerCode;
  final String? lastInvoiceNo;
  final DateTime? lastIssuedAt;
}

class AdminInvoiceCustomerRepository {
  AdminInvoiceCustomerRepository(this._client);

  final SupabaseClient _client;

  /// v_admin_customers_with_last_invoice üzerinden cari + son fatura listesini çeker.
  ///
  /// Arama: cari adı, ticari unvan, telefon, cari kodu, last_invoice_no.
  Future<List<AdminInvoiceCustomerPickEntry>> fetchCustomersWithLastInvoice({
    String? search,
    int limit = 100,
  }) async {
    final trimmedSearch = search?.trim();
    debugPrint(
      '[ADMIN][InvoiceCustomer] fetchCustomersWithLastInvoice via RPC search=${trimmedSearch ?? ''} limit=$limit',
    );

    dynamic data;
    try {
      data = await _client.rpc(
        'rpc_admin_customers_with_last_invoice',
        params: <String, dynamic>{
          'p_search': (trimmedSearch == null || trimmedSearch.isEmpty)
              ? null
              : trimmedSearch,
          'p_limit': limit,
        },
      );
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][InvoiceCustomer] fetchCustomersWithLastInvoice code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }

    if (data == null) {
      return const <AdminInvoiceCustomerPickEntry>[];
    }

    if (data is! List) {
      throw Exception(
        'Beklenmeyen RPC dönüş tipi: ${data.runtimeType}',
      );
    }

    final rows = data
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (rows.isEmpty) {
      return const <AdminInvoiceCustomerPickEntry>[];
    }

    List<AdminInvoiceCustomerPickEntry> entries = rows.map((row) {
      final customerId = (row['customer_id'] as String?) ?? (row['id'] as String?);
      if (customerId == null) {
        return null;
      }

      final tradeTitle = row['trade_title'] as String?;
      final fullName = row['full_name'] as String?;
      final phone = row['phone'] as String?;
      final customerCode = row['customer_code'] as String?;
      final lastInvoiceNo = row['last_invoice_no'] as String?;

      DateTime? lastIssuedAt;
      final rawDate = row['last_invoice_issued_at'];
      if (rawDate is String && rawDate.isNotEmpty) {
        lastIssuedAt = DateTime.tryParse(rawDate);
      } else if (rawDate is DateTime) {
        lastIssuedAt = rawDate;
      }

      final displayName =
          (tradeTitle != null && tradeTitle.isNotEmpty)
              ? tradeTitle
              : (fullName != null && fullName.isNotEmpty)
                  ? fullName
                  : 'Bilinmeyen Cari';

      return AdminInvoiceCustomerPickEntry(
        customerId: customerId,
        displayName: displayName,
        tradeTitle: tradeTitle,
        fullName: fullName,
        phone: phone,
        customerCode: customerCode,
        lastInvoiceNo: lastInvoiceNo,
        lastIssuedAt: lastIssuedAt,
      );
    }).whereType<AdminInvoiceCustomerPickEntry>().toList();

    // Arama client-side uygulanır: ad, telefon, kod, last_invoice_no.
    final rawSearch = trimmedSearch;
    if (rawSearch == null || rawSearch.isEmpty) {
      return entries;
    }

    final term = rawSearch.toLowerCase();
    return entries.where((entry) {
      final inName = entry.displayName.toLowerCase().contains(term);
      final inPhone = (entry.phone ?? '').toLowerCase().contains(term);
      final inCode = (entry.customerCode ?? '').toLowerCase().contains(term);
      final inLastInvoice = (entry.lastInvoiceNo ?? '').toLowerCase().contains(term);
      return inName || inPhone || inCode || inLastInvoice;
    }).toList();
  }

  /// Belirli bir customerId icin v_admin_customers_with_last_invoice kaydini dondurur.
  Future<AdminInvoiceCustomerPickEntry> fetchCustomerWithLastInvoiceById(
    String customerId,
  ) async {
    const selectColumns =
      'customer_id, trade_title, full_name, phone, customer_code, last_invoice_no, last_invoice_issued_at';

    debugPrint(
      '[ADMIN][InvoiceCustomer] fetchCustomerWithLastInvoiceById customerId=$customerId select="$selectColumns"',
    );

    dynamic data;
    try {
      data = await _client
          .from('v_admin_customers_with_last_invoice')
          .select(selectColumns)
          .eq('customer_id', customerId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      debugPrint(
        '[SUPABASE-ERROR][ADMIN][InvoiceCustomer] fetchCustomerWithLastInvoiceById customerId=$customerId code=${e.code} message=${e.message} details=${e.details} hint=${e.hint}',
      );
      rethrow;
    }

    if (data == null) {
      throw Exception('Cari bulunamadı veya görüntüleme yetkiniz yok.');
    }

    final row = Map<String, dynamic>.from(data as Map);

    final id = (row['customer_id'] as String?) ?? (row['id'] as String?);
    if (id == null) {
      throw Exception('Geçersiz cari kaydı.');
    }

    final tradeTitle = row['trade_title'] as String?;
    final fullName = row['full_name'] as String?;
    final phone = row['phone'] as String?;
    final customerCode = row['customer_code'] as String?;
    final lastInvoiceNo = row['last_invoice_no'] as String?;

    DateTime? lastIssuedAt;
    final rawDate = row['last_invoice_issued_at'];
    if (rawDate is String && rawDate.isNotEmpty) {
      lastIssuedAt = DateTime.tryParse(rawDate);
    } else if (rawDate is DateTime) {
      lastIssuedAt = rawDate;
    }

    final displayName =
        (tradeTitle != null && tradeTitle.isNotEmpty)
            ? tradeTitle
            : (fullName != null && fullName.isNotEmpty)
                ? fullName
                : 'Bilinmeyen Cari';

    return AdminInvoiceCustomerPickEntry(
      customerId: id,
      displayName: displayName,
      tradeTitle: tradeTitle,
      fullName: fullName,
      phone: phone,
      customerCode: customerCode,
      lastInvoiceNo: lastInvoiceNo,
      lastIssuedAt: lastIssuedAt,
    );
  }
}

final adminInvoiceCustomerRepository =
    AdminInvoiceCustomerRepository(supabaseClient);
