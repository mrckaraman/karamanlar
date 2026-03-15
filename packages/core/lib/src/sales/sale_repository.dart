import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';

class SaleDraft {
  const SaleDraft({
    required this.customerId,
    required this.stockId,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.totalAmount,
    this.batchId,
  });

  final String customerId;
  final String stockId;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double totalAmount;
  final String? batchId;
}

class SaleRepository {
  const SaleRepository(this._client);

  final SupabaseClient _client;

  /// RPC: create_sale_v1
  ///
  /// Beklenen Supabase fonksiyon parametreleri:
  /// - p_customer_id
  /// - p_stock_id
  /// - p_unit
  /// - p_quantity
  /// - p_unit_price
  /// - p_note
  ///
  /// Başarılı çağrıda oluşturulan satışın `sale_id` değerini döner.
  Future<String> createSale({
    required String customerId,
    required String stockId,
    required String unit,
    required double quantity,
    required double unitPrice,
    String? note,
  }) async {
    final params = <String, dynamic>{
      'p_customer_id': customerId,
      'p_stock_id': stockId,
      'p_unit': unit,
      'p_quantity': quantity,
      'p_unit_price': unitPrice,
      'p_note': note,
    };

    try {
      final result = await _client.rpc('create_sale_v1', params: params);

      if (result == null) {
        throw Exception('Satış oluşturulamadı: RPC sonucu null döndü.');
      }

      // Olası dönüş senaryolarını esnek şekilde ele al.
      if (result is String) {
        return result;
      }

      if (result is Map<String, dynamic>) {
        final saleId = result['sale_id'];
        if (saleId is String && saleId.isNotEmpty) {
          return saleId;
        }
      }

      if (result is List && result.isNotEmpty) {
        final first = result.first;
        if (first is Map<String, dynamic>) {
          final saleId = first['sale_id'];
          if (saleId is String && saleId.isNotEmpty) {
            return saleId;
          }
        }
      }

      throw Exception('Satış oluşturulamadı: Beklenmeyen RPC yanıtı.');
    } on PostgrestException catch (e) {
      throw Exception('Satış oluşturulamadı: ${e.message}');
    } catch (e) {
      throw Exception('Satış oluşturulamadı: $e');
    }
  }

  /// Bir müşteriye ait birden fazla satış satırını tek bir operasyon
  /// altında oluşturmak için yardımcı metot.
  ///
  /// Not: Gerçek anlamda atomik bir işlem için bu mantığın Supabase tarafında
  /// tek bir RPC/fonksiyon içinde, transaction kullanarak uygulanması gerekir.
  /// Bu metot, UI seviyesinde tek bir "Satışı Tamamla" akışı sağlamak için
  /// satırları sırayla oluşturur ve ilk hatada istisna fırlatır.
  Future<List<String>> createSalesBatch({
    required String customerId,
    required List<SaleDraft> lines,
  }) async {
    if (lines.isEmpty) {
      throw Exception('En az bir satış satırı gereklidir.');
    }

    final ids = <String>[];

    try {
      for (final line in lines) {
        final note =
            line.batchId == null ? null : 'BATCH:${line.batchId}';
        final saleId = await createSale(
          customerId: customerId,
          stockId: line.stockId,
          unit: line.unit,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          note: note,
        );
        ids.add(saleId);
      }

      return ids;
    } catch (e) {
      throw Exception('Satış satırları oluşturulamadı: $e');
    }
  }

  /// POS tek tuş fatura akışı için RPC:
  ///   rpc_pos_create_invoice(p_customer_id uuid, p_items jsonb) -> invoice_id
  ///
  /// Beklenen p_items formatı örneği:
  /// [
  ///   {
  ///     "stock_id": "...", // uuid
  ///     "qty": 1.0,
  ///     "unit_name": "Adet",
  ///     "unit_price": 100.0,
  ///   },
  /// ]
  Future<String> createPosInvoice({
    required String customerId,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) {
      throw Exception('En az bir satış kalemi gereklidir.');
    }

    final params = <String, dynamic>{
      'p_customer_id': customerId,
      'p_items': items,
    };

    try {
      final result = await _client.rpc('rpc_pos_create_invoice', params: params);

      if (result == null) {
        throw Exception('POS faturası oluşturulamadı: RPC sonucu null döndü.');
      }

      // Olası dönüş şekillerini esnek biçimde ele al.
      if (result is String) {
        return result;
      }

      if (result is Map<String, dynamic>) {
        final invoiceId = result['invoice_id'] ?? result['id'];
        if (invoiceId is String && invoiceId.isNotEmpty) {
          return invoiceId;
        }
      }

      if (result is List && result.isNotEmpty) {
        final first = result.first;
        if (first is Map<String, dynamic>) {
          final invoiceId = first['invoice_id'] ?? first['id'];
          if (invoiceId is String && invoiceId.isNotEmpty) {
            return invoiceId;
          }
        }
      }

      throw Exception('POS faturası oluşturulamadı: Beklenmeyen RPC yanıtı.');
    } on PostgrestException catch (e) {
      throw Exception('POS faturası oluşturulamadı: ${e.message}');
    } catch (e) {
      throw Exception('POS faturası oluşturulamadı: $e');
    }
  }
}
 
final saleRepository = SaleRepository(supabaseClient);
