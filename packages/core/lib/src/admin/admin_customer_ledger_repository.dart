import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';
import '../audit/audit_service.dart';
import '../exceptions/app_exception.dart';
import '../models/payment_method.dart';

class LedgerRow {
  const LedgerRow({
    required this.id,
    required this.customerId,
    required this.date,
    required this.type,
    required this.description,
    required this.debit,
    required this.credit,
    this.runningBalance,
    this.refType,
    this.refId,
  });

  final String id;
  final String customerId;
  final DateTime date;
  final String type;
  final String description;
  final double debit;
  final double credit;
  final double? runningBalance;
  final String? refType;
  final String? refId;

  factory LedgerRow.fromMap(Map<String, dynamic> map) {
    final rawDate = map['created_at'] ?? map['date'];
    DateTime parsedDate;
    if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String) {
      parsedDate =
          DateTime.tryParse(rawDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(0);
    }
    parsedDate = parsedDate.toLocal();

    return LedgerRow(
      id: map['id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      date: parsedDate,
      type: (map['type'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      debit: (map['debit'] as num?)?.toDouble() ?? 0,
      credit: (map['credit'] as num?)?.toDouble() ?? 0,
      runningBalance: (map['running_balance'] as num?)?.toDouble(),
      refType: map['ref_type'] as String?,
      refId: map['ref_id']?.toString(),
    );
  }
}

class PaymentRow {
  const PaymentRow({
    required this.id,
    required this.customerId,
    required this.date,
    required this.amount,
    required this.method,
    required this.description,
    required this.isCancelled,
    this.cancelReason,
  });

  /// Payment ID (customer_payments.id)
  final String id;

  /// İlişkili cari (customer_id)
  final String customerId;

  /// Ödeme tarihi (payment_date)
  final DateTime date;

  /// Tutar (amount)
  final double amount;

  /// Ödeme yöntemi (payment_method)
  final PaymentMethod method;

  /// Açıklama (description)
  final String description;

  /// İptal durumu (is_cancelled)
  final bool isCancelled;

  /// İptal sebebi (cancel_reason)
  final String? cancelReason;

  factory PaymentRow.fromMap(Map<String, dynamic> map) {
    final rawDate = map['payment_date'];
    late final DateTime parsedDate;
    if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String) {
      // payment_date bir DATE kolonu, saat bilgisini yok saymak için
      // sadece parse edip günü baz alıyoruz.
      parsedDate =
          DateTime.tryParse(rawDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return PaymentRow(
      id: map['id']?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      date: parsedDate,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      method: PaymentMethodX.fromDb(
        (map['payment_method'] as String?) ?? 'cash',
      ),
      description: (map['description'] as String?) ?? '',
      isCancelled: (map['is_cancelled'] as bool?) ?? false,
      cancelReason: map['cancel_reason'] as String?,
    );
  }
}

class AgingRow {
  const AgingRow({
    required this.bucket,
    required this.amount,
    required this.count,
  });

  final String bucket;
  final double amount;
  final int count;

  factory AgingRow.fromMap(Map<String, dynamic> map) {
    return AgingRow(
      bucket: (map['bucket'] as String?) ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class CustomerBalance {
  const CustomerBalance({
    required this.totalDebit,
    required this.totalCredit,
    required this.net,
  });

  final double totalDebit;
  final double totalCredit;
  final double net;

  factory CustomerBalance.fromMap(Map<String, dynamic> map) {
    return CustomerBalance(
      totalDebit: (map['total_debit'] as num?)?.toDouble() ?? 0,
      totalCredit: (map['total_credit'] as num?)?.toDouble() ?? 0,
      net: (map['net'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ManualRefundRequest {
  const ManualRefundRequest({
    required this.customerId,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.note,
  });

  final String customerId;
  final double quantity;
  final String unit;
  final double unitPrice;
  final String? note;

  double get total => quantity * unitPrice;
}

class AdminCustomerLedgerRepository {
  AdminCustomerLedgerRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client,
        _audit = AuditService(client ?? Supabase.instance.client);

  final SupabaseClient _client;
  final AuditService _audit;
  static bool _didCheckCustomerPaymentsSelect = false;

  Future<T> _guard<T>(
    String operation,
    Future<T> Function() run, {
    String? fallbackMessage,
  }) async {
    try {
      return await run();
    } catch (e, st) {
      throw mapSupabaseError(
        e,
        st,
        operation: operation,
        fallbackMessage: fallbackMessage,
      );
    }
  }

  Future<List<LedgerRow>> fetchStatement(
    String customerId, {
    DateTime? from,
    DateTime? to,
    String? type,
  }) async {
    // Müşteri uygulamasıyla aynı kaynağı kullanmak için
    // ledger_entries tabanlı view'e geç.
    const table = 'v_customer_statement_with_balance';

    debugPrint(
      '[LEDGER][FETCH] table=$table customerId=$customerId '
      'from=${from?.toIso8601String()} to=${to?.toIso8601String()}',
    );

    var query = _client
        .from(table)
        .select(
          'id, customer_id, date, created_at, type, ref_id, description, debit, credit, balance, is_overdue',
        )
        .eq('customer_id', customerId);

    if (from != null) {
      query = query.gte('created_at', _toIsoUtcStartOfDay(from));
    }
    if (to != null) {
      query = query.lte('created_at', _toIsoUtcEndOfDay(to));
    }

    final data = await _guard(
      'ledger.fetchStatement',
      () => query.order('created_at', ascending: false),
      fallbackMessage: 'Ekstre yüklenemedi. Lütfen tekrar deneyin.',
    );
    final rows = (data as List<dynamic>)
        .map((e) => LedgerRow.fromMap(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();

    final totalDebit = rows.fold<double>(0, (sum, r) => sum + r.debit);
    final totalCredit = rows.fold<double>(0, (sum, r) => sum + r.credit);
    final net = totalDebit - totalCredit;

    debugPrint(
      '[LEDGER][FETCH] table=$table customerId=$customerId rows=${rows.length} '
      'totalDebit=$totalDebit totalCredit=$totalCredit net=$net',
    );

    return rows;
  }

  static String _toIsoUtcStartOfDay(DateTime date) {
    final localStart = DateTime(date.year, date.month, date.day);
    return localStart.toUtc().toIso8601String();
  }

  static String _toIsoUtcEndOfDay(DateTime date) {
    final localEnd = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
    return localEnd.toUtc().toIso8601String();
  }

  Future<List<PaymentRow>> fetchPayments(
    String customerId, {
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client.from('customer_payments').select(
          'id, customer_id, payment_date, amount, payment_method, description, is_cancelled, cancel_reason',
        );

    // "_all" sentinel degeri, tum musterilerin tahsilatlarini
    // getirmek icin kullanilir. Diger durumda belirli bir
    // customer_id'ye gore filtre uygulanir.
    if (customerId != '_all') {
      query = query.eq('customer_id', customerId);
    }
    String formatDateOnly(DateTime d) {
      return '${d.year.toString().padLeft(4, '0')}'
          '-${d.month.toString().padLeft(2, '0')}'
          '-${d.day.toString().padLeft(2, '0')}';
    }

    if (from != null) {
      query = query.gte('payment_date', formatDateOnly(from));
    }
    if (to != null) {
      query = query.lte('payment_date', formatDateOnly(to));
    }

    final data = await _guard(
      'ledger.fetchPayments',
      () => query.order('payment_date', ascending: false),
      fallbackMessage: 'Tahsilatlar yüklenemedi. Lütfen tekrar deneyin.',
    );
    return (data as List<dynamic>)
        .map((e) => PaymentRow.fromMap(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();
  }

  Future<PaymentRow> fetchPaymentById(String id) async {
    final data = await _guard(
      'ledger.fetchPaymentById',
      () => _client
          .from('customer_payments')
          .select(
            'id, customer_id, payment_date, amount, payment_method, description, is_cancelled, cancel_reason',
          )
          .eq('id', id)
          .maybeSingle(),
      fallbackMessage: 'Tahsilat detayı yüklenemedi. Lütfen tekrar deneyin.',
    );

    if (data == null) {
      throw AppException(
        'Tahsilat kaydı bulunamadı.',
        code: 'not_found',
      );
    }

    return PaymentRow.fromMap(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<List<AgingRow>> fetchAging(String customerId) async {
    final data = await _guard(
      'ledger.fetchAging',
      () => _client
          .from('v_customer_aging')
          .select('bucket, amount, count')
          .eq('customer_id', customerId)
          .order('bucket_order'),
      fallbackMessage: 'Vade analizi yüklenemedi. Lütfen tekrar deneyin.',
    );
    return (data as List<dynamic>)
        .map((e) => AgingRow.fromMap(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();
  }

  Future<CustomerBalance> fetchBalance(String customerId) async {
    final data = await _guard(
      'ledger.fetchBalance',
      () => _client
          .from('v_customer_balance')
          .select('total_debit, total_credit, net')
          .eq('customer_id', customerId)
          .maybeSingle(),
      fallbackMessage: 'Bakiye yüklenemedi. Lütfen tekrar deneyin.',
    );

    if (data == null) {
      return const CustomerBalance(
        totalDebit: 0,
        totalCredit: 0,
        net: 0,
      );
    }

    return CustomerBalance.fromMap(
      Map<String, dynamic>.from(data as Map),
    );
  }

  /// Belirli bir tarih itibarıyla (o tarih dahil) cari bakiyeyi hesaplar.
  ///
  /// Bu metod, ekstre (statement) kayıtlarını kullanarak
  /// toplam borç/alacak ve net bakiyeyi client-side toplar.
  Future<CustomerBalance> fetchCustomerBalanceAt(
    String customerId,
    DateTime at,
  ) async {
    // Tarihi sadeleştir: saat bilgisini kaldırıp günü baz al.
    final dateOnly = DateTime(at.year, at.month, at.day);

    final rows = await fetchStatement(
      customerId,
      to: dateOnly,
    );

    if (rows.isEmpty) {
      return const CustomerBalance(
        totalDebit: 0,
        totalCredit: 0,
        net: 0,
      );
    }

    double totalDebit = 0;
    double totalCredit = 0;
    for (final row in rows) {
      totalDebit += row.debit;
      totalCredit += row.credit;
    }

    final net = totalDebit - totalCredit;

    return CustomerBalance(
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      net: net,
    );
  }

  Future<void> createManualRefund({
    required String customerId,
    required double quantity,
    required String unit,
    required double unitPrice,
    String? note,
  }) async {
    assert(quantity > 0, 'quantity must be > 0');
    assert(unitPrice >= 0, 'unitPrice must be >= 0');
    final createdBy = _client.auth.currentUser?.id;

    final payload = <String, dynamic>{
      'customer_id': customerId,
      'quantity': quantity,
      'unit': unit,
      'unit_price': unitPrice,
      'note': note,
      if (createdBy != null) 'created_by': createdBy,
    };

    if (kDebugMode) {
      final supabase = Supabase.instance.client;

      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;

      // ignore: avoid_print
      print('==== AUTH DEBUG ====');
      // ignore: avoid_print
      print('Session: $session');
      // ignore: avoid_print
      print('AccessToken: ${session?.accessToken}');
      // ignore: avoid_print
      print('UserID: ${user?.id}');
      // ignore: avoid_print
      print('====================');
    }

    // Hata durumunda temel bilgiler için id döndürmek yeterli.
    await _guard(
      'ledger.createManualRefund',
      () async {
        try {
          await _client
              .from('customer_adjustments')
              .insert(payload)
              .select('id')
              .maybeSingle();
        } catch (e, st) {
          // ignore: avoid_print
          print('INSERT ERROR: $e');
          // ignore: avoid_print
          print(st);
          rethrow;
        }
      },
      fallbackMessage: 'İade kaydedilemedi. Lütfen tekrar deneyin.',
    );
  }

  Future<void> addPayment({
    required String customerId,
    required double amount,
    required PaymentMethod method,
    required DateTime date,
    String? description,
  }) async {
    await insertPayment(
      customerId: customerId,
      amount: amount,
      paymentMethod: method,
      paymentDate: date,
      description: description,
    );
  }

  Future<void> updatePayment({
    required String id,
    required double amount,
    required PaymentMethod method,
    required DateTime date,
    String? description,
  }) async {
    Map<String, dynamic>? oldValue;
    try {
      final row = await _client
          .from('customer_payments')
          .select(
            'id, customer_id, amount, payment_method, payment_date, description, is_cancelled, cancel_reason, created_at, updated_at',
          )
          .eq('id', id)
          .maybeSingle();
      if (row != null) {
        oldValue = Map<String, dynamic>.from(row as Map);
      }
    } catch (_) {
      // Best-effort: audit için old_value alınamazsa ana akışı bozma.
    }

    await _guard(
      'ledger.updatePayment',
      () => _client.from('customer_payments').update({
            'amount': amount,
            'payment_method': method.dbValue,
            'payment_date':
                DateTime(date.year, date.month, date.day).toIso8601String(),
            'description': description,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', id),
      fallbackMessage: 'Tahsilat güncellenemedi. Lütfen tekrar deneyin.',
    );

    unawaited(
      _audit.logChange(
        entity: 'payments',
        entityId: id,
        action: 'update',
        oldValue: oldValue,
        newValue: <String, dynamic>{
          'id': id,
          'customer_id': oldValue?['customer_id']?.toString(),
          'amount': amount,
          'payment_method': method.dbValue,
          'payment_date': DateTime(date.year, date.month, date.day)
              .toIso8601String(),
          'description': description,
        },
      ),
    );
  }

  Future<void> deletePayment(String id) async {
    // Geriye dönük uyumluluk için bırakıldı, artık gerçek silme yerine
    // iptal olarak ele alınıyor.
    await cancelPayment(id, 'Silme isteği');
  }

  /// Yeni tahsilat ekler (soft-insert).
  ///
  /// Not: payment_date sunucuda DATE kolonu, bu yüzden sadece yıl/ay/gün
  /// bilgisini gönderiyoruz.
  Future<void> insertPayment({
    required String customerId,
    required double amount,
    required PaymentMethod paymentMethod,
    required DateTime paymentDate,
    String? description,
  }) async {
    try {
      final supa = Supabase.instance.client;
      final session = supa.auth.currentSession;
      if (kDebugMode) {
        final uid = supa.auth.currentUser?.id;
        final token = session?.accessToken;
        final tokenPrefix = (token != null && token.length >= 12)
            ? token.substring(0, 12)
            : token;
        String? role;
        if (token != null) {
          try {
            final parts = token.split('.');
            if (parts.length >= 2) {
              final payload = utf8.decode(
                base64Url.decode(base64Url.normalize(parts[1])),
              );
              final decoded = jsonDecode(payload) as Map<String, dynamic>;
              final appMeta = decoded['app_metadata'] as Map<String, dynamic>?;
              role = appMeta?['role']?.toString();
            }
          } catch (e) {
            debugPrint('[PAYMENT][INSERT] jwt decode error: $e');
          }
        }

        debugPrint(
          '[PAYMENT][INSERT] session=${session != null} uid=$uid tokenPrefix=$tokenPrefix role=$role',
        );

        try {
          final isAdminResult = await supa.rpc('is_admin');
          debugPrint('[PAYMENT][INSERT] is_admin=$isAdminResult');
        } catch (e) {
          debugPrint('[PAYMENT][INSERT] is_admin RPC error: $e');
        }

        if (!_didCheckCustomerPaymentsSelect) {
          _didCheckCustomerPaymentsSelect = true;
          try {
            await supa.from('customer_payments').select('id').limit(1);
            debugPrint(
                '[PAYMENT][SANITY] select customer_payments succeeded (permission OK).');
          } on PostgrestException catch (e) {
            debugPrint(
                '[PAYMENT][SANITY] select customer_payments PostgrestException code=${e.code} message=${e.message}');
            if (e.details != null && e.details!.toString().isNotEmpty) {
              debugPrint('[PAYMENT][SANITY] details=${e.details}');
            }
            if (e.hint != null && e.hint!.toString().isNotEmpty) {
              debugPrint('[PAYMENT][SANITY] hint=${e.hint}');
            }
            debugPrint(
              '[PAYMENT][SANITY] Possible GRANT/RLS issue on customer_payments table.',
            );
          } catch (e) {
            debugPrint(
                '[PAYMENT][SANITY] select customer_payments unexpected error: $e');
          }
        }
      }

      final inserted = await _client.from('customer_payments').insert({
        'customer_id': customerId,
        'amount': amount,
        'payment_method': paymentMethod.dbValue,
        'payment_date': DateTime(
          paymentDate.year,
          paymentDate.month,
          paymentDate.day,
        ).toIso8601String(),
        'description': description,
        'is_cancelled': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).select(
        'id, customer_id, amount, payment_method, payment_date, description, is_cancelled, cancel_reason, created_at, updated_at',
      ).maybeSingle();

      Map<String, dynamic>? newValue;
      String entityId = 'unknown';
      if (inserted != null) {
        newValue = Map<String, dynamic>.from(inserted as Map);
        final id = newValue['id']?.toString();
        if (id != null && id.isNotEmpty) {
          entityId = id;
        }
      }

      unawaited(
        _audit.logChange(
          entity: 'payments',
          entityId: entityId,
          action: 'create',
          oldValue: null,
          newValue: newValue ?? <String, dynamic>{
            'customer_id': customerId,
            'amount': amount,
            'payment_method': paymentMethod.dbValue,
            'payment_date': DateTime(
              paymentDate.year,
              paymentDate.month,
              paymentDate.day,
            ).toIso8601String(),
            'description': description,
          },
        ),
      );
    } catch (e, st) {
      throw mapSupabaseError(
        e,
        st,
        operation: 'ledger.insertPayment',
        fallbackMessage: 'Tahsilat kaydedilemedi. Lütfen tekrar deneyin.',
      );
    }
  }

  /// Tahsilatı iptal eder (soft delete).
  Future<void> cancelPayment(String id, String reason) async {
    Map<String, dynamic>? oldValue;
    try {
      final row = await _client
          .from('customer_payments')
          .select(
            'id, customer_id, amount, payment_method, payment_date, description, is_cancelled, cancel_reason, created_at, updated_at',
          )
          .eq('id', id)
          .maybeSingle();
      if (row != null) {
        oldValue = Map<String, dynamic>.from(row as Map);
      }
    } catch (_) {
      // Best-effort: audit için old_value alınamazsa ana akışı bozma.
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await _guard(
      'ledger.cancelPayment',
      () => _client.from('customer_payments').update({
            'is_cancelled': true,
            'cancelled_at': now,
            'cancel_reason': reason,
            'updated_at': now,
          }).eq('id', id),
      fallbackMessage: 'Tahsilat iptal edilemedi. Lütfen tekrar deneyin.',
    );

    unawaited(
      _audit.logChange(
        entity: 'payments',
        entityId: id,
        action: 'delete',
        oldValue: oldValue,
        newValue: <String, dynamic>{
          'id': id,
          'is_cancelled': true,
          'cancelled_at': now,
          'cancel_reason': reason,
        },
      ),
    );
  }

  /// Tahsilat özeti (Toplam / Bugün / Bu Ay / Adet) döner.
  ///
  /// is_cancelled = false kayıtlar üzerinden hesaplama yapılır.
  Future<CustomerPaymentsSummary> fetchPaymentsSummary(
    String customerId,
  ) async {
    final effectiveCustomerId = customerId == '_all' ? null : customerId;

    final params = effectiveCustomerId != null
        ? <String, dynamic>{'p_customer_id': effectiveCustomerId}
        : null;

    final result = await _guard(
      'ledger.fetchPaymentsSummary',
      () => _client.rpc(
        'get_customer_payments_summary',
        params: params,
      ),
      fallbackMessage: 'Tahsilat özeti yüklenemedi. Lütfen tekrar deneyin.',
    );

    Map<String, dynamic> map;
    if (result is List && result.isNotEmpty) {
      map = Map<String, dynamic>.from(result.first as Map);
    } else if (result is Map) {
      map = Map<String, dynamic>.from(result);
    } else {
      throw AppException(
        'Tahsilat özeti beklenmeyen formatta geldi.',
        code: 'unexpected_response',
      );
    }

    final total = (map['total'] as num?)?.toDouble() ?? 0;
    final today = (map['today'] as num?)?.toDouble() ?? 0;
    final monthToDate = (map['month_to_date'] as num?)?.toDouble() ?? 0;
    final count = (map['count'] as num?)?.toInt() ?? 0;

    return CustomerPaymentsSummary(
      total: total,
      today: today,
      monthToDate: monthToDate,
      count: count,
    );
  }
}

final adminCustomerLedgerRepository =
    AdminCustomerLedgerRepository(client: supabaseClient);

class CustomerPaymentsSummary {
  const CustomerPaymentsSummary({
    required this.total,
    required this.today,
    required this.monthToDate,
    required this.count,
  });

  final double total;
  final double today;
  final double monthToDate;
  final int count;
}
