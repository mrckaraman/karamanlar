import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Son güncellenen siparişin id'sini tutar.
///
/// Orders list ve detay sayfaları bu provider'ı dinleyip
/// kendi FutureProvider'larını invalidate edebilir.
final customerOrdersRealtimeLastOrderIdProvider =
    StateProvider<String?>((ref) => null);

/// Mevcut müşteri için public.orders tablosuna realtime abone olur.
///
/// - INSERT ve UPDATE event'lerini dinler.
/// - customer_id = currentCustomerId filtresi uygular.
/// - Event'ler 300-400ms aralığında debounce edilerek
///   customerOrdersRealtimeLastOrderIdProvider'a yazılır.
final customerOrdersRealtimeProvider = Provider.autoDispose<void>((ref) {
  final client = supabaseClient;
  final customerId = ref.watch(customerIdProvider);

  if (customerId == null || customerId.isEmpty) {
    if (kDebugMode) {
      debugPrint('[ORDERS-RT] customerId yok, abonelik açılmadı.');
    }
    return;
  }

  if (kDebugMode) {
    debugPrint('[ORDERS-RT] Subscribing for customer_id=$customerId');
  }

  String? pendingOrderId;
  Timer? debounceTimer;

  void handlePayload(PostgresChangePayload payload) {
    try {
      final newRow = payload.newRecord;

      final dynamic rawId = newRow['id'];
      final orderId = rawId is String ? rawId : rawId?.toString();
      if (orderId == null || orderId.isEmpty) {
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '[ORDERS-RT] ${payload.eventType.name.toUpperCase()} order_id=$orderId status=${newRow['status']}',
        );
      }

      pendingOrderId = orderId;
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(milliseconds: 350), () {
        final id = pendingOrderId;
        if (id == null || id.isEmpty) return;
        ref.read(customerOrdersRealtimeLastOrderIdProvider.notifier).state =
            id;
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[ORDERS-RT] callback error: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  final channel = client
      .channel('public:orders:customer:$customerId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'customer_id',
          value: customerId,
        ),
        callback: handlePayload,
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'customer_id',
          value: customerId,
        ),
        callback: handlePayload,
      )
      .subscribe();

  ref.onDispose(() {
    if (kDebugMode) {
      debugPrint('[ORDERS-RT] Disposing channel for customer_id=$customerId');
    }
    try {
      debounceTimer?.cancel();
      client.removeChannel(channel);
    } catch (_) {
      // ignore
    }
  });
});
